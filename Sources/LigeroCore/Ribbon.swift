/// Pure model of a Ribbon strip (SPEC §4.12): per display, windows form a row
/// of columns with fixed widths; the strip scrolls horizontally and windows
/// outside the viewport are parked at the edge with 1 pt visible.
///
/// Coordinates are top-left (AX). `viewport` is the display's visible frame.

/// Fixed column widths, as a fraction of the viewport.
public enum ColumnWidth: String, CaseIterable, Codable, Sendable {
    case quarter, third, half, twoThirds, threeQuarters, full

    public var fraction: Double {
        switch self {
        case .quarter: return 0.25
        case .third: return 1.0 / 3.0
        case .half: return 0.5
        case .twoThirds: return 2.0 / 3.0
        case .threeQuarters: return 0.75
        case .full: return 1
        }
    }

    public func next(backwards: Bool = false) -> ColumnWidth {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        let j = backwards ? (i + all.count - 1) % all.count : (i + 1) % all.count
        return all[j]
    }
}

public struct RibbonColumn<ID: Hashable>: Equatable {
    public var windows: [ID]
    public var width: ColumnWidth
    /// Row that gets focus when the column is focused.
    public var active: Int

    public init(windows: [ID], width: ColumnWidth, active: Int = 0) {
        self.windows = windows
        self.width = width
        self.active = active
    }
}

public struct RibbonPosition: Equatable, Sendable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// Where a window should be.
public struct RibbonPlacement: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case visible
        case parkedLeft
        case parkedRight
    }

    public var frame: LRect
    public var state: State
}

public struct RibbonStrip<ID: Hashable> {
    public private(set) var columns: [RibbonColumn<ID>] = []
    public private(set) var focus: RibbonPosition?
    /// Horizontal scroll in points: 0 shows the first column at the left edge.
    public private(set) var offset: Double = 0
    public var viewport: LRect {
        didSet { clampOffset() }
    }
    public var gap: Double {
        didSet { clampOffset() }
    }
    public var defaultWidth: ColumnWidth
    /// Which edges may receive parked windows. A side that touches another
    /// display must not be used, or the window would show up there.
    public var canParkLeft = true
    public var canParkRight = true

    public init(viewport: LRect, gap: Double = 0, defaultWidth: ColumnWidth = .half) {
        self.viewport = viewport
        self.gap = max(0, gap)
        self.defaultWidth = defaultWidth
    }

    // MARK: Queries

    public var windowIDs: [ID] { columns.flatMap(\.windows) }
    public var isEmpty: Bool { columns.isEmpty }

    public func position(of id: ID) -> RibbonPosition? {
        for (c, column) in columns.enumerated() {
            if let r = column.windows.firstIndex(of: id) { return RibbonPosition(column: c, row: r) }
        }
        return nil
    }

    public var focusedWindow: ID? {
        guard let f = focus, columns.indices.contains(f.column), columns[f.column].windows.indices.contains(f.row) else { return nil }
        return columns[f.column].windows[f.row]
    }

    /// Column width in points: n columns of 1/n plus their gaps fill the viewport.
    public func points(for width: ColumnWidth) -> Double {
        max(1, width.fraction * (viewport.width - gap) - gap)
    }

    /// Left edge of column `index` in strip coordinates (0 = strip start).
    public func columnX(_ index: Int) -> Double {
        var x = gap
        for i in 0..<min(index, columns.count) {
            x += points(for: columns[i].width) + gap
        }
        return x
    }

    public var contentWidth: Double { columnX(columns.count) }
    public var maxOffset: Double { max(0, contentWidth - viewport.width) }

    // MARK: Editing

    /// Adds a window as a new column right after the focused one (or at the
    /// end), focuses it and scrolls it into view. Other columns keep their size.
    public mutating func insert(_ id: ID, width: ColumnWidth? = nil) {
        guard position(of: id) == nil else { return focusWindow(id) }
        let index = focus.map { $0.column + 1 } ?? columns.count
        columns.insert(RibbonColumn(windows: [id], width: width ?? defaultWidth), at: index)
        focus = RibbonPosition(column: index, row: 0)
        ensureVisible(index)
    }

