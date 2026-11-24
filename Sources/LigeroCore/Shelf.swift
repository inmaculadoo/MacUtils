import Foundation

/// Something dropped on the shelf (SPEC §4.4).
public enum ShelfItem: Hashable, Codable, Sendable {
    case file(path: String)
    case url(String)
    case text(String)

    /// Short label for the item tile.
    public var label: String {
        switch self {
        case .file(let path): return (path as NSString).lastPathComponent
        case .url(let s): return URL(string: s)?.host ?? s
        case .text(let t):
            let line = t.split(whereSeparator: \.isNewline).first.map(String.init) ?? t
            return line.count > 40 ? String(line.prefix(39)) + "…" : line
        }
    }
}

/// The shelf contents: ordered, without duplicates, bounded.
public struct ShelfModel: Equatable, Sendable {
    public static let capacity = 30
    public private(set) var items: [ShelfItem] = []

    public init(items: [ShelfItem] = []) {
        for i in items { add(i) }
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Adds new items at the end; an item already on the shelf moves to the end.
    public mutating func add(_ item: ShelfItem) {
        if case .text(let t) = item, t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        items.removeAll { $0 == item }
        items.append(item)
        if items.count > Self.capacity { items.removeFirst(items.count - Self.capacity) }
    }

    public mutating func add(contentsOf new: [ShelfItem]) {
        for i in new { add(i) }
    }

    public mutating func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
    }

    /// Files whose path no longer exists are dropped (moved or deleted
    /// elsewhere while on the shelf).
    public mutating func prune(exists: (String) -> Bool) {
        items.removeAll {
            if case .file(let p) = $0 { return !exists(p) }
            return false
        }
    }

    public mutating func removeAll() { items.removeAll() }
}

/// Settings of the Shelf module.
public struct ShelfSettings: ModuleSettings {
    public var shortcut: KeyCombo?
    public var pinnedFolders: [String]
    public var showOnDrag: Bool
    /// Hovering the notch opens the shelf; leaving it closes it again.
    public var showOnNotchHover: Bool

    public init(shortcut: KeyCombo?, pinnedFolders: [String], showOnDrag: Bool, showOnNotchHover: Bool = true) {
        self.shortcut = shortcut
        self.pinnedFolders = pinnedFolders
        self.showOnDrag = showOnDrag
        self.showOnNotchHover = showOnNotchHover
    }

    public static let `default` = ShelfSettings(
        shortcut: KeyCombo(keyCode: KeyCode.s, modifiers: [.control, .option, .command]),
        pinnedFolders: [],
        showOnDrag: true
    )

    enum CodingKeys: String, CodingKey { case shortcut, pinnedFolders, showOnDrag, showOnNotchHover }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortcut = c.contains(.shortcut) ? c.value(.shortcut, or: nil) : Self.default.shortcut
        pinnedFolders = c.value(.pinnedFolders, or: [])
        showOnDrag = c.value(.showOnDrag, or: true)
        showOnNotchHover = c.value(.showOnNotchHover, or: true)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shortcut, forKey: .shortcut) // explicit null = "no shortcut"
        try c.encode(pinnedFolders, forKey: .pinnedFolders)
        try c.encode(showOnDrag, forKey: .showOnDrag)
        try c.encode(showOnNotchHover, forKey: .showOnNotchHover)
    }

    public mutating func pin(_ path: String) {
        guard !pinnedFolders.contains(path) else { return }
        pinnedFolders.append(path)
    }
}

/// Decides when a global `leftMouseDragged` stream means "a real drag with
/// content started" (SPEC §4.4). The drag pasteboard is read only on the
/// first dragged event of each mouse-down, never on every event.
public struct DragDetector: Sendable {
    private var inGesture = false
    private var lastChangeCount: Int

    public init(changeCount: Int) {
        lastChangeCount = changeCount
    }

    /// True on the first dragged event of a gesture: the caller then reads the
    /// pasteboard change count and calls `pasteboard(changeCount:)`.
    public mutating func draggedNeedsCheck() -> Bool {
        guard !inGesture else { return false }
        inGesture = true
        return true
    }

    /// Returns true when the drag pasteboard changed since the last drag,
    /// meaning files, text or URLs are being dragged.
    public mutating func pasteboard(changeCount: Int) -> Bool {
        defer { lastChangeCount = changeCount }
        return changeCount != lastChangeCount
    }

    public mutating func mouseUp() {
        inGesture = false
    }
}

/// Geometry of the "hover the notch to open the shelf" option (SPEC §4.4).
/// Cocoa coordinates (bottom-left origin), like NSScreen.
public enum NotchHover {
    /// The notch: between the two menu-bar areas beside the camera
    /// (`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`), as tall
    /// as those areas. Nil on displays without a notch.
    public static func notchRect(screen: LRect, topLeftArea: LRect?, topRightArea: LRect?) -> LRect? {
        guard let l = topLeftArea, let r = topRightArea, r.minX - l.maxX > 20 else { return nil }
        let height = min(l.height, r.height)
        guard height > 0 else { return nil }
        return LRect(x: l.maxX, y: screen.maxY - height, width: r.minX - l.maxX, height: height)
    }

    /// Whether a shelf opened by hovering stays open with the mouse here:
    /// over the notch, over the panel, or in the gap between them.
    public static func keepsShelf(mouseX x: Double, mouseY y: Double, notch: LRect, panel: LRect) -> Bool {
        let margin = 12.0
        func inside(_ r: LRect) -> Bool {
            x >= r.minX - margin && x <= r.maxX + margin && y >= r.minY - margin && y <= r.maxY + margin
        }
        let gapTop = notch.minY
        let gapBottom = panel.maxY
        let inGap = y <= gapTop + 1 && y >= gapBottom - 1 && x >= max(notch.minX, panel.minX) && x <= min(notch.maxX, panel.maxX)
        return inside(notch) || inside(panel) || inGap
    }
}
