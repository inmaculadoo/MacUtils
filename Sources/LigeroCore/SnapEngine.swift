/// Pure window-placement math for the Snap module (SPEC §4.1).
///
/// Everything is in the top-left coordinate space used by the Accessibility
/// API. The caller converts NSScreen frames with `CoordinateSpace` first.
public enum SnapEngine {
    public struct Options: Equatable, Sendable {
        /// Gap in points between windows and around the screen edge.
        public var gap: Double
        /// Repeating the left/right half shortcut cycles ½ → ⅔ → ⅓.
        public var cycleHalves: Bool

        public init(gap: Double = 0, cycleHalves: Bool = true) {
            self.gap = gap
            self.cycleHalves = cycleHalves
        }
    }

    /// The frame `action` should give a window that currently has `window`.
    ///
    /// Returns nil when there is nothing to do (no screens, or `.restore`,
    /// which the caller handles with `RestoreHistory`).
    public static func target(
        for action: SnapAction,
        window: LRect,
        screens: [ScreenInfo],
        options: Options = Options()
    ) -> LRect? {
        guard !screens.isEmpty else { return nil }
        let index = screenIndex(for: window, in: screens)
        let area = usableArea(of: screens[index], gap: options.gap)
        guard !area.isEmpty else { return nil }

        switch action {
        case .restore:
            return nil
        case .nextDisplay, .previousDisplay:
            let ordered = orderedIndices(screens)
            guard ordered.count > 1, let position = ordered.firstIndex(of: index) else { return nil }
            let step = action == .nextDisplay ? 1 : ordered.count - 1
            let destination = screens[ordered[(position + step) % ordered.count]]
            return move(window, from: area, to: usableArea(of: destination, gap: options.gap))
        case .center:
            let w = min(window.width, area.width)
            let h = min(window.height, area.height)
            return LRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h).integral
        case .maximize:
            return area.integral
        case .maximizeHeight:
            let w = min(window.width, area.width)
            let x = min(max(window.x, area.minX), area.maxX - w)
            return LRect(x: x, y: area.y, width: w, height: area.height).integral
        case .leftHalf, .rightHalf:
            let cycle = action == .leftHalf ? Self.leftCycle : Self.rightCycle
            var choice = cycle[0]
            if options.cycleHalves {
                let frames = cycle.map { column($0.0, $0.1, in: area, gap: options.gap) }
                if let current = frames.firstIndex(where: { $0.isClose(to: window) }) {
                    choice = cycle[(current + 1) % cycle.count]
                }
            }
            return column(choice.0, choice.1, in: area, gap: options.gap)
        case .topHalf:
            return cell(x: (0, 1), y: (0, 0.5), in: area, gap: options.gap)
        case .bottomHalf:
            return cell(x: (0, 1), y: (0.5, 1), in: area, gap: options.gap)
        case .topLeft:
            return cell(x: (0, 0.5), y: (0, 0.5), in: area, gap: options.gap)
        case .topRight:
            return cell(x: (0.5, 1), y: (0, 0.5), in: area, gap: options.gap)
        case .bottomLeft:
            return cell(x: (0, 0.5), y: (0.5, 1), in: area, gap: options.gap)
        case .bottomRight:
            return cell(x: (0.5, 1), y: (0.5, 1), in: area, gap: options.gap)
        case .firstThird:
            return third(0, 1.0 / 3, in: area, gap: options.gap)
        case .centerThird:
            return third(1.0 / 3, 2.0 / 3, in: area, gap: options.gap)
        case .lastThird:
            return third(2.0 / 3, 1, in: area, gap: options.gap)
        case .firstTwoThirds:
            return third(0, 2.0 / 3, in: area, gap: options.gap)
        case .lastTwoThirds:
            return third(1.0 / 3, 1, in: area, gap: options.gap)
        }
    }

    /// Column spans (as fractions of the width) the half shortcuts cycle through.
    static let leftCycle: [(Double, Double)] = [(0.0, 0.5), (0.0, 2.0 / 3.0), (0.0, 1.0 / 3.0)]
    static let rightCycle: [(Double, Double)] = [(0.5, 1.0), (1.0 / 3.0, 1.0), (2.0 / 3.0, 1.0)]

    // MARK: - Screens

    /// The screen that shows the largest part of `window`. Falls back to the
    /// screen containing its centre, then to the first (primary) screen.
    public static func screenIndex(for window: LRect, in screens: [ScreenInfo]) -> Int {
        var best = -1
        var bestArea = 0.0
        for (i, s) in screens.enumerated() {
            let a = s.frame.intersection(window).area
            if a > bestArea {
                bestArea = a
                best = i
            }
        }
        if best >= 0 { return best }
        if let i = screens.firstIndex(where: { $0.frame.contains(x: window.midX, y: window.midY) }) {
            return i
        }
        return 0
    }

    /// Screen indices ordered left to right, then top to bottom: the order used
    /// by next/previous display.
    public static func orderedIndices(_ screens: [ScreenInfo]) -> [Int] {
        screens.indices.sorted {
            let a = screens[$0].frame
            let b = screens[$1].frame
            return a.minX != b.minX ? a.minX < b.minX : a.minY < b.minY
        }
    }

    static func usableArea(of screen: ScreenInfo, gap: Double) -> LRect {
        screen.visibleFrame.insetBy(max(0, gap))
    }

    // MARK: - Building blocks

    /// Splits `length` starting at `origin` and returns the span between the
    /// fractions `a` and `b`, leaving half a gap on each inner edge so that two
    /// neighbouring spans are exactly `gap` apart.
    static func span(_ a: Double, _ b: Double, origin: Double, length: Double, gap: Double) -> (Double, Double) {
        let half: Double = gap / 2
        let leading: Double = a > 0.0001 ? half : 0
        let trailing: Double = b < 0.9999 ? half : 0
        let start: Double = origin + a * length + leading
        let end: Double = origin + b * length - trailing
        return (start, max(start, end))
    }

    static func cell(x: (Double, Double), y: (Double, Double), in area: LRect, gap: Double) -> LRect {
        let (x0, x1) = span(x.0, x.1, origin: area.x, length: area.width, gap: gap)
        let (y0, y1) = span(y.0, y.1, origin: area.y, length: area.height, gap: gap)
        return LRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).integral
    }

    static func column(_ a: Double, _ b: Double, in area: LRect, gap: Double) -> LRect {
        cell(x: (a, b), y: (0, 1), in: area, gap: gap)
    }

    /// Thirds run along the long side, so on a portrait display they stack
    /// vertically.
    static func third(_ a: Double, _ b: Double, in area: LRect, gap: Double) -> LRect {
        if area.height > area.width {
            return cell(x: (0, 1), y: (a, b), in: area, gap: gap)
        }
        return column(a, b, in: area, gap: gap)
    }

    /// Keeps the window's position and size relative to the usable area when
    /// moving it to another display, so a left half stays a left half.
    static func move(_ window: LRect, from source: LRect, to destination: LRect) -> LRect {
        let fx = (window.x - source.x) / source.width
        let fy = (window.y - source.y) / source.height
        let fw = window.width / source.width
        let fh = window.height / source.height
        var w = min(destination.width, fw * destination.width)
        var h = min(destination.height, fh * destination.height)
        w = max(1, w)
        h = max(1, h)
        var x = destination.x + fx * destination.width
        var y = destination.y + fy * destination.height
        x = min(max(x, destination.minX), destination.maxX - w)
        y = min(max(y, destination.minY), destination.maxY - h)
        return LRect(x: x, y: y, width: w, height: h).integral
    }

    /// Where to put a window that refused the target size (e.g. Safari's
    /// minimum width), so it stays on the target's screen. A target touching
    /// the right or bottom edge keeps that edge; otherwise the origin is kept
    /// and only pulled back as far as needed. Nil when no move is needed.
    public static func settle(actual: LRect, target: LRect, screens: [ScreenInfo], gap: Double = 0) -> LRect? {
        guard !screens.isEmpty, !actual.isClose(to: target, tolerance: 0.5) else { return nil }
        let area = usableArea(of: screens[screenIndex(for: target, in: screens)], gap: gap)
        func place(_ start: Double, _ end: Double, _ size: Double, _ lo: Double, _ hi: Double) -> Double {
            let anchored = end >= hi - 1 ? hi - size : min(start, hi - size)
            return max(lo, anchored)
        }
        let x = place(target.minX, target.maxX, actual.width, area.minX, area.maxX)
        let y = place(target.minY, target.maxY, actual.height, area.minY, area.maxY)
        let settled = LRect(x: x, y: y, width: actual.width, height: actual.height).integral
        return settled.isClose(to: actual, tolerance: 0.5) ? nil : settled
    }
}

