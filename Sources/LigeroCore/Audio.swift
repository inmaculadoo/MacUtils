/// Per-app audio settings and the real-time DSP of the Audio module
/// (SPEC §4.11). The DSP functions work on raw pointers and never allocate,
/// lock or call into Swift concurrency, so they are safe in an IOProc.

public struct AppAudioSetting: Codable, Equatable, Sendable {
    /// 0…1.5 (0 – 150 %).
    public var volume: Double
    public var muted: Bool
    /// Output device UID; nil = follow the system default output.
    public var outputUID: String?

    public init(volume: Double = 1, muted: Bool = false, outputUID: String? = nil) {
        self.volume = volume
        self.muted = muted
        self.outputUID = outputUID
    }

    public static let maxVolume = 1.5
    public static let neutral = AppAudioSetting()
}

public struct AudioSettings: ModuleSettings {
    /// Keyed by bundle id.
    public var apps: [String: AppAudioSetting]

    public init(apps: [String: AppAudioSetting]) {
        self.apps = apps
    }

    public static let `default` = AudioSettings(apps: [:])

    enum CodingKeys: String, CodingKey { case apps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = c.value(.apps, or: [:])
    }

    /// Stores a setting; neutral settings are removed so that the blob only
    /// holds apps the user actually changed.
    public mutating func set(_ setting: AppAudioSetting, for bundleID: String) {
        if AudioRouting.isNeutral(setting) { apps.removeValue(forKey: bundleID) } else { apps[bundleID] = setting }
    }
}

public enum AudioRouting {
    public static func isNeutral(_ s: AppAudioSetting) -> Bool {
        !s.muted && abs(s.volume - 1) < 0.005 && s.outputUID == nil
    }

    /// A process tap exists only for an app that is playing AND whose volume
    /// is not 100 % or whose output is redirected (SPEC §4.11).
    public static func needsTap(_ s: AppAudioSetting?, isPlaying: Bool, defaultOutputUID: String?) -> Bool {
        guard isPlaying, let s else { return false }
        if s.muted || abs(s.volume - 1) >= 0.005 { return true }
        if let out = s.outputUID, out != defaultOutputUID { return true }
        return false
    }

    /// Device the tap's aggregate should play to.
    public static func outputUID(for s: AppAudioSetting, defaultOutputUID: String?) -> String? {
        s.outputUID ?? defaultOutputUID
    }

    public static func gain(for s: AppAudioSetting) -> Float {
        s.muted ? 0 : Float(min(max(s.volume, 0), AppAudioSetting.maxVolume))
    }
}

public enum AudioDSP {
    /// out[i] = clamp(in[i] * gain, -1, 1). `input` and `output` may alias.
    @inline(__always)
    public static func apply(gain: Float, input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, count: Int) {
        var i = 0
        while i < count {
            let v = input[i] * gain
            output[i] = v > 1 ? 1 : (v < -1 ? -1 : v)
            i += 1
        }
    }

    /// Interleaved stereo in, two planar channels out.
    @inline(__always)
    public static func deinterleave(gain: Float, input: UnsafePointer<Float>, left: UnsafeMutablePointer<Float>,
                                    right: UnsafeMutablePointer<Float>, frames: Int) {
        var f = 0
        while f < frames {
            let l = input[2 * f] * gain
            let r = input[2 * f + 1] * gain
            left[f] = l > 1 ? 1 : (l < -1 ? -1 : l)
            right[f] = r > 1 ? 1 : (r < -1 ? -1 : r)
            f += 1
        }
    }

    @inline(__always)
    public static func silence(_ output: UnsafeMutablePointer<Float>, count: Int) {
        var i = 0
        while i < count {
            output[i] = 0
            i += 1
        }
    }

    /// Float ↔ UInt32 bit pattern, to keep the gain in an atomic word.
    @inline(__always)
    public static func bits(_ gain: Float) -> UInt32 { gain.bitPattern }
    @inline(__always)
    public static func gain(_ bits: UInt32) -> Float { Float(bitPattern: bits) }
}
