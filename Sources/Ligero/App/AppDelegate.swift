import AppKit
import LigeroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var registry: ModuleRegistry?
    private var permissions: PermissionCenter?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore()
        let permissions = PermissionCenter()
        let actions = AppActions()
        let context = AppContext(settings: store, hotKeys: HotKeyCenter.shared, permissions: permissions, actions: actions)
        let registry = ModuleRegistry(descriptors: ModuleCatalog.all, context: context, permissions: permissions)
        permissions.onChange = { [weak registry] in registry?.apply() }

        let settingsWindow = SettingsWindowController(registry: registry, permissions: permissions, store: store)
        statusItem = StatusItemController(
            registry: registry,
            permissions: permissions,
            openSettings: { [weak settingsWindow] in settingsWindow?.show() }
        )
        actions.openSettings = { [weak settingsWindow] tab in settingsWindow?.show(tab: tab) }

        self.registry = registry
        self.permissions = permissions
        self.settingsWindow = settingsWindow

        registry.apply(explainMissing: true)
        Log.app.info("Ligero started with \(registry.runningCount) module(s) running")
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry?.stopAll()
    }

    /// Opening the app again from Finder or Spotlight shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return false
    }
}
