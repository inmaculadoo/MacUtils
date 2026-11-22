import Foundation

/// Small LRU cache (thumbnails of the Switcher and Dock Previews). Bounded so
/// that RAM stays well under the 60 MB budget.
public struct LRUCache<Key: Hashable, Value> {
    public let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { values.count }
    public var keys: [Key] { order }

    public mutating func get(_ key: Key) -> Value? {
        guard let v = values[key] else { return nil }
        touch(key)
        return v
    }

    public func peek(_ key: Key) -> Value? { values[key] }

    public mutating func set(_ key: Key, _ value: Value) {
        values[key] = value
        touch(key)
        while order.count > capacity {
            let old = order.removeFirst()
            values.removeValue(forKey: old)
        }
    }

    public mutating func remove(_ key: Key) {
        values.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    public mutating func removeAll() {
        values.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

/// Most-recently-used order of windows.
public struct MRUList<ID: Hashable> {
    public private(set) var items: [ID] = []

    public init() {}

    public mutating func touch(_ id: ID) {
        items.removeAll { $0 == id }
        items.insert(id, at: 0)
    }

    public mutating func remove(_ id: ID) {
        items.removeAll { $0 == id }
    }

    /// `ids` sorted by recency; ids never focused keep their relative order
    /// after the known ones.
    public func sorted(_ ids: [ID]) -> [ID] {
        var rank: [ID: Int] = [:]
        for (i, id) in items.enumerated() { rank[id] = i }
        return ids.enumerated().sorted { a, b in
            switch (rank[a.element], rank[b.element]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }
}

/// Settings of the Switcher module (SPEC §4.5).
public struct SwitcherSettings: ModuleSettings {
    public var shortcut: KeyCombo?
    public var reverseShortcut: KeyCombo?
    public var showThumbnails: Bool

    public init(shortcut: KeyCombo?, reverseShortcut: KeyCombo?, showThumbnails: Bool) {
        self.shortcut = shortcut
        self.reverseShortcut = reverseShortcut
        self.showThumbnails = showThumbnails
    }

    public static let `default` = SwitcherSettings(
        shortcut: KeyCombo(keyCode: KeyCode.tab, modifiers: [.option]),
        reverseShortcut: KeyCombo(keyCode: KeyCode.tab, modifiers: [.option, .shift]),
        showThumbnails: true
    )

    enum CodingKeys: String, CodingKey { case shortcut, reverseShortcut, showThumbnails }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        shortcut = c.contains(.shortcut) ? c.value(.shortcut, or: nil) : d.shortcut
        reverseShortcut = c.contains(.reverseShortcut) ? c.value(.reverseShortcut, or: nil) : d.reverseShortcut
        showThumbnails = c.value(.showThumbnails, or: d.showThumbnails)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shortcut, forKey: .shortcut)
        try c.encode(reverseShortcut, forKey: .reverseShortcut)
        try c.encode(showThumbnails, forKey: .showThumbnails)
    }
}

public enum SwitcherSearch {
    /// Case- and accent-insensitive: every word of the query must appear in
    /// the title or the app name.
    public static func matches(_ query: String, title: String, app: String) -> Bool {
        let words = fold(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = fold(title) + " " + fold(app)
        return words.allSatisfy { haystack.contains($0) }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Cursor over the switcher list.
public struct SwitcherSelection: Equatable, Sendable {
    public private(set) var index: Int
    public private(set) var count: Int

    /// Opening the switcher selects the second item (the previous window),
    /// like ⌘Tab; reverse opening selects the last one.
    public init(count: Int, reverse: Bool = false) {
        self.count = count
        if count == 0 { index = 0 } else if reverse { index = count - 1 } else { index = min(1, count - 1) }
    }

    public mutating func next() { if count > 0 { index = (index + 1) % count } }
    public mutating func previous() { if count > 0 { index = (index + count - 1) % count } }

    /// Keeps the index valid when the list shrinks (search, closed window).
    public mutating func resize(to newCount: Int) {
        count = newCount
        index = newCount == 0 ? 0 : min(index, newCount - 1)
    }

    public mutating func select(_ i: Int) {
        guard count > 0 else { return }
        index = min(max(0, i), count - 1)
    }
}
