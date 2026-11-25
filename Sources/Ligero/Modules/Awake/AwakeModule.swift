import AppKit
import IOKit.pwr_mgt
import LigeroCore

/// Keep the Mac awake for a while, until turned off, or while some apps are
/// open (SPEC §4.13, like Amphetamine).
///
/// Idle cost: zero. Uses IOPM assertions. A timed session hands its timeout
/// to the system (kIOPMAssertionTimeoutKey), which releases the assertion on
/// its own, so there is no timer here. Trigger apps are followed with the
/// NSWorkspace launch/terminate notifications, only while at least one
/// trigger app is set.
@MainActor
final class AwakeModule: LigeroModule, MenuContributing {
    static let id = "awake"
    static let requiredPermissions: Set<Permission> = []

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(AwakeModule.self, titleKey: "module.awake.title", summaryKey: "module.awake.summary") {
            AwakeModule(context: $0)
        }
    }

    private let context: AppContext
    private var settings: AwakeSettings
    private var hotKey: HotKeyToken?
    private var session: AwakeSession?
    private var sessionAssertion: IOPMAssertionID?
    private var appsAssertion: IOPMAssertionID?
    private var workspaceTokens: [NSObjectProtocol] = []

    init(context: AppContext) {
        self.context = context
        settings = context.settings.load(AwakeSettings.self, module: Self.id)
    }

    func start() {
        if let combo = settings.shortcut {
            hotKey = context.hotKeys.register(combo) { [weak self] in self?.toggleIndefinitely() }
        }
        updateAppWatch()
    }

    func stop() {
        if let hotKey { context.hotKeys.unregister(hotKey) }
        hotKey = nil
        endSession()
        stopAppWatch()
    }

    // MARK: Manual sessions

    private func toggleIndefinitely() {
        if currentSession != nil { endSession() } else { begin(.indefinitely) }
    }

    /// The session, if the system has not released it yet.
    private var currentSession: AwakeSession? {
        guard let session, session.isActive(at: Date()) else { return nil }
        return session
    }

    private func begin(_ duration: AwakeDuration) {
        endSession()
        session = AwakeSession(duration: duration, now: Date())
        sessionAssertion = Self.assert(name: "All In One: keep awake", display: settings.keepDisplayOn,
                                       timeout: duration.seconds)
        Log.modules.info("Awake: session \(duration.rawValue, privacy: .public)")
    }

    private func endSession() {
        if let id = sessionAssertion { IOPMAssertionRelease(id) }
        sessionAssertion = nil
        session = nil
    }

    // MARK: Trigger apps

    private func updateAppWatch() {
        if settings.triggerApps.isEmpty {
            stopAppWatch()
            return
        }
        if workspaceTokens.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.evaluateApps() }
                })
            }
        }
        evaluateApps()
    }

    private func stopAppWatch() {
        let center = NSWorkspace.shared.notificationCenter
        for t in workspaceTokens { center.removeObserver(t) }
        workspaceTokens.removeAll()
        if let id = appsAssertion { IOPMAssertionRelease(id) }
        appsAssertion = nil
    }

    private var runningBundles: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private func evaluateApps() {
        let open = AwakePlanner.openTriggers(settings.triggerApps, running: runningBundles)
        if open.isEmpty {
            if let id = appsAssertion { IOPMAssertionRelease(id) }
            appsAssertion = nil
        } else if appsAssertion == nil {
            appsAssertion = Self.assert(name: "All In One: trigger app open", display: settings.keepDisplayOn, timeout: nil)
        }
    }

    // MARK: Settings changed from the menu

    private func change(_ edit: (inout AwakeSettings) -> Void) {
        edit(&settings)
        context.settings.save(settings, module: Self.id)
    }

    private func setKeepDisplayOn(_ on: Bool) {
        change { $0.keepDisplayOn = on }
        // Re-create the assertions with the new type; a timed session keeps
        // its end time.
        if let s = currentSession, let id = sessionAssertion {
            IOPMAssertionRelease(id)
            sessionAssertion = Self.assert(name: "All In One: keep awake", display: on,
                                           timeout: s.until.map { max(1, $0.timeIntervalSinceNow) })
        }
        if let id = appsAssertion {
            IOPMAssertionRelease(id)
            appsAssertion = nil
            evaluateApps()
        }
    }

    private func toggleTrigger(_ bundleID: String) {
        change { $0.toggleTrigger(bundleID) }
        if let id = appsAssertion { IOPMAssertionRelease(id) }
        appsAssertion = nil
        updateAppWatch()
    }

    // MARK: IOKit

    private static func assert(name: String, display: Bool, timeout: Double?) -> IOPMAssertionID? {
        var props: [String: Any] = [
            kIOPMAssertionTypeKey: display ? kIOPMAssertionTypePreventUserIdleDisplaySleep
                                           : kIOPMAssertionTypePreventUserIdleSystemSleep,
            kIOPMAssertionNameKey: name,
        ]
        if let timeout {
            props[kIOPMAssertionTimeoutKey] = timeout
            props[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
        }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithProperties(props as CFDictionary, &id)
        guard result == kIOReturnSuccess else {
            Log.modules.error("Awake: assertion failed (\(result))")
            return nil
        }
        return id
    }

    // MARK: Menu

    func menuItems() -> [NSMenuItem] {
        let now = Date()
        let reason = AwakePlanner.reason(session: currentSession, triggers: settings.triggerApps,
                                         running: runningBundles, now: now)
        if session != nil, currentSession == nil {
            // The system already released the timed assertion.
            endSession()
        }
        let title: String
        switch reason {
        case .off:
            title = L("awake.menu.off")
        case .session(let s):
            if let until = s.until {
                title = L("awake.menu.until", DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short))
            } else {
                title = L("awake.menu.indefinitely")
            }
        case .apps(let ids):
            title = L("awake.menu.whileApps", ids.map(Self.appName).joined(separator: ", "))
        }
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false

        let off = ClosureMenuItem(title: L("awake.menu.turnOff")) { [weak self] in self?.endSession() }
        off.isEnabled = currentSession != nil
        sub.addItem(off)
        for d in AwakeDuration.allCases {
            let item = ClosureMenuItem(title: L(d.titleKey)) { [weak self] in self?.begin(d) }
            if d == .indefinitely { item.showShortcut(settings.shortcut) }
            sub.addItem(item)
        }

        sub.addItem(.separator())
        let display = ClosureMenuItem(title: L("awake.menu.keepDisplayOn")) { [weak self] in
            guard let self else { return }
            self.setKeepDisplayOn(!self.settings.keepDisplayOn)
        }
        display.state = settings.keepDisplayOn ? .on : .off
        sub.addItem(display)

        let apps = NSMenuItem(title: L("awake.menu.whileOpen"), action: nil, keyEquivalent: "")
        let appsMenu = NSMenu()
        // Chosen apps first (even if closed), then the other open apps.
        var ids = settings.triggerApps
        let open = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap(\.bundleIdentifier)
            .filter { !ids.contains($0) }
            .sorted { Self.appName($0).localizedCaseInsensitiveCompare(Self.appName($1)) == .orderedAscending }
        ids += open
        for id in ids {
            let item = ClosureMenuItem(title: Self.appName(id)) { [weak self] in self?.toggleTrigger(id) }
            item.state = settings.triggerApps.contains(id) ? .on : .off
            appsMenu.addItem(item)
        }
        apps.submenu = appsMenu
        sub.addItem(apps)
        root.submenu = sub
        return [root]
    }

    private static func appName(_ bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}
