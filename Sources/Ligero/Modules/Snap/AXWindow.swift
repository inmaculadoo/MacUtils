import AppKit
import ApplicationServices
import LigeroCore

/// Thin wrapper over the Accessibility API for the focused window. Each call
/// is a round trip to the target app (a few ms), so callers do as few as
/// possible and never animate (SPEC §2.3).
@MainActor
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    /// The focused window of the frontmost app, if it has one.
    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard err == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            Log.snap.debug("No focused window for pid \(pid): \(err.rawValue)")
            return nil
        }
        return AXWindow(element: value as! AXUIElement, pid: pid)
    }

    /// Stable identity for RestoreHistory: AX elements for the same window
    /// compare equal and hash the same.
    var key: WindowKey { WindowKey(pid: pid, hash: CFHash(element)) }

    var frame: LRect? {
        guard let origin = point(kAXPositionAttribute), let size = size(kAXSizeAttribute) else { return nil }
        return LRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    /// Size, then position, then size again: moving to a smaller display may
    /// clip the first resize, and some apps only accept a size that fits
    /// their current screen.
    func setFrame(_ r: LRect) {
        setSize(CGSize(width: r.width, height: r.height))
        setPosition(CGPoint(x: r.x, y: r.y))
        setSize(CGSize(width: r.width, height: r.height))
    }

    private func point(_ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
    }

    private func size(_ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
    }

    private func setPosition(_ p: CGPoint) {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v)
    }

    private func setSize(_ s: CGSize) {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v)
    }
}

struct WindowKey: Hashable {
    let pid: pid_t
    let hash: CFHashCode
}

enum ScreenGeometry {
    /// Current displays in AX (top-left) coordinates. Read on demand, when a
    /// shortcut is pressed, instead of observing display changes.
    @MainActor
    static func screens() -> [ScreenInfo] {
        let all = NSScreen.screens
        guard let primary = all.first else { return [] }
        let h = Double(primary.frame.height)
        return all.map { s in
            ScreenInfo(
                frame: CoordinateSpace.topLeft(fromCocoa: LRect(s.frame), primaryHeight: h),
                visibleFrame: CoordinateSpace.topLeft(fromCocoa: LRect(s.visibleFrame), primaryHeight: h)
            )
        }
    }
}