    /// Removes a window. Returns the width of its column if the column
    /// disappeared with it (so it can be recreated on another display).
    @discardableResult
    public mutating func remove(_ id: ID) -> ColumnWidth? {
        guard let p = position(of: id) else { return nil }
        let focusedBefore = focusedWindow
        columns[p.column].windows.remove(at: p.row)
        var removedWidth: ColumnWidth?
        if columns[p.column].windows.isEmpty {
            removedWidth = columns[p.column].width
            columns.remove(at: p.column)
        } else {
            let c = columns[p.column]
            columns[p.column].active = min(c.active > p.row ? c.active - 1 : c.active, c.windows.count - 1)
        }
        if columns.isEmpty {
            focus = nil
        } else if focusedBefore == id {
            // Focus the neighbour: same column if it survived, else the column to the left.
            if removedWidth == nil {
                focus = RibbonPosition(column: p.column, row: min(p.row, columns[p.column].windows.count - 1))
            } else {
                let c = max(0, min(p.column - 1, columns.count - 1))
                focus = RibbonPosition(column: c, row: columns[c].active)
            }
        } else if let other = focusedBefore {
            focus = position(of: other)
        }
        clampOffset()
        if let f = focus { ensureVisible(f.column) }
        return removedWidth
    }

    /// Follows a focus change made outside Ligero (click, ⌘Tab).
    public mutating func focusWindow(_ id: ID) {
        guard let p = position(of: id) else { return }
        focus = p
        columns[p.column].active = p.row
        ensureVisible(p.column)
    }

    @discardableResult
    public mutating func focusLeft() -> ID? { moveFocus(columns: -1) }
    @discardableResult
    public mutating func focusRight() -> ID? { moveFocus(columns: 1) }

    @discardableResult
    public mutating func focusUp() -> ID? { moveFocus(rows: -1) }
    @discardableResult
    public mutating func focusDown() -> ID? { moveFocus(rows: 1) }

    private mutating func moveFocus(columns dc: Int = 0, rows dr: Int = 0) -> ID? {
        guard let f = focus else { return nil }
        if dc != 0 {
            let c = f.column + dc
            guard columns.indices.contains(c) else { return nil }
            focus = RibbonPosition(column: c, row: min(columns[c].active, columns[c].windows.count - 1))
            ensureVisible(c)
        } else {
            let r = f.row + dr
            guard columns[f.column].windows.indices.contains(r) else { return nil }
            focus = RibbonPosition(column: f.column, row: r)
            columns[f.column].active = r
        }
        return focusedWindow
    }

    public mutating func moveColumnLeft() { moveColumn(by: -1) }
    public mutating func moveColumnRight() { moveColumn(by: 1) }

    private mutating func moveColumn(by d: Int) {
        guard let f = focus else { return }
        let target = f.column + d
        guard columns.indices.contains(target) else { return }
        columns.swapAt(f.column, target)
        focus = RibbonPosition(column: target, row: f.row)
        ensureVisible(target)
    }

    public mutating func cycleWidth(backwards: Bool = false) {
        guard let f = focus else { return }
        columns[f.column].width = columns[f.column].width.next(backwards: backwards)
        clampOffset()
        ensureVisible(f.column)
    }

    public mutating func setWidth(_ width: ColumnWidth) {
        guard let f = focus else { return }
        columns[f.column].width = width
        clampOffset()
        ensureVisible(f.column)
    }

    /// Moves the focused window to the bottom of the column on its left.
    public mutating func stackIntoLeft() {
        guard let f = focus, f.column > 0, let id = focusedWindow else { return }
        columns[f.column].windows.remove(at: f.row)
        var target = f.column - 1
        if columns[f.column].windows.isEmpty {
            columns.remove(at: f.column)
        } else {
            columns[f.column].active = min(columns[f.column].active, columns[f.column].windows.count - 1)
        }
        target = min(target, columns.count - 1)
        columns[target].windows.append(id)
        let row = columns[target].windows.count - 1
        columns[target].active = row
        focus = RibbonPosition(column: target, row: row)
        clampOffset()
        ensureVisible(target)
    }

