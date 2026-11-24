/// Drag-to-edge zones of the Snap module: where the pointer is while a window
/// is dragged decides the placement (top-left AX coordinates).
///
///  - left / right edge: that half; near a corner, that quarter
///  - top edge: maximise; near a corner, that quarter
///  - bottom edge: only the corners (the middle is the Dock's)
///
/// Edges shared with another display are not zones, so windows can still be
/// dragged from one display to the other.
public enum SnapZones {
    public struct Zone: Equatable, Sendable {
        public var action: SnapAction
        /// Index of the display in the `screens` array passed in.
        public var screen: Int
    }

    public static func zone(atX x: Double, y: Double, screens: [ScreenInfo],
                            edge: Double = 6, corner: Double = 80) -> Zone? {
        let frames = screens.map(\.frame)
        guard let index = frames.firstIndex(where: { $0.contains(x: x, y: y) || onEdge(x, y, of: $0) }) else { return nil }
        let f = frames[index]
        let open = openEdges(of: f, among: frames)
        let nearTop = y - f.minY < corner
        let nearBottom = f.maxY - y < corner
        let nearLeft = x - f.minX < corner
        let nearRight = f.maxX - x < corner

        let action: SnapAction?
        if open.left && x - f.minX <= edge {
            action = nearTop ? .topLeft : nearBottom ? .bottomLeft : .leftHalf
        } else if open.right && f.maxX - x <= edge {
            action = nearTop ? .topRight : nearBottom ? .bottomRight : .rightHalf
        } else if open.top && y - f.minY <= edge {
            action = nearLeft ? .topLeft : nearRight ? .topRight : .maximize
        } else if open.bottom && f.maxY - y <= edge {
            action = nearLeft ? .bottomLeft : nearRight ? .bottomRight : nil
        } else {
            action = nil
        }
        return action.map { Zone(action: $0, screen: index) }
    }

    /// The pointer can sit on the very last pixel row/column (maxX - 1), but
    /// `contains` may exclude the max edge; accept it too.
    static func onEdge(_ x: Double, _ y: Double, of f: LRect) -> Bool {
        x >= f.minX && x <= f.maxX && y >= f.minY && y <= f.maxY
    }

    /// Edges of `screen` that no other display touches.
    public static func openEdges(of screen: LRect, among all: [LRect])
        -> (left: Bool, right: Bool, top: Bool, bottom: Bool) {
        var edges = (left: true, right: true, top: true, bottom: true)
        for other in all where other != screen {
            let vertical = other.minY < screen.maxY && other.maxY > screen.minY
            let horizontal = other.minX < screen.maxX && other.maxX > screen.minX
            if vertical && abs(other.maxX - screen.minX) < 2 { edges.left = false }
            if vertical && abs(other.minX - screen.maxX) < 2 { edges.right = false }
            if horizontal && abs(other.maxY - screen.minY) < 2 { edges.top = false }
            if horizontal && abs(other.minY - screen.maxY) < 2 { edges.bottom = false }
        }
        return edges
    }

    /// The frame `zone` gives a window, on the zone's display.
    public static func target(for zone: Zone, screens: [ScreenInfo], options: SnapEngine.Options) -> LRect? {
        guard screens.indices.contains(zone.screen) else { return nil }
        // A tiny rect in the middle of the display picks that display; the
        // zone actions don't depend on the window's own size.
        let v = screens[zone.screen].visibleFrame
        let probe = LRect(x: v.midX - 1, y: v.midY - 1, width: 2, height: 2)
        var plain = options
        plain.cycleHalves = false
        return SnapEngine.target(for: zone.action, window: probe, screens: screens, options: plain)
    }
}
