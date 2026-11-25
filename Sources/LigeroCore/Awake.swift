import Foundation

/// How long a manual "keep awake" lasts (SPEC §4.13).
public enum AwakeDuration: String, CaseIterable, Codable, Sendable {
    case minutes30, hour1, hours2, hours5, indefinitely

    /// Seconds, or nil for "until I turn it off".
    public var seconds: Double? {
        switch self {
        case .minutes30: return 30 * 60
        case .hour1: return 60 * 60
        case .hours2: return 2 * 60 * 60
        case .hours5: return 5 * 60 * 60
        case .indefinitely: return nil
        }
    }

    public var titleKey: String { "awake.duration.\(rawValue)" }
}

/// A manual session. `until` nil means until the user turns it off.
public struct AwakeSession: Equatable, Sendable {
    public var until: Date?

    public init(duration: AwakeDuration, now: Date) {
        until = duration.seconds.map { now.addingTimeInterval($0) }
    }

    /// The system releases a timed assertion on its own (no timer in the
    /// app), so "still on" is only ever asked when the menu opens.
    public func isActive(at now: Date) -> Bool {
        until.map { now < $0 } ?? true
    }
}

/// What keeps the Mac awake right now.
public enum AwakeReason: Equatable, Sendable {
    case off
    case session(AwakeSession)
    /// A trigger app is open (bundle ids of the open ones, sorted).
    case apps([String])
}

public enum AwakePlanner {
    /// Trigger apps that are open, in a stable order.
    public static func openTriggers(_ triggers: [String], running: Set<String>) -> [String] {
        triggers.filter { running.contains($0) }.sorted()
    }

    /// A manual session wins over trigger apps (it is what the user just
    /// asked for); otherwise any open trigger app keeps the Mac awake.
    public static func reason(session: AwakeSession?, triggers: [String], running: Set<String>, now: Date) -> AwakeReason {
        if let session, session.isActive(at: now) { return .session(session) }
        let open = openTriggers(triggers, running: running)
        return open.isEmpty ? .off : .apps(open)
    }
}

/// Settings of the Awake module.
public struct AwakeSettings: ModuleSettings {
    /// Keep the display on too (otherwise only the Mac stays awake and the
    /// screen still turns off, which saves the most battery).
    public var keepDisplayOn: Bool
    /// Bundle ids that keep the Mac awake while they are open.
    public var triggerApps: [String]
    /// Toggles "until I turn it off".
    public var shortcut: KeyCombo?

    public init(keepDisplayOn: Bool, triggerApps: [String], shortcut: KeyCombo?) {
        self.keepDisplayOn = keepDisplayOn
        self.triggerApps = triggerApps
        self.shortcut = shortcut
    }

    public static let `default` = AwakeSettings(
        keepDisplayOn: false, triggerApps: [],
        shortcut: KeyCombo(keyCode: KeyCode.a, modifiers: [.control, .option, .command])
    )

    public mutating func toggleTrigger(_ bundleID: String) {
        if let i = triggerApps.firstIndex(of: bundleID) {
            triggerApps.remove(at: i)
        } else {
            triggerApps.append(bundleID)
        }
    }

    enum CodingKeys: String, CodingKey { case keepDisplayOn, triggerApps, shortcut }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keepDisplayOn = c.value(.keepDisplayOn, or: false)
        triggerApps = c.value(.triggerApps, or: [])
        shortcut = c.contains(.shortcut) ? c.value(.shortcut, or: nil) : Self.default.shortcut
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keepDisplayOn, forKey: .keepDisplayOn)
        try c.encode(triggerApps, forKey: .triggerApps)
        try c.encode(shortcut, forKey: .shortcut) // explicit null = "no shortcut"
    }
}
