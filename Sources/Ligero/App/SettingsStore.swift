import Foundation
import LigeroCore

/// One Codable blob per module in UserDefaults (SPEC §3).
@MainActor
final class SettingsStore {
    private let defaults: UserDefaults
    private static let appKey = "app.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load<T: ModuleSettings>(_ type: T.Type, module id: String) -> T {
        SettingsCoding.decode(T.self, from: defaults.data(forKey: SettingsCoding.key(forModule: id)))
    }

    func save<T: ModuleSettings>(_ value: T, module id: String) {
        defaults.set(SettingsCoding.encode(value), forKey: SettingsCoding.key(forModule: id))
    }

    /// Non-settings data a module keeps between launches (e.g. undo history).
    func loadValue<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func saveValue<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    var app: AppSettings {
        get { SettingsCoding.decode(AppSettings.self, from: defaults.data(forKey: Self.appKey)) }
        set { defaults.set(SettingsCoding.encode(newValue), forKey: Self.appKey) }
    }

    // MARK: Language (SPEC §2.7)

    private static let languagesKey = "AppleLanguages"

    /// Only the app's own domain counts: NSGlobalDomain always has
    /// AppleLanguages, and that would hide the "System" choice.
    var language: LanguageChoice {
        get {
            guard let id = Bundle.main.bundleIdentifier,
                  let domain = defaults.persistentDomain(forName: id) else { return .system }
            return LanguageChoice(appleLanguages: domain[Self.languagesKey] as? [String])
        }
        set {
            if let value = newValue.appleLanguages {
                defaults.set(value, forKey: Self.languagesKey)
            } else {
                defaults.removeObject(forKey: Self.languagesKey)
            }
        }
    }
}
