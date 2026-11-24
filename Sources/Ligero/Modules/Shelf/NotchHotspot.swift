import AppKit
import LigeroCore

/// An invisible window over each display's notch that reports when the
/// pointer enters or leaves it (SPEC §4.4, "hover the notch").
///
/// Idle cost: zero. The window server tracks the area and sends enter/exit
/// events; nothing watches the mouse. The window is opaque black, which is
/// what the notch looks like anyway (there are no pixels behind the camera),
/// and a fully transparent window would not receive mouse events.
@MainActor
final class NotchHotspot {
    /// Cocoa frame of the notch that was entered / left.
    var onEnter: (LRect) -> Void = { _ in }
    var onExit: (LRect) -> Void = { _ in }

    private var panels: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?

    func start() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        rebuild()
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
    }

    /// Displays come and go (external display, lid): one window per notch.
    private func rebuild() {
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
        for screen in NSScreen.screens {
            guard let notch = NotchHover.notchRect(screen: LRect(screen.frame),
                                                   topLeftArea: screen.auxiliaryTopLeftArea.map { LRect($0) },
                                                   topRightArea: screen.auxiliaryTopRightArea.map { LRect($0) }) else { continue }
            panels.append(makePanel(notch))
        }
    }

    private func makePanel(_ notch: LRect) -> NSPanel {
        let frame = NSRect(x: notch.x, y: notch.y, width: notch.width, height: notch.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = HoverView(frame: NSRect(origin: .zero, size: frame.size))
        view.onEnter = { [weak self] in self?.onEnter(notch) }
        view.onExit = { [weak self] in self?.onExit(notch) }
        panel.contentView = view
        panel.orderFrontRegardless()
        return panel
    }
}

/// A view that reports pointer enter/exit through a tracking area.
final class HoverView: NSView {
    var onEnter: @MainActor () -> Void = {}
    var onExit: @MainActor () -> Void = {}
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}
