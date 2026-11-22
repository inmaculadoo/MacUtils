/// Settings and state of the MenuBar module (SPEC §4.7).
public struct MenuBarSettings: ModuleSettings {
    public var shortcut: KeyCombo?
    /// Second separator further left whose items stay hidden unless you ⌥-click.
    public var alwaysHiddenSection: Bool
    /// Hide the icons again when you switch to another app.
    public var autoHide: Bool

    public init(shortcut: KeyCombo?, alwaysHiddenSection: Bool, autoHide: Bool) {
        self.shortcut = shortcut
        self.alwaysHiddenSection = alwaysHiddenSection
        self.autoHide = autoHide
    }

    public static let `default` = MenuBarSettings(
        shortcut: KeyCombo(keyCode: KeyCode.b, modifiers: [.control, .option, .command]),
        alwaysHiddenSection: false,
        autoHide: true
    )

    enum CodingKeys: String, CodingKey { case shortcut, alwaysHiddenSection, autoHide }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        shortcut = c.contains(.shortcut) ? c.value(.shortcut, or: nil) : d.shortcut
        alwaysHiddenSection = c.value(.alwaysHiddenSection, or: d.alwaysHiddenSection)
        autoHide = c.value(.autoHide, or: d.autoHide)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shortcut, forKey: .shortcut)
        try c.encode(alwaysHiddenSection, forKey: .alwaysHiddenSection)
        try c.encode(autoHide, forKey: .autoHide)
    }
}

/// What is visible in the menu bar. Hiding works by giving a separator item a
/// huge length so it pushes the icons on its left off the screen (as Ice does).
public enum MenuBarState: Equatable, Sendable {
    case collapsed
    case expanded
    /// Expanded including the "always hidden" section (⌥-click).
    case all

    public static let hiddenLength: Double = 10_000
    public static let separatorLength: Double = 12

    /// Lengths for the main separator and the always-hidden separator.
    public func lengths(alwaysHiddenSection: Bool) -> (separator: Double, alwaysHidden: Double?) {
        let main = self == .collapsed ? Self.hiddenLength : Self.separatorLength
        guard alwaysHiddenSection else { return (main, nil) }
        return (main, self == .all ? Self.separatorLength : Self.hiddenLength)
    }

    /// Click on the toggle: collapsed ↔ expanded; ⌥-click shows everything.
    public func toggled(option: Bool) -> MenuBarState {
        if option { return self == .all ? .collapsed : .all }
        return self == .collapsed ? .expanded : .collapsed
    }
}
