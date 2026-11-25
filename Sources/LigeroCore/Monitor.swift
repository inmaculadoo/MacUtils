import Foundation

/// Settings of the Monitor module (SPEC §4.10).
public struct MonitorSettings: ModuleSettings {
    /// Small CPU/RAM reading in the menu bar. Off by default because it is the
    /// only thing in Ligero that wakes up periodically.
    public var menuBarReading: Bool
    /// Seconds between menu bar updates (at least 10, tolerance 50 %).
    public var menuBarInterval: Double

    public init(menuBarReading: Bool, menuBarInterval: Double) {
        self.menuBarReading = menuBarReading
        self.menuBarInterval = menuBarInterval
    }

    public static let minimumInterval: Double = 10
    public static let `default` = MonitorSettings(menuBarReading: false, menuBarInterval: 10)

    public var clampedInterval: Double { max(Self.minimumInterval, menuBarInterval) }

    enum CodingKeys: String, CodingKey { case menuBarReading, menuBarInterval }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarReading = c.value(.menuBarReading, or: false)
        menuBarInterval = c.value(.menuBarInterval, or: Self.default.menuBarInterval)
    }
}

// MARK: - CPU

/// Cumulative ticks of one core (`host_processor_info`, CPU_STATE_*).
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum CPUUsage {
    /// Busy fraction (0…1) of each core and of the whole CPU between two
    /// samples. Counters are 32-bit and wrap; wrapping subtraction handles it.
    public static func between(_ old: [CPUTicks], _ new: [CPUTicks]) -> (total: Double, perCore: [Double]) {
        guard old.count == new.count, !new.isEmpty else { return (0, []) }
        var busyAll = 0.0
        var allAll = 0.0
        var cores: [Double] = []
        for (a, b) in zip(old, new) {
            let user = Double(b.user &- a.user)
            let system = Double(b.system &- a.system)
            let nice = Double(b.nice &- a.nice)
            let idle = Double(b.idle &- a.idle)
            let busy = user + system + nice
            let all = busy + idle
            cores.append(all > 0 ? busy / all : 0)
            busyAll += busy
            allAll += all
        }
        return (allAll > 0 ? busyAll / allAll : 0, cores)
    }
}

// MARK: - Memory

public struct MemoryStats: Equatable, Sendable {
    public enum Pressure: Int, Sendable {
        case normal = 1, warning = 2, critical = 4
    }

    public var total: UInt64
    public var used: UInt64
    public var compressed: UInt64
    public var wired: UInt64
    public var pressure: Pressure

    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Activity Monitor's "Memory Used": app memory (internal − purgeable) +
    /// wired + compressed. Inputs are page counts from `vm_statistics64`.
    public static func from(pageSize: UInt64, total: UInt64, internalPages: UInt64, purgeablePages: UInt64,
                            wiredPages: UInt64, compressedPages: UInt64, pressureLevel: Int) -> MemoryStats {
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let used = min(total, (app + wiredPages + compressedPages) * pageSize)
        return MemoryStats(
            total: total, used: used,
            compressed: compressedPages * pageSize, wired: wiredPages * pageSize,
            pressure: Pressure(rawValue: pressureLevel) ?? .normal
        )
    }
}

// MARK: - Battery

