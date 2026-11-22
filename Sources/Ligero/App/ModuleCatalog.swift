/// Every module the app knows about, in menu order.
enum ModuleCatalog {
    @MainActor static var all: [ModuleDescriptor] { [] }
}

/// Settings tabs contributed by modules, after "General".
@MainActor
enum SettingsPanes {
    static func all(model: SettingsModel) -> [SettingsPane] { [] }
}
