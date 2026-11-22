/// System permissions (TCC) that a module may need. See SPEC §6.
public enum Permission: String, CaseIterable, Codable, Hashable, Sendable {
    case accessibility
    case screenRecording

    /// Key of the human-readable name in Localizable.strings.
    public var titleKey: String { "permission.\(rawValue).title" }
    /// Key of the explanation shown before sending the user to System Settings.
    public var explanationKey: String { "permission.\(rawValue).explanation" }
}
