import AudioToolbox
import CoreAudio
import Foundation
import LigeroCore
import Synchronization

/// Thin Core Audio helpers. Everything here runs on the main thread except
/// the IOProc block in `ProcessTap`.
enum CoreAudioHAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var addr = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == OSStatus(noErr), size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &list) == OSStatus(noErr) else { return [] }
        return list
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var addr = address(selector, scope: scope)
        var v = initial
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &v) == OSStatus(noErr) else { return nil }
        return v
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == OSStatus(noErr), let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static var defaultOutputDevice: AudioDeviceID? {
        value(system, kAudioHardwarePropertyDefaultOutputDevice, AudioDeviceID(0)).flatMap { $0 == 0 ? nil : $0 }
    }

    static var defaultOutputUID: String? {
        defaultOutputDevice.flatMap { string($0, kAudioDevicePropertyDeviceUID) }
    }

    struct OutputDevice: Hashable {
        let uid: String
        let name: String
    }

    /// Devices with output streams, excluding Ligero's own private aggregates.
    static func outputDevices() -> [OutputDevice] {
        ids(system, kAudioHardwarePropertyDevices).compactMap { id in
            guard !ids(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput).isEmpty,
                  let uid = string(id, kAudioDevicePropertyDeviceUID), !uid.hasPrefix(ProcessTap.uidPrefix),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return OutputDevice(uid: uid, name: name)
        }
    }

    /// An audio client process (macOS 14.2+ process objects).
    struct Process: Equatable {
        let object: AudioObjectID
        let pid: pid_t
        let bundleID: String
        let isPlaying: Bool
    }

    /// Audio clients other than Ligero itself: Ligero shows up too once it
    /// plays a sound (Capture's "Pop") or hosts a tap, and must never be
    /// listed in the mixer nor tapped.
    static func processes() -> [Process] {
        let me = getpid()
        return ids(system, kAudioHardwarePropertyProcessObjectList).compactMap { object in
            guard let pid = value(object, kAudioProcessPropertyPID, pid_t(0)), pid > 0, pid != me,
                  let bundle = string(object, kAudioProcessPropertyBundleID), !bundle.isEmpty else { return nil }
            let running = value(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0
            return Process(object: object, pid: pid, bundleID: bundle, isPlaying: running != 0)
        }
    }
}

/// Gain shared between the main thread and the real-time IOProc through a
/// single atomic word: no lock, no allocation.
final class GainBox: Sendable {
    let bits: Atomic<UInt32>

    init(_ gain: Float) {
        bits = Atomic(AudioDSP.bits(gain))
    }

    func set(_ gain: Float) {
        bits.store(AudioDSP.bits(gain), ordering: .relaxed)
    }
}

/// One app's process tap + private aggregate device + IOProc.
///
/// The tap mutes the app's own output (`mutedWhenTapped`) and the IOProc
/// writes the tapped audio, multiplied by the gain, to the aggregate's output
/// device. Created only while needed and destroyed as soon as the app stops
/// playing or goes back to 100 % on the default output.
final class ProcessTap {
    static let uidPrefix = "app.allinone.aggregate."

    let bundleID: String
    let outputUID: String
    let gain: GainBox
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init?(process: AudioObjectID, bundleID: String, outputUID: String, gain: Float) {
        self.bundleID = bundleID
        self.outputUID = outputUID
        self.gain = GainBox(gain)

        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == OSStatus(noErr) else { return nil }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Ligero \(bundleID)",
            kAudioAggregateDeviceUIDKey: Self.uidPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == OSStatus(noErr) else {
            destroy()
            return nil
        }

        let box = self.gain
        // REAL-TIME: no allocation, no locks, no Swift concurrency.
        // Only pointer arithmetic over the buffers CoreAudio hands us.
        let block: AudioDeviceIOBlock = { _, inputData, _, outputData, _ in
            let g = AudioDSP.gain(box.bits.load(ordering: .relaxed))
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let outputs = UnsafeMutableAudioBufferListPointer(outputData)
            ProcessTap.render(gain: g, inputs: inputs, outputs: outputs)
        }
        guard AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, block) == OSStatus(noErr), let procID,
              AudioDeviceStart(aggregateID, procID) == OSStatus(noErr) else {
            destroy()
            return nil
        }
    }

    /// Copies tapped audio to the output with gain. Handles the same layout on
    /// both sides and interleaved stereo → two planar channels.
    @inline(__always)
    static func render(gain: Float, inputs: UnsafeMutableAudioBufferListPointer, outputs: UnsafeMutableAudioBufferListPointer) {
        let inCount = inputs.count
        for o in 0..<outputs.count {
            let out = outputs[o]
            guard let dst = out.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let dstCount = Int(out.mDataByteSize) / MemoryLayout<Float>.size
            guard inCount > 0 else {
                AudioDSP.silence(dst, count: dstCount)
                continue
            }
            let input = inputs[min(o, inCount - 1)]
            guard let src = input.mData?.assumingMemoryBound(to: Float.self) else {
                AudioDSP.silence(dst, count: dstCount)
                continue
            }
            let srcCount = Int(input.mDataByteSize) / MemoryLayout<Float>.size
            if inCount == 1, input.mNumberChannels == 2, outputs.count == 2, out.mNumberChannels == 1, o == 0,
               let right = outputs[1].mData?.assumingMemoryBound(to: Float.self) {
                let frames = min(srcCount / 2, dstCount, Int(outputs[1].mDataByteSize) / MemoryLayout<Float>.size)
                AudioDSP.deinterleave(gain: gain, input: src, left: dst, right: right, frames: frames)
                return
            }
            let n = min(srcCount, dstCount)
            AudioDSP.apply(gain: gain, input: src, output: dst, count: n)
            if dstCount > n { AudioDSP.silence(dst + n, count: dstCount - n) }
        }
    }

    func destroy() {
        if let procID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
