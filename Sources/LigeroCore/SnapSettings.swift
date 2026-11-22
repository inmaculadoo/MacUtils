/// Settings of the Snap module.
public struct SnapSettings: ModuleSettings {
    public var shortcuts: [SnapAction: KeyCombo]
    public var gap: Double
    public var cycleHalves: Bool

    public init(shortcuts: [SnapAction: KeyCombo], gap: Double, cycleHalves: Bool) {
        self.shortcuts = shortcuts
        self.gap = gap
        self.cycleHalves = cycleHalves
    }

    public static let maxGap: Double = 40

    public var options: SnapEngine.Options {
        SnapEngine.Options(gap: min(max(gap, 0), Self.maxGap), cycleHalves: cycleHalves)
    }

    /// Rectangle-style defaults: ⌃⌥ plus an arrow or a letter.
    public static let defaultShortcuts: [SnapAction: KeyCombo] = {
        let co: KeyCombo.Modifiers = [.control, .option]
        return [
            .leftHalf: KeyCombo(keyCode: KeyCode.leftArrow, modifiers: co),
            .rightHalf: KeyCombo(keyCode: KeyCode.rightArrow, modifiers: co),
            .topHalf: KeyCombo(keyCode: KeyCode.upArrow, modifiers: co),
            .bottomHalf: KeyCombo(keyCode: KeyCode.downArrow, modifiers: co),
            .topLeft: KeyCombo(keyCode: KeyCode.u, modifiers: co),
            .topRight: KeyCombo(keyCode: KeyCode.i, modifiers: co),
            .bottomLeft: KeyCombo(keyCode: KeyCode.j, modifiers: co),
            .bottomRight: KeyCombo(keyCode: KeyCode.k, modifiers: co),
            .firstThird: KeyCombo(keyCode: KeyCode.d, modifiers: co),
            .centerThird: KeyCombo(keyCode: KeyCode.f, modifiers: co),
            .lastThird: KeyCombo(keyCode: KeyCode.g, modifiers: co),
            .firstTwoThirds: KeyCombo(keyCode: KeyCode.e, modifiers: co),
            .lastTwoThirds: KeyCombo(keyCode: KeyCode.t, modifiers: co),
            .maximize: KeyCombo(keyCode: KeyCode.returnKey, modifiers: co),
            .maximizeHeight: KeyCombo(keyCode: KeyCode.upArrow, modifiers: [.control, .option, .shift]),
            .center: KeyCombo(keyCode: KeyCode.c, modifiers: co),
            .nextDisplay: KeyCombo(keyCode: KeyCode.rightArrow, modifiers: [.control, .option, .command]),
            .previousDisplay: KeyCombo(keyCode: KeyCode.leftArrow, modifiers: [.control, .option, .command]),
            .restore: KeyCombo(keyCode: KeyCode.delete, modifiers: co),
        ]
    }()

    public static let `default` = SnapSettings(shortcuts: defaultShortcuts, gap: 0, cycleHalves: true)

    /// Assigns `combo` to `action`, removing it from any other action so that
    /// two actions never share a shortcut. A nil combo clears the action.
    public mutating func assign(_ combo: KeyCombo?, to action: SnapAction) {
        if let combo {
            for (other, existing) in shortcuts where existing == combo && other != action {
                shortcuts[other] = nil
            }
        }
        shortcuts[action] = combo
    }

    // Stored as [rawValue: combo] so an action removed in a later version is
    // simply skipped instead of breaking the whole blob.
    enum CodingKeys: String, CodingKey { case shortcuts, gap, cycleHalves }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw: [String: KeyCombo]? = c.value(.shortcuts, or: nil)
        if let raw {
            var map: [SnapAction: KeyCombo] = [:]
            for (k, v) in raw {
                if let action = SnapAction(rawValue: k) { map[action] = v }
            }
            shortcuts = map
        } else {
            shortcuts = Self.defaultShortcuts
        }
        gap = c.value(.gap, or: Self.default.gap)
        cycleHalves = c.value(.cycleHalves, or: Self.default.cycleHalves)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let raw = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        try c.encode(raw, forKey: .shortcuts)
        try c.encode(gap, forKey: .gap)
        try c.encode(cycleHalves, forKey: .cycleHalves)
    }
}
