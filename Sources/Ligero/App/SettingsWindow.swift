import AppKit
import LigeroCore
import SwiftUI

/// Owns the Settings window. The window and its SwiftUI tree are created when
/// it opens and released when it closes (SPEC §2.4).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let registry: ModuleRegistry
    private let permissions: PermissionCenter
    private let store: SettingsStore
    private var window: NSWindow?
    private var model: SettingsModel?

    init(registry: ModuleRegistry, permissions: PermissionCenter, store: SettingsStore) {
        self.registry = registry
        self.permissions = permissions
        self.store = store
    }

    func show() {
        if window == nil {
            let model = SettingsModel(registry: registry, permissions: permissions, store: store)
            let host = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = L("settings.window.title")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
            self.model = model
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        permissions.refresh()
        model?.reload()
    }

    func windowWillClose(_ notification: Notification) {
        model?.windowWillClose()
        window?.contentViewController = nil
        window = nil
        model = nil
    }
}

/// State behind the Settings window. Lives only while the window is open.
@MainActor
final class SettingsModel: ObservableObject {
    let registry: ModuleRegistry
    let permissions: PermissionCenter
    let store: SettingsStore

    @Published private(set) var language: LanguageChoice
    @Published private(set) var languageAtOpen: LanguageChoice
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var granted: [Permission: Bool] = [:]
    @Published private(set) var enabled: Set<String> = []
    /// Bumped when module settings change so that panes re-read them.
    @Published private(set) var revision = 0

    /// Pane-specific cleanup (for example, a shortcut recorder) registered
    /// by the views.
    var onClose: [@MainActor () -> Void] = []

    init(registry: ModuleRegistry, permissions: PermissionCenter, store: SettingsStore) {
        self.registry = registry
        self.permissions = permissions
        self.store = store
        language = store.language
        languageAtOpen = store.language
        reload()
    }

    func reload() {
        launchAtLogin = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.requiresApproval
        var g: [Permission: Bool] = [:]
        for p in Permission.allCases { g[p] = permissions.isGranted(p) }
        granted = g
        enabled = store.app.enabledModules
    }

    func windowWillClose() {
        for f in onClose { f() }
        onClose.removeAll()
    }

    // MARK: General

    func setLanguage(_ choice: LanguageChoice) {
        store.language = choice
        language = choice
    }

    var needsRestartForLanguage: Bool { language != languageAtOpen }

    /// Launches a fresh copy of the app and quits this one, so the new
    /// AppleLanguages value takes effect.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        LoginItem.setEnabled(on)
        reload()
    }

    func openLoginItemsSettings() {
        LoginItem.openSystemSettings()
    }

    // MARK: Modules

    func isEnabled(_ id: String) -> Bool { enabled.contains(id) }

    func setModule(_ id: String, enabled on: Bool) {
        registry.setEnabled(id, on)
        reload()
    }

    func request(_ permission: Permission) {
        permissions.request(permission)
    }

    /// Loads, edits and saves a module's settings, then restarts the module
    /// if it is running so it picks them up.
    func update<T: ModuleSettings>(_ type: T.Type, module id: String, _ change: (inout T) -> Void) {
        var value = store.load(T.self, module: id)
        change(&value)
        store.save(value, module: id)
        registry.restart(id)
        revision += 1
    }

    func settings<T: ModuleSettings>(_ type: T.Type, module id: String) -> T {
        _ = revision
        return store.load(T.self, module: id)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label(L("settings.tab.general"), systemImage: "gearshape") }
            ForEach(SettingsPanes.all(model: model)) { pane in
                pane.view
                    .tabItem { Label(L(pane.titleKey), systemImage: pane.symbol) }
            }
        }
        .frame(width: 560)
        .frame(minHeight: 460)
    }
}

/// A module's tab in Settings.
struct SettingsPane: Identifiable {
    let id: String
    let titleKey: String
    let symbol: String
    let view: AnyView
}

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section(L("settings.language")) {
                Picker(L("settings.language"), selection: Binding(
                    get: { model.language },
                    set: { model.setLanguage($0) }
                )) {
                    ForEach(LanguageChoice.allCases, id: \.self) { choice in
                        Text(L(choice.titleKey)).tag(choice)
                    }
                }
                if model.needsRestartForLanguage {
                    HStack {
                        Text(L("settings.language.restartHint"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("settings.language.restartNow")) { model.relaunch() }
                    }
                }
            }

            Section(L("settings.startup")) {
                Toggle(L("settings.launchAtLogin"), isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.loginNeedsApproval {
                    HStack {
                        Text(L("settings.launchAtLogin.needsApproval"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("settings.openSystemSettings")) { model.openLoginItemsSettings() }
                    }
                }
            }

            Section(L("settings.modules")) {
                if model.registry.descriptors.isEmpty {
                    Text(L("menu.modules.none")).foregroundStyle(.secondary)
                }
                ForEach(model.registry.descriptors) { d in
                    Toggle(isOn: Binding(
                        get: { model.isEnabled(d.id) },
                        set: { model.setModule(d.id, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L(d.titleKey))
                            Text(L(d.summaryKey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(L("settings.permissions")) {
                ForEach(Permission.allCases, id: \.self) { p in
                    PermissionRow(permission: p, granted: model.granted[p] ?? false) {
                        model.request(p)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PermissionRow: View {
    let permission: Permission
    let granted: Bool
    let request: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(permission.titleKey))
                Text(L(permission.explanationKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Text(L("permission.status.granted")).foregroundStyle(.secondary)
            } else {
                Button(L("settings.openSystemSettings"), action: request)
            }
        }
    }
}
