import Foundation

/// Every module stores one Codable value in UserDefaults (SPEC §3). Decoding
/// must never fail because of a field added or removed in a later version, so
/// each settings type decodes field by field and falls back to its default.
public protocol ModuleSettings: Codable, Equatable, Sendable {
    static var `default`: Self { get }
}

public enum SettingsCoding {
    public static func encode<T: ModuleSettings>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    /// Never throws: corrupt or missing data gives the default value.
    public static func decode<T: ModuleSettings>(_ type: T.Type, from data: Data?) -> T {
        guard let data, let value = try? JSONDecoder().decode(T.self, from: data) else {
            return T.default
        }
        return value
    }

    /// UserDefaults key for a module's settings blob.
    public static func key(forModule id: String) -> String { "module.\(id).settings" }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent` that also swallows type mismatches.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

/// App-wide settings that do not belong to a module.
public struct AppSettings: ModuleSettings {
    /// Ids of the modules the user turned on.
    public var enabledModules: Set<String>

    public init(enabledModules: Set<String>) {
        self.enabledModules = enabledModules
    }

    public static let `default` = AppSettings(enabledModules: ["snap", "scroll"])

    enum CodingKeys: String, CodingKey { case enabledModules }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabledModules = c.value(.enabledModules, or: Self.default.enabledModules)
    }
}

/// The language selector in Settings (SPEC §2.7). It writes `AppleLanguages`
/// in the app's own defaults domain, which macOS reads at launch.
public enum LanguageChoice: String, CaseIterable, Codable, Sendable {
    case system, es, en

    public var titleKey: String { "settings.language.\(rawValue)" }

    /// Value for the `AppleLanguages` default; nil means "remove the key and
    /// follow the system".
    public var appleLanguages: [String]? {
        switch self {
        case .system: return nil
        case .es: return ["es"]
        case .en: return ["en"]
        }
    }

    public init(appleLanguages: [String]?) {
        switch appleLanguages?.first?.prefix(2) {
        case "es": self = .es
        case "en": self = .en
        default: self = .system
        }
    }
}