    /// Takes the focused window out of a stacked column into its own column
    /// on the right.
    public mutating func expel() {
        guard let f = focus, columns[f.column].windows.count > 1, let id = focusedWindow else { return }
        columns[f.column].windows.remove(at: f.row)
        columns[f.column].active = min(columns[f.column].active, columns[f.column].windows.count - 1)
        columns.insert(RibbonColumn(windows: [id], width: columns[f.column].width), at: f.column + 1)
        focus = RibbonPosition(column: f.column + 1, row: 0)
        ensureVisible(f.column + 1)
    }

    // MARK: Scrolling

    public mutating func scroll(by dx: Double) {
        offset += dx
        clampOffset()
    }

    /// Minimal scroll that shows the whole column (with its gaps).
    public mutating func ensureVisible(_ index: Int) {
        guard columns.indices.contains(index) else { return }
        let left = columnX(index) - gap
        let right = columnX(index) + points(for: columns[index].width) + gap
        if left < offset {
            offset = left
        } else if right > offset + viewport.width {
            offset = right - viewport.width
        }
        clampOffset()
    }

    private mutating func clampOffset() {
        offset = min(max(0, offset), maxOffset)
    }

    // MARK: Layout

    /// Target frame of every window. Columns fully outside the viewport are
    /// parked with 1 pt visible at an allowed edge.
    public func layout() -> [ID: RibbonPlacement] {
        var result: [ID: RibbonPlacement] = [:]
        let height = max(1, viewport.height - 2 * gap)
        for (i, column) in columns.enumerated() {
            let w = points(for: column.width)
            let x = viewport.x + columnX(i) - offset
            let n = Double(column.windows.count)
            let h = max(1, (height - (n - 1) * gap) / n)
            var state = RibbonPlacement.State.visible
            var frameX = x
            if x + w <= viewport.minX {
                state = canParkLeft || !canParkRight ? .parkedLeft : .parkedRight
            } else if x >= viewport.maxX {
                state = canParkRight || !canParkLeft ? .parkedRight : .parkedLeft
            }
            switch state {
            case .parkedLeft: frameX = viewport.minX - w + 1
            case .parkedRight: frameX = viewport.maxX - 1
            case .visible: break
            }
            for (r, id) in column.windows.enumerated() {
                let y = viewport.y + gap + Double(r) * (h + gap)
                result[id] = RibbonPlacement(frame: LRect(x: frameX, y: y, width: w, height: h).integral, state: state)
            }
        }
        return result
    }

    /// Windows whose target frame differs from where they are now: the only
    /// ones that need an AX call (SPEC §4.12).
    public static func windowsToMove(current: [ID: LRect], target: [ID: RibbonPlacement], tolerance: Double = 1) -> [ID] {
        target.compactMap { id, placement in
            guard let now = current[id] else { return id }
            return now.isClose(to: placement.frame, tolerance: tolerance) ? nil : id
        }
    }

    // MARK: Building

    /// Builds a strip from existing windows ordered left to right by their
    /// current x, each in its own column with the closest width.
    public static func adopting(_ windows: [(id: ID, frame: LRect)], viewport: LRect, gap: Double = 0) -> RibbonStrip {
        var strip = RibbonStrip(viewport: viewport, gap: gap)
        for w in windows.sorted(by: { $0.frame.x < $1.frame.x }) {
            strip.columns.append(RibbonColumn(windows: [w.id], width: closestWidth(w.frame.width, in: strip)))
        }
        if !strip.columns.isEmpty { strip.focus = RibbonPosition(column: 0, row: 0) }
        return strip
    }

    static func closestWidth(_ points: Double, in strip: RibbonStrip) -> ColumnWidth {
        ColumnWidth.allCases.min { abs(strip.points(for: $0) - points) < abs(strip.points(for: $1) - points) } ?? .half
    }
}
