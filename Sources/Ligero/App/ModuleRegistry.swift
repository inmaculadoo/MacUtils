import LigeroCore

/// Contract of every module (SPEC §2.2).
@MainActor
protocol LigeroModule: AnyObject {
    static var id: String { get }
    static var requiredPermissions: Set<Permission> { get }
    /// Registers observers, hotkeys and taps.
    func start()
    /// Removes ALL of them; nothing may stay alive after stop().
    func stop()
}

/// Shared services handed to modules when they are created.
@MainActor
struct AppContext {
    let settings: SettingsStore
    let hotKeys: HotKeyCenter
}

/// Static description of a module. Holding one costs nothing: the module
/// itself is only created by `make` when it is enabled and allowed to run.
struct ModuleDescriptor: Identifiable {
    let id: String
    let titleKey: String
    let summaryKey: String
    let requiredPermissions: Set<Permission>
    let make: @MainActor (AppContext) -> any LigeroModule

    @MainActor
    init<M: LigeroModule>(
        _ type: M.Type,
        titleKey: String,
        summaryKey: String,
        make: @escaping @MainActor (AppContext) -> M
    ) {
        self.id = M.id
        self.titleKey = titleKey
        self.summaryKey = summaryKey
        self.requiredPermissions = M.requiredPermissions
        self.make = { make($0) }
    }
}

enum ModuleState: Equatable {
    case off
    case waitingForPermission([Permission])
    case running
}

/// Creates, starts and stops modules. A disabled module is never
/// instantiated (SPEC §2.2); a module that lacks a permission is not created
/// either, and starts on its own once the permission arrives.
@MainActor
final class ModuleRegistry {
    let descriptors: [ModuleDescriptor]
    let context: AppContext
    private let permissions: PermissionCenter
    private var running: [String: any LigeroModule] = [:]

    init(descriptors: [ModuleDescriptor], context: AppContext, permissions: PermissionCenter) {
        self.descriptors = descriptors
        self.context = context
        self.permissions = permissions
    }

    var runningCount: Int { running.count }

    func isEnabled(_ id: String) -> Bool {
        context.settings.app.enabledModules.contains(id)
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        var app = context.settings.app
        if enabled {
            app.enabledModules.insert(id)
        } else {
            app.enabledModules.remove(id)
        }
        context.settings.app = app
        apply(explainMissing: enabled)
    }

    func state(of descriptor: ModuleDescriptor) -> ModuleState {
        if running[descriptor.id] != nil { return .running }
        guard isEnabled(descriptor.id) else { return .off }
        let missing = permissions.missing(descriptor.requiredPermissions)
        return missing.isEmpty ? .off : .waitingForPermission(missing)
    }

    /// Brings every module in line with its setting and its permissions.
    func apply(explainMissing: Bool = false) {
        var blocked: [Permission: [String]] = [:]
        for d in descriptors {
            let wanted = isEnabled(d.id)
            let missing = permissions.missing(d.requiredPermissions)
            if wanted && missing.isEmpty {
                if running[d.id] == nil {
                    let module = d.make(context)
                    running[d.id] = module
                    module.start()
                    Log.modules.info("Started \(d.id, privacy: .public)")
                }
            } else {
                stopModule(d.id)
                if wanted {
                    for p in missing { blocked[p, default: []].append(L(d.titleKey)) }
                }
            }
        }
        guard explainMissing, !blocked.isEmpty else { return }
        // Explain after the current event so launch is not blocked by a modal.
        let pending = blocked
        Task { @MainActor [permissions] in
            for p in Permission.allCases {
                if let modules = pending[p] { permissions.explain(p, neededBy: modules) }
            }
        }
    }

    /// Stops and recreates a module so it picks up new settings.
    func restart(_ id: String) {
        stopModule(id)
        apply()
    }

    func stopAll() {
        for id in Array(running.keys) { stopModule(id) }
    }

    private func stopModule(_ id: String) {
        guard let module = running.removeValue(forKey: id) else { return }
        module.stop()
        Log.modules.info("Stopped \(id, privacy: .public)")
    }
}
