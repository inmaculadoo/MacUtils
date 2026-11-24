import AppKit
import Darwin
import IOKit
import IOKit.ps
import LigeroCore

/// Reads the raw system counters. Every call is a one-off read; nothing here
/// schedules work on its own.
enum SystemSampler {
    /// mach_host_self() adds a port reference on every call, so it is read once.
    private static let host = mach_host_self()

    /// Whole-machine CPU ticks. HOST_CPU_LOAD_INFO needs no allocation
    /// (unlike per-core host_processor_info, which must be vm_deallocate'd).
    static func cpuTicks() -> [CPUTicks] {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return [] }
        let t = load.cpu_ticks
        return [CPUTicks(user: t.0, system: t.1, idle: t.2, nice: t.3)]
    }

    static func memory() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return MemoryStats.from(
            pageSize: UInt64(getpagesize()),
            total: ProcessInfo.processInfo.physicalMemory,
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            pressureLevel: Int(level)
        )
    }

    static func battery() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return BatteryInfo.parse(dict)
    }

    static func network() -> [String: NetworkCounters] {
        var result: [String: NetworkCounters] = [:]
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return result }
        defer { freeifaddrs(first) }
        var cursor = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.pointee.ifa_data else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            result[name] = NetworkCounters(received: UInt64(stats.ifi_ibytes), sent: UInt64(stats.ifi_obytes))
        }
        return result
    }

    /// Energy of every process we can read (`proc_pid_rusage`). Uses
    /// `ri_energy_nj`: `ri_billed_energy` stays at 0 on recent macOS.
    static func energy() -> [ProcessEnergySample] {
        let capacity = 4096
        var pids = [pid_t](repeating: 0, count: capacity)
        let n = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard n > 0 else { return [] }
        var samples: [ProcessEnergySample] = []
        samples.reserveCapacity(Int(n))
        var nameBuffer = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(n)) where pid > 0 {
            var info = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard ok == 0 else { continue }
            let len = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = len > 0 ? nameBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : String(pid)
            samples.append(ProcessEnergySample(pid: pid, name: name, energy: info.ri_energy_nj))
        }
        return samples
    }
}
