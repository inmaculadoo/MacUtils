import AppKit
import LigeroCore

/// Hide menu bar icons behind a separator (SPEC §4.7). EXPERIMENTAL.
///
/// Mechanism (as Ice): an NSStatusItem separator whose `length` grows to
/// 10 000 pt pushes every item on its left off the screen; shrinking it shows
/// them again. Items are arranged by ⌘-dragging; `autosaveName` keeps the
/// positions. Idle cost: zero (no timers; the optional re-hide on app switch
/// is an NSWorkspace notification).
///
/// RISK (macOS 26 Tahoe): Tahoe redesigned the menu bar and moved some status
/// items into Control Center. If the system caps the length of a status item,
/// or lays items out differently, the huge separator may stop pushing icons
/// away, or push Ligero's own icon too. Validate on the real Mac before
/// polishing (TESTING.md).
@MainActor
final class MenuBarModule: LigeroModule, MenuContributing {
    static let id = "menubar"
    static let requiredPermissions: Set<Permission> = []

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(MenuBarModule.self, titleKey: "module.menubar.title", summaryKey: "module.menubar.summary",
                         experimental: true) { MenuBarModule(context: $0) }
    }

    private let context: AppContext
    private let settings: MenuBarSettings
    private let clickTarget = MenuBarClickTarget()
    private var toggleItem: NSStatusItem?
    private var separator: NSStatusItem?
    private var alwaysHidden: NSStatusItem?
    private var state = MenuBarState.collapsed
    private var hotKey: HotKeyToken?
    private var activationToken: NSObjectProtocol?

    init(context: AppContext) {
        self.context = context
        settings = context.settings.load(MenuBarSettings.self, module: Self.id)
    }

    func start() {
        // New status items appear to the left of existing ones, so they are
        // created right to left: toggle, separator, always-hidden separator.
        let bar = NSStatusBar.system
        let toggle = bar.statusItem(withLength: NSStatusItem.squareLength)
        toggle.autosaveName = "ligero.menubar.toggle"
        clickTarget.module = self
        if let button = toggle.button {
            button.target = clickTarget
            button.action = #selector(MenuBarClickTarget.clicked(_:))
            button.toolTip = L("menubar.toggleHelp")
        }
        toggleItem = toggle

        let sep = bar.statusItem(withLength: MenuBarState.separatorLength)
        sep.autosaveName = "ligero.menubar.separator"
        sep.button?.image = Self.dividerImage()
        separator = sep

        if settings.alwaysHiddenSection {
            let hidden = bar.statusItem(withLength: MenuBarState.hiddenLength)
            hidden.autosaveName = "ligero.menubar.alwaysHidden"
            hidden.button?.image = Self.dividerImage()
            alwaysHidden = hidden
        }

        if let combo = settings.shortcut {
            hotKey = context.hotKeys.register(combo) { [weak self] in self?.toggle(option: false) }
        }
        if settings.autoHide {
            activationToken = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.collapseIfNeeded() }
            }
        }
        apply(.collapsed)
    }

    func stop() {
        if let hotKey { context.hotKeys.unregister(hotKey) }
        hotKey = nil
        if let activationToken { NSWorkspace.shared.notificationCenter.removeObserver(activationToken) }
        activationToken = nil
        for item in [toggleItem, separator, alwaysHidden].compactMap({ $0 }) {
            NSStatusBar.system.removeStatusItem(item)
        }
        toggleItem = nil
        separator = nil
        alwaysHidden = nil
        clickTarget.module = nil
    }

    fileprivate func toggle(option: Bool) {
        apply(state.toggled(option: option))
    }

    private func collapseIfNeeded() {
        if state != .collapsed { apply(.collapsed) }
    }

    private func apply(_ new: MenuBarState) {
        state = new
        let lengths = new.lengths(alwaysHiddenSection: settings.alwaysHiddenSection)
        separator?.length = lengths.separator
        if let l = lengths.alwaysHidden { alwaysHidden?.length = l }
        let symbol = new == .collapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: L("menubar.toggleHelp"))
        image?.isTemplate = true
        toggleItem?.button?.image = image
    }

    func menuItems() -> [NSMenuItem] {
        let title = state == .collapsed ? L("menubar.menu.show") : L("menubar.menu.hide")
        return [ClosureMenuItem(title: title) { [weak self] in self?.toggle(option: false) }]
    }

    /// A thin vertical line: the divider the user ⌘-drags icons around.
    static func dividerImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 6, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSRect(x: rect.midX - 0.5, y: 2, width: 1, height: rect.height - 4).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// NSObject target for the toggle button (modules are plain classes).
@MainActor
final class MenuBarClickTarget: NSObject {
    weak var module: MenuBarModule?

    @objc func clicked(_ sender: Any?) {
        module?.toggle(option: NSEvent.modifierFlags.contains(.option))
    }
}
