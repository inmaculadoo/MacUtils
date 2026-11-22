import AppKit
import LigeroCore

/// Window snapping with global shortcuts (SPEC §4.1).
/// Idle cost: zero. Only Carbon hotkeys are registered; AX is touched only
/// when a shortcut is pressed.
@MainActor
final class SnapModule: LigeroModule {
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
    }

    func stop() {
        for token in tokens { hotKeys.unregister(token) }
        tokens.removeAll()
        history.removeAll()
    }

    func perform(_ action: SnapAction) {
        guard let window = AXWindow.focused(), let current = window.frame else {
            NSSound.beep()
            return
        }
        let key = window.key
        if action == .restore {
            guard let original = history.takeOriginal(key) else { return }
            window.setFrame(original)
            return
        }
        let screens = ScreenGeometry.screens()
        guard let target = SnapEngine.target(for: action, window: current, screens: screens, options: settings.options) else {
            return
        }
        guard !target.isClose(to: current, tolerance: 0.5) else { return }
        history.record(key, current: current, applied: target)
        window.setFrame(target)
    }
}
