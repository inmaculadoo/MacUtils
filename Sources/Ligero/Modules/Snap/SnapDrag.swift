import AppKit
import LigeroCore

/// Drag a window to a screen edge or corner to snap it (SPEC §4.1).
///
/// Idle cost: zero. The apps themselves notify "window moved" (AXObserver via
/// WindowService). Only when that happens with the mouse button down, i.e.
/// the user is dragging a window, are two global mouse monitors added; both
/// go away on mouse-up. The preview panel exists only during that drag.
@MainActor
final class SnapDrag {
    /// Called on mouse-up in a zone with the window, its frame when the drag
    /// was noticed, and the zone.
    var onDrop: ((AXWindow, LRect, SnapZones.Zone) -> Void)?

    private var running = false
    private var options = SnapEngine.Options()
    private var window: AXWindow?
    private var before: LRect?
    private var zone: SnapZones.Zone?
    private var screens: [ScreenInfo] = []
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var preview: NSPanel?

    func start(options: SnapEngine.Options) {
        guard !running else { return }
        running = true
        self.options = options
        WindowService.shared.acquire(self) { [weak self] event in self?.windowEvent(event) }
    }

    func stop() {
        endDrag()
        guard running else { return }
        WindowService.shared.release(self)
        running = false
    }

    private func windowEvent(_ event: WindowEvent) {
        guard case .changed(let pid, let id) = event, let id, window == nil,
              NSEvent.pressedMouseButtons & 1 != 0, pid != ProcessInfo.processInfo.processIdentifier,
              let info = WindowService.shared.windows(ofApp: pid).first(where: { $0.id == id }),
              WindowService.isStandardWindow(info.element) else { return }
        let w = AXWindow(element: info.element, pid: pid)
        guard let frame = w.frame else { return }
        window = w
        before = frame
        screens = ScreenGeometry.screens()
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }
        mouseDragged()
    }

    private func mouseDragged() {
        guard window != nil, let primary = NSScreen.screens.first else { return }
        let m = NSEvent.mouseLocation
        let y = Double(primary.frame.height) - m.y
        let z = SnapZones.zone(atX: m.x, y: y, screens: screens)
        guard z != zone else { return }
        zone = z
        if let z, let target = SnapZones.target(for: z, screens: screens, options: options) {
            showPreview(target, primaryHeight: Double(primary.frame.height))
        } else {
            preview?.orderOut(nil)
        }
    }

    private func mouseUp() {
        let w = window, b = before, z = zone
        endDrag()
        // A resize that reached an edge is not a drop: the size changed.
        guard let w, let b, let z, let now = w.frame,
              abs(now.width - b.width) < 2, abs(now.height - b.height) < 2 else { return }
        onDrop?(w, b, z)
    }

    private func endDrag() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        dragMonitor = nil
        upMonitor = nil
        preview?.orderOut(nil)
        preview = nil
        window = nil
        before = nil
        zone = nil
        screens = []
    }

    /// Translucent frame where the window will go; no animation (SPEC §2.3).
    private func showPreview(_ target: LRect, primaryHeight: Double) {
        let panel = preview ?? Self.makePreview()
        preview = panel
        let r = CoordinateSpace.cocoa(fromTopLeft: target, primaryHeight: primaryHeight)
        panel.setFrame(NSRect(x: r.x, y: r.y, width: r.width, height: r.height), display: true)
        panel.orderFrontRegardless()
    }

    private static func makePreview() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 12
        panel.contentView = view
        return panel
    }
}