public struct BatteryInfo: Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    public var externalPower: Bool
    public var fullyCharged: Bool
    public var cycleCount: Int?
    /// Max capacity relative to design capacity, in %.
    public var health: Int?
    /// Positive while charging, negative while discharging.
    public var watts: Double?
    /// Minutes to empty (on battery) or to full (charging); nil while macOS is
    /// still calculating.
    public var minutesRemaining: Int?

    /// Parses the `AppleSmartBattery` IORegistry properties.
    public static func parse(_ d: [String: Any]) -> BatteryInfo? {
        guard let current = int(d["CurrentCapacity"]) else { return nil }
        let max = int(d["MaxCapacity"]) ?? 100
        let charging = bool(d["IsCharging"]) ?? false
        let external = bool(d["ExternalConnected"]) ?? false
        var percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
        // Apple Silicon reports CurrentCapacity already in % with MaxCapacity 100.
        percent = Swift.min(100, Swift.max(0, percent))

        // Recent macOS keeps the capacities only inside "BatteryData". The
        // nominal capacity matches System Settings' "Maximum Capacity" best;
        // the raw one reads a few points lower.
        let nested = d["BatteryData"] as? [String: Any] ?? [:]
        func capacity(_ key: String) -> Int? { int(d[key]) ?? int(nested[key]) }
        let full = capacity("NominalChargeCapacity") ?? capacity("AppleRawMaxCapacity")
        let design = capacity("DesignCapacity")
        var health: Int?
        if let full, let design, design > 0 {
            health = Swift.min(100, Int((Double(full) / Double(design) * 100).rounded()))
        }

        var watts: Double?
        if let mv = int(d["Voltage"]), let ma = int(d["InstantAmperage"]) ?? int(d["Amperage"]) {
            watts = Double(mv) * Double(ma) / 1_000_000
        }

        let raw = charging ? int(d["AvgTimeToFull"]) ?? int(d["TimeRemaining"]) : int(d["AvgTimeToEmpty"]) ?? int(d["TimeRemaining"])
        let minutes = raw.flatMap { ($0 <= 0 || $0 >= 65535) ? nil : $0 }

        return BatteryInfo(
            percent: percent, isCharging: charging, externalPower: external,
            fullyCharged: bool(d["FullyCharged"]) ?? false,
            cycleCount: int(d["CycleCount"]), health: health, watts: watts,
            minutesRemaining: (external && !charging) ? nil : minutes
        )
    }

    /// IOKit returns signed amperage as an unsigned 64-bit pattern on some
    /// machines, so values above Int64.max are reinterpreted.
    static func int(_ v: Any?) -> Int? {
        switch v {
        case let i as Int: return i
        case let i as Int64: return Int(i)
        case let i as Int32: return Int(i)
        case let u as UInt64: return Int(Int64(bitPattern: u))
        case let u as UInt: return Int(Int64(bitPattern: UInt64(u)))
        case let d as Double: return Int(d)
        case let n as NSNumber: return Int(Int64(bitPattern: n.uint64Value))
        default: return nil
        }
    }

    static func bool(_ v: Any?) -> Bool? {
        switch v {
        case let b as Bool: return b
        case let i as Int: return i != 0
        case let n as NSNumber: return n.boolValue
        default: return nil
        }
    }

    /// "3:07" style duration.
    public static func hoursMinutes(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

// MARK: - Network

public struct NetworkCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }

    /// Interfaces that carry real traffic. Loopback, tunnels (which would
    /// count VPN traffic twice) and AirDrop/peer links are left out.
    public static func counts(interface name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    /// Sums the interfaces that count.
    public static func total(_ perInterface: [String: NetworkCounters]) -> NetworkCounters {
        var r = NetworkCounters(received: 0, sent: 0)
        for (name, c) in perInterface where counts(interface: name) {
            r.received &+= c.received
            r.sent &+= c.sent
        }
        return r
    }

    /// Bytes per second between two samples, per interface so that one
    /// counter wrapping (if_data uses 32 bits) does not spoil the others.
    public static func rate(from old: [String: NetworkCounters], to new: [String: NetworkCounters], seconds: Double) -> (down: Double, up: Double) {
        guard seconds > 0 else { return (0, 0) }
        var down: UInt64 = 0
        var up: UInt64 = 0
        for (name, b) in new where counts(interface: name) {
            guard let a = old[name] else { continue }
            down &+= delta(a.received, b.received)
            up &+= delta(a.sent, b.sent)
        }
        return (Double(down) / seconds, Double(up) / seconds)
    }

    static func delta(_ a: UInt64, _ b: UInt64) -> UInt64 {
        if b >= a { return b - a }
        // 32-bit wrap; anything else (interface reset) counts as zero.
        if a <= UInt64(UInt32.max) { return (UInt64(UInt32.max) - a) + b + 1 }
        return 0
    }
}

// MARK: - Energy

/// Cumulative CPU time of one process (`proc_pid_rusage` user + system).
///
/// The per-process energy counters (`ri_energy_nj`, `ri_billed_energy`) stay
/// at or near 0 for almost every process on macOS 27, so the panel ranks by
/// CPU time instead, which is what drives most of an app's energy use.
public struct ProcessCPUSample: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    /// Nanoseconds of CPU time since the process started.
    public var cpuNanoseconds: UInt64

    public init(pid: Int32, name: String, cpuNanoseconds: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuNanoseconds = cpuNanoseconds
    }
}

public struct CPUUser: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    /// Share of one core between the two samples (1 = one core fully busy;
    /// can exceed 1 for multithreaded work), like Activity Monitor's % CPU.
    public var cores: Double
}

public enum CPURanking {
    /// Processes that used the most CPU between two samples. Processes that
    /// appeared or restarted (counter went down) are skipped, and so is
    /// anything under 0.5 % of a core (noise).
    public static func top(_ old: [ProcessCPUSample], _ new: [ProcessCPUSample], seconds: Double, limit: Int = 5) -> [CPUUser] {
        guard seconds > 0 else { return [] }
        var previous: [Int32: UInt64] = [:]
        for s in old { previous[s.pid] = s.cpuNanoseconds }
        var users: [CPUUser] = []
        for s in new {
            guard let t0 = previous[s.pid], s.cpuNanoseconds > t0 else { continue }
            let cores = Double(s.cpuNanoseconds - t0) / 1e9 / seconds
            if cores >= 0.005 { users.append(CPUUser(pid: s.pid, name: s.name, cores: cores)) }
        }
        users.sort { $0.cores != $1.cores ? $0.cores > $1.cores : $0.pid < $1.pid }
        return Array(users.prefix(limit))
    }
}

/// GPU load from the IOAccelerator's "PerformanceStatistics" (Apple Silicon).
public struct GPUStats: Equatable, Sendable {
    /// 0…1, "Device Utilization %".
    public var utilization: Double
    /// Memory the GPU has in use, in bytes ("In use system memory").
    public var memoryInUse: UInt64?

    public static func parse(_ stats: [String: Any]) -> GPUStats? {
        guard let device = BatteryInfo.int(stats["Device Utilization %"]) else { return nil }
        let memory = BatteryInfo.int(stats["In use system memory"]).map { UInt64(max(0, $0)) }
        return GPUStats(utilization: Double(min(max(device, 0), 100)) / 100, memoryInUse: memory)
    }
}
