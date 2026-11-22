import Foundation

/// A rectangle in a top-left-origin coordinate space (the one the
/// Accessibility API uses: the primary screen's top-left corner is 0,0 and y
/// grows downwards). Kept independent of CoreGraphics so the math runs on Linux.
public struct LRect: Equatable, Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = LRect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { max(0, width) * max(0, height) }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func intersection(_ other: LRect) -> LRect {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        guard x1 > x0, y1 > y0 else { return .zero }
        return LRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= minX && px < maxX && py >= minY && py < maxY
    }

    public func insetBy(_ d: Double) -> LRect {
        LRect(x: x + d, y: y + d, width: max(0, width - 2 * d), height: max(0, height - 2 * d))
    }

    /// Rounds the origin and size to whole points. AX coordinates are points,
    /// and fractional values make some apps nudge the window by one point.
    public var integral: LRect {
        let x0 = x.rounded()
        let y0 = y.rounded()
        return LRect(x: x0, y: y0, width: (x + width).rounded() - x0, height: (y + height).rounded() - y0)
    }

    /// True when every edge is within `tolerance` points of `other`.
    public func isClose(to other: LRect, tolerance: Double = 2) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    public var description: String { "(\(x), \(y), \(width)×\(height))" }
}

/// One display as seen by the snapping math, in top-left coordinates.
public struct ScreenInfo: Equatable, Sendable {
    /// Whole display.
    public var frame: LRect
    /// Display minus the menu bar (which already covers the notch) and the Dock.
    public var visibleFrame: LRect

    public init(frame: LRect, visibleFrame: LRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum CoordinateSpace {
    /// Converts a Cocoa rect (bottom-left origin, as NSScreen reports it) to the
    /// top-left space used by AX. `primaryHeight` is the height of the screen
    /// that contains the menu bar (`NSScreen.screens[0]`).
    public static func topLeft(fromCocoa r: LRect, primaryHeight: Double) -> LRect {
        LRect(x: r.x, y: primaryHeight - (r.y + r.height), width: r.width, height: r.height)
    }

    public static func cocoa(fromTopLeft r: LRect, primaryHeight: Double) -> LRect {
        // The transform is its own inverse.
        topLeft(fromCocoa: r, primaryHeight: primaryHeight)
    }
}
