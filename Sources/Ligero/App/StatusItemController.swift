import AppKit
import LigeroCore

/// The menu bar icon and its NSMenu (SPEC §2.4: an NSMenu is cheaper than a
/// SwiftUI popover). The menu is rebuilt only when it is about to open.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let registry: ModuleRegistry
    private let permissions: PermissionCenter
    private let openSettings: @MainActor () -> Void

    init(registry: ModuleRegistry, permissions: PermissionCenter, openSettings: @escaping @MainActor () -> Void) {
        self.registry = registry
        self.permissions = permissions
        self.openSettings = openSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = item.button {
            let image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: L("app.name"))
            image?.isTemplate = true
            button.image = image
            button.toolTip = L("app.name")
        }
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Opening the menu is a natural moment to notice a permission granted
        // in System Settings (Screen Recording has no notification).
        permissions.refresh()
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        menu.addItem(NSMenuItem.sectionHeader(title: L("menu.modules")))
        if registry.descriptors.isEmpty {
            let none = NSMenuItem(title: L("menu.modules.none"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for d in registry.descriptors {
            let title: String
            switch registry.state(of: d) {
            case .waitingForPermission:
                title = L("menu.module.needsPermission", L(d.titleKey))
            case .off, .running:
                title = d.experimental ? L("menu.module.experimental", L(d.titleKey)) : L(d.titleKey)
            }
            let entry = NSMenuItem(title: title, action: #selector(toggleModule(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = d.id
            entry.state = registry.isEnabled(d.id) ? .on : .off
            entry.toolTip = L(d.summaryKey)
            menu.addItem(entry)
        }

        // Entries of running modules (Downloads undo, Capture, Monitor…).
        for module in registry.runningModules {
            guard let contributor = module as? MenuContributing else { continue }
            let items = contributor.menuItems()
            guard !items.isEmpty else { continue }
            menu.addItem(.separator())
            for item in items { menu.addItem(item) }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: L("menu.permissions")))
        for p in Permission.allCases {
            let granted = permissions.isGranted(p)
            let status = granted ? L("permission.status.granted") : L("permission.status.missing")
            let entry = NSMenuItem(
                title: L("menu.permission.row", L(p.titleKey), status),
                action: granted ? nil : #selector(requestPermission(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = p.rawValue
            entry.isEnabled = !granted
            entry.state = granted ? .on : .off
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: L("menu.launchAtLogin"), action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let settings = NSMenuItem(title: L("menu.settings"), action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        registry.setEnabled(id, !registry.isEnabled(id))
    }

    @objc private func requestPermission(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let p = Permission(rawValue: raw) else { return }
        permissions.request(p)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        if LoginItem.requiresApproval { LoginItem.openSystemSettings() }
    }

    @objc private func showSettings(_ sender: NSMenuItem) {
        openSettings()
    }
}
