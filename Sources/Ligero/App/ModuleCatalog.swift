import SwiftUI

/// Every module the app knows about, in menu order.
enum ModuleCatalog {
    @MainActor static var all: [ModuleDescriptor] {
        [
            SnapModule.descriptor,
            ScrollModule.descriptor,
            DownloadsModule.descriptor,
            ShelfModule.descriptor,
            UninstallModule.descriptor,
            CaptureModule.descriptor,
            MonitorModule.descriptor,
        ]
    }
}

/// Settings tabs contributed by modules, after "General".
@MainActor
enum SettingsPanes {
    static func all(model: SettingsModel) -> [SettingsPane] {
        [
            SettingsPane(id: SnapModule.id, titleKey: "settings.tab.snap", symbol: "rectangle.split.2x1",
                         view: AnyView(SnapSettingsView(model: model))),
            SettingsPane(id: ScrollModule.id, titleKey: "settings.tab.scroll", symbol: "computermouse",
                         view: AnyView(ScrollSettingsView(model: model))),
            SettingsPane(id: DownloadsModule.id, titleKey: "settings.tab.downloads", symbol: "arrow.down.circle",
                         view: AnyView(DownloadsSettingsView(model: model))),
            SettingsPane(id: ShelfModule.id, titleKey: "settings.tab.shelf", symbol: "tray",
                         view: AnyView(ShelfSettingsView(model: model))),
            SettingsPane(id: CaptureModule.id, titleKey: "settings.tab.capture", symbol: "camera.viewfinder",
                         view: AnyView(CaptureSettingsView(model: model))),
            SettingsPane(id: MonitorModule.id, titleKey: "settings.tab.monitor", symbol: "gauge.with.dots.needle.33percent",
                         view: AnyView(MonitorSettingsView(model: model))),
        ]
    }
}
