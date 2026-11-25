import AppKit
import ApplicationServices
import LigeroCore
import SwiftUI

/// Window previews when hovering Dock icons (SPEC §4.6). EXPERIMENTAL.
///
/// Mechanism (as DockDoor): an AXObserver on the Dock process for
/// `kAXSelectedChildrenChangedNotification` on its icon list, which the Dock
/// posts when the hovered icon changes. No mouse polling. Thumbnails come
/// from the WindowService cache shared with the Switcher.
///
/// Optional "click the icon of the active app to minimise/hide it" needs an
/// event tap on mouse clicks, so it is off by default and the tap only exists
/// while that option is on.
@MainActor
final class DockModule: LigeroModule {
    static let id = "dock"
    static let requiredPermissions: Set<Permission> = [.accessibility]
    static let dockBundleID = "com.apple.dock"

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(DockModule.self, titleKey: "module.dock.title", summaryKey: "module.dock.summary",
                         experimental: true) { DockModule(context: $0) }
    }

    private let settings: DockSettings
    private let service = WindowService.shared
    private var observer: AXObserver?
    private var list: AXUIElement?
    private var launchToken: NSObjectProtocol?
    private var panel: DockPreviewPanel?
    private let viewModel = DockPreviewModel()
    private var hoveredPID: pid_t?
    private var clickTap: ClickTap?
    private var thumbnailTask: Task<Void, Never>?
    /// Mouse monitors that exist only while the preview is visible.
    private var moveMonitors: [Any] = []
    /// The Dock's icon list frame (top-left), read once when the panel shows.
    private var dockFrame: LRect?

    init(context: AppContext) {
        settings = context.settings.load(DockSettings.self, module: Self.id)
    }

    func start() {
        service.acquire(self) { [weak self] event in self?.windowEvent(event) }
        attachToDock()
        // The Dock restarts after some settings changes; re-attach when it does.
        launchToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if bundle == DockModule.dockBundleID { self?.attachToDock() }
            }
        }
        if settings.clickAction != .none {
            clickTap = ClickTap { [weak self] in self?.handleClick() ?? false }
        }
    }

    func stop() {
        detachFromDock()
        if let launchToken { NSWorkspace.shared.notificationCenter.removeObserver(launchToken) }
        launchToken = nil
        clickTap?.invalidate()
        clickTap = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        service.release(self)
        hidePanel()
        panel = nil
    }

    // MARK: Dock observation

    private func attachToDock() {
        detachFromDock()
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleID).first else { return }
        let pid = dock.processIdentifier
        let app = WindowService.appElement(pid)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
              let elements = children as? [AXUIElement],
              let list = elements.first(where: { WindowService.string($0, kAXRoleAttribute) == (kAXListRole as String) }) else {
            Log.modules.error("Dock icon list not found")
            return
        }
        var observer: AXObserver?
        guard AXObserverCreate(pid, dockCallback, &observer) == .success, let observer else { return }
        AXObserverAddNotification(observer, list, kAXSelectedChildrenChangedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        self.list = list
    }

    private func detachFromDock() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        list = nil
        hoveredPID = nil
    }

    fileprivate func selectionChanged() {
        guard let list else { return }
        var selected: CFTypeRef?
        AXUIElementCopyAttributeValue(list, kAXSelectedChildrenAttribute as CFString, &selected)
        guard let item = (selected as? [AXUIElement])?.first,
              WindowService.string(item, kAXSubroleAttribute) == "AXApplicationDockItem",
              let app = runningApp(for: item) else {
            hoveredPID = nil
            hideUnlessHovered()
            return
        }
        hoveredPID = app.processIdentifier
        guard settings.showPreviews else { return }
        let windows = service.windows(ofApp: app.processIdentifier)
        guard !windows.isEmpty, let itemFrame = WindowService.frame(item) else {
            hideUnlessHovered()
            return
        }
        show(windows, anchor: itemFrame)
    }

    private func runningApp(for item: AXUIElement) -> NSRunningApplication? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &value) == .success,
              let url = value as? URL else { return nil }
        let path = url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL.path == path }
    }

    // MARK: Panel

    private func show(_ windows: [WindowInfo], anchor: LRect) {
        let panel = self.panel ?? DockPreviewPanel(model: viewModel) { [weak self] in self?.panelExited() }
        self.panel = panel
        viewModel.service = service
        viewModel.windows = windows
        viewModel.refreshThumbnails()
        panel.show(near: anchor)
        dockFrame = list.flatMap { WindowService.frame($0) }
        watchMouse()
        guard CGPreflightScreenCaptureAccess() else { return }
        let ids = windows.map(\.id)
        thumbnailTask?.cancel()
        thumbnailTask = Task { @MainActor [weak self] in
            await self?.service.loadThumbnails(for: ids)
            guard let self, !Task.isCancelled else { return }
            self.viewModel.refreshThumbnails()
        }
    }

    private func hideUnlessHovered() {
        guard let panel, panel.isVisible else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) { hidePanel() }
    }

    private func panelExited() {
        if hoveredPID == nil { hidePanel() }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        for m in moveMonitors { NSEvent.removeMonitor(m) }
        moveMonitors.removeAll()
    }

    /// The Dock does not always report that the mouse left it (an auto-hiding
    /// Dock just disappears), and the panel only sees an exit after an entry.
    /// While the preview is visible, every mouse move checks where it is.
    private func watchMouse() {
        guard moveMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { moveMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) { moveMonitors.append(m) }
    }

    private func mouseMoved() {
        guard let panel, panel.isVisible, let primary = NSScreen.screens.first else {
            hidePanel()
            return
        }
        let h = Double(primary.frame.height)
        let mouse = NSEvent.mouseLocation
        let panelFrame = CoordinateSpace.topLeft(fromCocoa: LRect(panel.frame), primaryHeight: h)
        if !DockPreviewHover.keepsPreview(mouseX: Double(mouse.x), mouseY: h - Double(mouse.y),
                                          panel: panelFrame, dock: dockFrame) {
            hoveredPID = nil
            hidePanel()
        }
    }

    private func windowEvent(_ event: WindowEvent) {
        guard let panel, panel.isVisible, let pid = hoveredPID else { return }
        let affected: pid_t?
        switch event {
        case .destroyed(let p, _), .created(let p, _), .changed(let p, _): affected = p
        case .focused, .appTerminated: affected = nil
        }
        guard affected == pid else { return }
        viewModel.windows = service.windows(ofApp: pid)
        viewModel.refreshThumbnails()
        if viewModel.windows.isEmpty { hidePanel() }
    }

    // MARK: Click on the active app's icon

    /// Returns true to swallow the click.
    private func handleClick() -> Bool {
        guard let pid = hoveredPID, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier == pid else { return false }
        switch settings.clickAction {
        case .none:
            return false
        case .hide:
            front.hide()
        case .minimize:
            for w in service.windows(ofApp: pid) where !w.isMinimized { service.minimize(w) }
        }
        hidePanel()
        return true
    }
}

