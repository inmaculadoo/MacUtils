import AppKit
import LigeroCore

/// Window snapping with global shortcuts (SPEC §4.1).
/// Idle cost: zero. Only Carbon hotkeys are registered; AX is touched only
/// when a shortcut is pressed.
@MainActor
final class SnapModule: LigeroModule, MenuContributing {
    static let id = "snap"
    static let requiredPermissions: Set<Permission> = [.accessibility]

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(SnapModule.self, titleKey: "module.snap.title", summaryKey: "module.snap.summary") {
            SnapModule(context: $0)
        }
    }

    private let hotKeys: HotKeyCenter
    private let settings: SnapSettings
    private var tokens: [HotKeyToken] = []
    private var history = RestoreHistory<WindowKey>(capacity: 50)
    private let drag = SnapDrag()

    init(context: AppContext) {
        hotKeys = context.hotKeys
        settings = context.settings.load(SnapSettings.self, module: Self.id)
    }

    func start() {
        for action in SnapAction.allCases {
            guard let combo = settings.shortcuts[action] else { continue }
            let token = hotKeys.register(combo) { [weak self] in
                self?.perform(action)
            }
            if let token { tokens.append(token) }
        }
        Log.snap.info("Registered \(self.tokens.count) shortcut(s)")
        if settings.dragToEdges {
            drag.onDrop = { [weak self] window, before, zone in self?.dropped(window, before: before, zone: zone) }
            drag.start(options: settings.options)
        }
    }

    func stop() {
        drag.stop()
        drag.onDrop = nil
        for token in tokens { hotKeys.unregister(token) }
        tokens.removeAll()
        history.removeAll()
    }

    /// Groups of the "Place window" submenu, in menu order.
    private static let menuGroups: [[SnapAction]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds],
        [.maximize, .maximizeHeight, .center],
        [.nextDisplay, .previousDisplay],
        [.restore],
    ]

    /// A submenu with every placement, for the window that is focused when
    /// the menu opens (the menu doesn't take focus from it).
    func menuItems() -> [NSMenuItem] {
        let window = AXWindow.focused()
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let root = NSMenuItem(title: window == nil ? L("snap.menu.noWindow") : L("snap.menu.place", app),
                              action: nil, keyEquivalent: "")
        guard let window else {
            root.isEnabled = false
            return [root]
        }
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (i, group) in Self.menuGroups.enumerated() {
            if i > 0 { sub.addItem(.separator()) }
            for action in group {
                let item = ClosureMenuItem(title: L(action.localizationKey)) { [weak self] in
                    self?.perform(action, on: window)
                }
                item.showShortcut(settings.shortcuts[action])
                sub.addItem(item)
            }
        }
        root.submenu = sub
        return [root]
    }

    func perform(_ action: SnapAction, on chosen: AXWindow? = nil) {
        guard let window = chosen ?? AXWindow.focused(), let current = window.frame else {
            NSSound.beep()
            return
        }
        let key = window.key
        if action == .restore {
            guard let original = history.takeOriginal(key) else { return }
            if let id = WindowService.windowID(window.element) {
                NotificationCenter.default.post(name: .ligeroWindowPlaced, object: NSNumber(value: id))
            }
            window.setFrame(original)
            return
        }
        let screens = ScreenGeometry.screens()
        // Apps that round their size never sit exactly on a snap frame: use
        // the frame Ligero asked for while the window hasn't moved since.
        let layout = history.lastTarget(key, current: current) ?? current
        guard let target = SnapEngine.target(for: action, window: layout, screens: screens, options: settings.options) else {
            return
        }
        guard !target.isClose(to: layout, tolerance: 0.5) else { return }
        place(window, from: current, to: target, screens: screens)
    }

    /// A window was dragged and let go in an edge zone.
    private func dropped(_ window: AXWindow, before: LRect, zone: SnapZones.Zone) {
        let screens = ScreenGeometry.screens()
        guard let target = SnapZones.target(for: zone, screens: screens, options: settings.options) else { return }
        // Restore (⌃⌥⌫) goes back to the frame from before the drag, or from
        // before the first snap if the window was still snapped.
        let current = history.appliedBeforeDrag(window.key, dragged: before) ?? before
        place(window, from: current, to: target, screens: screens)
    }

    private func place(_ window: AXWindow, from current: LRect, to target: LRect, screens: [ScreenInfo]) {
        // Ribbon lets go of a window the user places on purpose.
        if let id = WindowService.windowID(window.element) {
            NotificationCenter.default.post(name: .ligeroWindowPlaced, object: NSNumber(value: id))
        }
        window.setFrame(target)
        // Apps with a minimum size may refuse the target: keep the window on
        // screen and remember where it really ended up, so restore still works.
        var applied = window.frame ?? target
        if let settled = SnapEngine.settle(actual: applied, target: target, screens: screens, gap: settings.options.gap) {
            window.setPosition(CGPoint(x: settled.x, y: settled.y))
            applied = window.frame ?? settled
        }
        history.record(window.key, current: current, applied: applied, target: target)
    }
}
