import AppKit
import ApplicationServices
import LigeroCore
@preconcurrency import ScreenCaptureKit

/// Private but long-standing AX call that maps an AX window to its
/// CGWindowID (used by AltTab, Rectangle, yabai…). Needed to match AX windows
/// with ScreenCaptureKit windows and the on-screen window list.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// A window as the Switcher, Dock Previews and Ribbon see it.
@MainActor
struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let element: AXUIElement
    let title: String
    let appName: String
    let isMinimized: Bool
    let frame: LRect?

    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }
}

/// Window events the clients care about.
enum WindowEvent {
    case created(pid_t, AXUIElement)
    case destroyed(pid_t, CGWindowID?)
    case focused(pid_t)
    case changed(pid_t, CGWindowID?) // moved, resized, renamed, (un)minimised
    case appTerminated(pid_t)
}

/// Shared, reference-counted window tracker (SPEC §4.5, §4.6, §4.12).
///
/// Nothing runs until a module calls `acquire`. Then there is one AXObserver
/// per regular app, notified by the apps themselves (no polling), and two
/// NSWorkspace observers for launches and quits. `release` by the last client
/// removes every observer. The window list is cached per app and rebuilt only
/// for apps whose cache an event invalidated.
@MainActor
final class WindowService {
    static let shared = WindowService()