private func dockCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let module = Unmanaged<DockModule>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { module.selectionChanged() }
}

// MARK: - Click tap

/// Active tap on left mouse down/up, installed only while the click option
/// is on. Swallows the down and the matching up when `shouldSwallow` says so.
@MainActor
private final class ClickTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate let shouldSwallow: @MainActor () -> Bool
    fileprivate var swallowingUp = false

    init(shouldSwallow: @escaping @MainActor () -> Bool) {
        self.shouldSwallow = shouldSwallow
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: clickTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.port = port
        self.source = source
    }

    func invalidate() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }

    fileprivate func reenable() {
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }
}

private func clickTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<ClickTap>.fromOpaque(refcon).takeUnretainedValue()
    let swallow: Bool = MainActor.assumeIsolated {
        switch type {
        case .tapDisabledByTimeout:
            tap.reenable()
            return false
        case .leftMouseDown:
            let s = tap.shouldSwallow()
            tap.swallowingUp = s
            return s
        case .leftMouseUp:
            let s = tap.swallowingUp
            tap.swallowingUp = false
            return s
        default:
            return false
        }
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

// MARK: - Preview panel

@MainActor
final class DockPreviewModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published private(set) var images: [CGWindowID: NSImage] = [:]
    weak var service: WindowService?

    func refreshThumbnails() {
        var out: [CGWindowID: NSImage] = [:]
        for w in windows {
            if let cg = service?.thumbnails.peek(w.id) { out[w.id] = NSImage(cgImage: cg, size: .zero) }
        }
        images = out
    }

    func activate(_ w: WindowInfo) { service?.activate(w) }
    func close(_ w: WindowInfo) { service?.close(w) }
    func minimize(_ w: WindowInfo) { service?.minimize(w) }
}

/// Created once and then only moved, shown and hidden.
@MainActor
final class DockPreviewPanel: NSPanel {
    private let onExit: @MainActor () -> Void

    init(model: DockPreviewModel, onExit: @escaping @MainActor () -> Void) {
        self.onExit = onExit
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let container = TrackingView { [weak self] in self?.onExit() }
        let host = NSHostingView(rootView: DockPreviewView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
    }

    /// Places the panel next to the Dock icon (`anchor` in AX coordinates),
    /// on the side away from the Dock.
    func show(near anchor: LRect) {
        guard let primary = NSScreen.screens.first, let content = contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let icon = CoordinateSpace.cocoa(fromTopLeft: anchor, primaryHeight: Double(primary.frame.height))
        let screen = NSScreen.screens.first { LRect($0.frame).intersection(icon).area > 0 } ?? primary
        let s = screen.frame
        var origin: NSPoint
        if icon.midY < Double(s.minY) + 200 { // Dock at the bottom
            origin = NSPoint(x: icon.midX - Double(size.width) / 2, y: icon.maxY + 6)
        } else if icon.midX < Double(s.midX) { // left
            origin = NSPoint(x: icon.maxX + 6, y: icon.midY - Double(size.height) / 2)
        } else { // right
            origin = NSPoint(x: icon.minX - Double(size.width) - 6, y: icon.midY - Double(size.height) / 2)
        }
        origin.x = min(max(origin.x, s.minX + 4), s.maxX - size.width - 4)
        origin.y = min(max(origin.y, s.minY + 4), s.maxY - size.height - 4)
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }
}

/// Reports when the mouse leaves the panel (event-driven tracking area).
private final class TrackingView: NSView {
    private let onExit: @MainActor () -> Void

    init(onExit: @escaping @MainActor () -> Void) {
        self.onExit = onExit
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onExit()
    }
}

struct DockPreviewView: View {
    @ObservedObject var model: DockPreviewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(model.windows, id: \.id) { w in
                VStack(spacing: 4) {
                    Group {
                        if let image = model.images[w.id] {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "macwindow").font(.system(size: 40)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 180, height: 110)
                    HStack(spacing: 4) {
                        Text(w.title.isEmpty ? w.appName : w.title).font(.caption).lineLimit(1)
                        Spacer(minLength: 2)
                        Button { model.minimize(w) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help(L("dock.minimize"))
                        Button { model.close(w) } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.borderless).help(L("dock.close"))
                    }
                    .frame(width: 180)
                }
                .padding(6)
                .contentShape(Rectangle())
                .onTapGesture { model.activate(w) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .fixedSize()
    }
}