/// Remembers the frame a window had before Ligero first snapped it, so that
/// `.restore` can put it back (SPEC §4.1, "restore the previous size").
public struct RestoreHistory<Key: Hashable> {
    struct Entry {
        var original: LRect
        var applied: LRect
        var target: LRect
        var stamp: Int
    }

    public let capacity: Int
    private var entries: [Key: Entry] = [:]
    private var clock = 0

    public init(capacity: Int = 50) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { entries.count }

    /// Call after moving a window from `current` to `applied`, the frame it
    /// really ended up with. `target` is the frame Ligero asked for (defaults
    /// to `applied`); apps that round their size (Terminal) or have a minimum
    /// size end up somewhere close but different.
    ///
    /// If the window is still where Ligero last put it, the original frame is
    /// kept (snap → snap → restore goes back to the very first frame). If the
    /// user has moved it by hand since, the current frame becomes the new
    /// original.
    public mutating func record(_ key: Key, current: LRect, applied: LRect, target: LRect? = nil) {
        clock += 1
        let target = target ?? applied
        if var e = entries[key], e.applied.isClose(to: current) {
            e.applied = applied
            e.target = target
            e.stamp = clock
            entries[key] = e
        } else {
            entries[key] = Entry(original: current, applied: applied, target: target, stamp: clock)
        }
        if entries.count > capacity, let oldest = entries.min(by: { $0.value.stamp < $1.value.stamp })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    /// The frame Ligero last asked for, if the window is still where Ligero
    /// left it. Used instead of the real frame to recognise the current
    /// layout (e.g. to keep cycling ½ → ⅔ → ⅓ in Terminal).
    public func lastTarget(_ key: Key, current: LRect) -> LRect? {
        guard let e = entries[key], e.applied.isClose(to: current) else { return nil }
        return e.target
    }

    /// For a window dragged by the user: the frame Ligero last gave it, if
    /// the drag only moved it (same size). Dragging a snapped window to
    /// another edge then keeps the chain, so restore still goes back to the
    /// frame from before the first snap.
    public func appliedBeforeDrag(_ key: Key, dragged: LRect, tolerance: Double = 2) -> LRect? {
        guard let e = entries[key], abs(e.applied.width - dragged.width) <= tolerance,
              abs(e.applied.height - dragged.height) <= tolerance else { return nil }
        return e.applied
    }

    /// The frame to restore, removing it from the history.
    public mutating func takeOriginal(_ key: Key) -> LRect? {
        entries.removeValue(forKey: key)?.original
    }

    public mutating func removeAll() {
        entries.removeAll()
    }
}