    private var clients: [ObjectIdentifier: @MainActor (WindowEvent) -> Void] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var cache: [pid_t: [WindowInfo]] = [:]
    private var mru = MRUList<CGWindowID>()
    private(set) var thumbnails = LRUCache<CGWindowID, CGImage>(capacity: 40)

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXMovedNotification, kAXResizedNotification,
        kAXTitleChangedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]

    private init() {}

    var isActive: Bool { !clients.isEmpty }

    // MARK: Clients

    func acquire(_ client: AnyObject, onEvent: @escaping @MainActor (WindowEvent) -> Void) {
        let wasActive = isActive
        clients[ObjectIdentifier(client)] = onEvent
        if !wasActive { activate() }
    }

    func release(_ client: AnyObject) {
        clients.removeValue(forKey: ObjectIdentifier(client))
        if clients.isEmpty { deactivate() }
    }

    private func activate() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.observe(pid) } }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.appTerminated(pid) } }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.focusChanged(pid) } }
        })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app.processIdentifier)
        }
        if let front = NSWorkspace.shared.frontmostApplication { focusChanged(front.processIdentifier) }
        Log.modules.info("WindowService active: \(self.observers.count) apps observed")
    }

    private func deactivate() {
        let center = NSWorkspace.shared.notificationCenter
        for t in workspaceTokens { center.removeObserver(t) }
        workspaceTokens.removeAll()
        for (_, observer) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        cache.removeAll()
        mru = MRUList()
        thumbnails.removeAll()
        Log.modules.info("WindowService stopped")
    }

    // MARK: Observing apps

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, windowServiceCallback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.appNotifications {
            AXObserverAddNotification(observer, app, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        for w in axWindows(of: app) { watchWindow(w, observer: observer) }
    }

    private func watchWindow(_ window: AXUIElement, observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.windowNotifications {
            AXObserverAddNotification(observer, window, n as CFString, refcon)
        }
    }

    private func appTerminated(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        for w in cache[pid] ?? [] {
            mru.remove(w.id)
            thumbnails.remove(w.id)
        }
        cache.removeValue(forKey: pid)
        broadcast(.appTerminated(pid))
    }

    private func focusChanged(_ pid: pid_t) {
        if let id = focusedWindowID(pid) { mru.touch(id) }
        broadcast(.focused(pid))
    }

    fileprivate func axEvent(_ element: AXUIElement, _ notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let id = Self.windowID(element)
        switch notification {
        case kAXWindowCreatedNotification:
            cache.removeValue(forKey: pid)
            if let observer = observers[pid] { watchWindow(element, observer: observer) }
            broadcast(.created(pid, element))
        case kAXUIElementDestroyedNotification:
            cache.removeValue(forKey: pid)
            if let id {
                mru.remove(id)
                thumbnails.remove(id)
            }
            broadcast(.destroyed(pid, id))
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            focusChanged(pid)
        default:
            cache.removeValue(forKey: pid)
            if let id { thumbnails.remove(id) }
            broadcast(.changed(pid, id))
        }
    }

    private func broadcast(_ event: WindowEvent) {
        for handler in clients.values { handler(event) }
    }

    // MARK: Queries

    /// Standard windows on the current Space (plus minimised ones), most
    /// recently used first. Apps whose cache is still valid are not queried.
    func windows(includeMinimized: Bool = true) -> [WindowInfo] {
        let onScreen = Self.onScreenWindowIDs()
        var all: [WindowInfo] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            if pid == ProcessInfo.processInfo.processIdentifier { continue }
            let list = cache[pid] ?? loadWindows(app)
            cache[pid] = list
            all += list.filter { onScreen.contains($0.id) || (includeMinimized && $0.isMinimized) }
        }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return mru.sorted(all.map(\.id)).compactMap { byID[$0] }
    }

    func windows(ofApp pid: pid_t) -> [WindowInfo] {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return [] }
        let list = cache[pid] ?? loadWindows(app)
        cache[pid] = list
        return list
    }

    private func loadWindows(_ app: NSRunningApplication) -> [WindowInfo] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let name = app.localizedName ?? ""
        return axWindows(of: element).compactMap { w in
            guard Self.isStandardWindow(w), let id = Self.windowID(w) else { return nil }
            return WindowInfo(
                id: id, pid: app.processIdentifier, element: w,
                title: Self.string(w, kAXTitleAttribute) ?? "",
                appName: name,
                isMinimized: Self.bool(w, kAXMinimizedAttribute) ?? false,
                frame: Self.frame(w)
            )
        }
    }

    private func axWindows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private func focusedWindowID(_ pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return Self.windowID(value as! AXUIElement)
    }

    static func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids = Set<CGWindowID>()
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let n = w[kCGWindowNumber as String] as? CGWindowID { ids.insert(n) }
        }
        return ids
    }

    // MARK: AX helpers

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    static func isStandardWindow(_ w: AXUIElement) -> Bool {
        string(w, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String)
    }

    static func string(_ e: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func bool(_ e: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    static func frame(_ e: AXUIElement) -> LRect? {
        var p: CFTypeRef?
        var s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return LRect(x: point.x, y: point.y, width: size.width, height: size.height)
    }

    static func setFrame(_ e: AXUIElement, _ r: LRect) {
        var size = CGSize(width: r.width, height: r.height)
        var point = CGPoint(x: r.x, y: r.y)
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, v) }
        if let v = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v) }
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, v) }
    }

    // MARK: Actions

    func activate(_ w: WindowInfo) {
        if w.isMinimized {
            AXUIElementSetAttributeValue(w.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(w.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(w.element, kAXRaiseAction as CFString)
        w.app?.activate()
        mru.touch(w.id)
    }

    func close(_ w: WindowInfo) {
        var button: CFTypeRef?
        if AXUIElementCopyAttributeValue(w.element, kAXCloseButtonAttribute as CFString, &button) == .success,
           let button, CFGetTypeID(button) == AXUIElementGetTypeID() {
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
        cache.removeValue(forKey: w.pid)
    }

    func minimize(_ w: WindowInfo) {
        AXUIElementSetAttributeValue(w.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        cache.removeValue(forKey: w.pid)
    }

    func quit(_ w: WindowInfo) {
        w.app?.terminate()
    }

    // MARK: Thumbnails (Screen Recording permission)

    struct ThumbnailRequest: Sendable {
        let ids: [CGWindowID]
        let maxWidth: Int
    }

    struct Thumbnail: @unchecked Sendable {
        let id: CGWindowID
        let image: CGImage
    }

    /// Captures thumbnails for windows that are not cached yet, one-shot with
    /// SCScreenshotManager (never an SCStream). Called only when a switcher
    /// or dock preview opens.
    func loadThumbnails(for ids: [CGWindowID], maxWidth: Int = 320) async {
        let missing = ids.filter { thumbnails.peek($0) == nil }
        guard !missing.isEmpty, CGPreflightScreenCaptureAccess() else { return }
        let results = await Self.capture(ThumbnailRequest(ids: missing, maxWidth: maxWidth))
        for t in results { thumbnails.set(t.id, t.image) }
    }

    func thumbnail(_ id: CGWindowID) -> CGImage? {
        thumbnails.get(id)
    }

    nonisolated static func capture(_ request: ThumbnailRequest) async -> [Thumbnail] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return []
        }
        let wanted = Set(request.ids)
        let windows = content.windows.filter { wanted.contains($0.windowID) }
        return await withTaskGroup(of: Thumbnail?.self) { group in
            for window in windows {
                group.addTask {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    let w = max(1.0, Double(window.frame.width))
                    let h = max(1.0, Double(window.frame.height))
                    let scale = min(1.0, Double(request.maxWidth) * 2 / w)
                    config.width = max(1, Int(w * scale))
                    config.height = max(1, Int(h * scale))
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                        return nil
                    }
                    return Thumbnail(id: window.windowID, image: image)
                }
            }
            var out: [Thumbnail] = []
            for await t in group { if let t { out.append(t) } }
            return out
        }
    }
}

/// AX callbacks arrive on the main run loop.
private func windowServiceCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let service = Unmanaged<WindowService>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated { service.axEvent(element, name) }
}
