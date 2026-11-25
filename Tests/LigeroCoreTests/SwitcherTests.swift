import Foundation
import XCTest
@testable import LigeroCore

final class SwitcherTests: XCTestCase {
    func testLRUEvictsLeastRecentlyUsed() {
        var c = LRUCache<Int, String>(capacity: 2)
        c.set(1, "a")
        c.set(2, "b")
        XCTAssertEqual(c.get(1), "a") // 1 is now most recent
        c.set(3, "c")
        XCTAssertNil(c.peek(2))
        XCTAssertEqual(c.keys, [1, 3])
        c.remove(1)
        XCTAssertEqual(c.count, 1)
        c.set(3, "c2")
        XCTAssertEqual(c.peek(3), "c2")
        c.removeAll()
        XCTAssertEqual(c.count, 0)
    }

    func testMRUOrdering() {
        var m = MRUList<Int>()
        m.touch(1)
        m.touch(2)
        m.touch(1)
        XCTAssertEqual(m.items, [1, 2])
        XCTAssertEqual(m.sorted([5, 2, 6, 1]), [1, 2, 5, 6])
        m.remove(1)
        XCTAssertEqual(m.sorted([1, 2]), [2, 1])
    }

    func testSearchIsCaseAndAccentInsensitive() {
        XCTAssertTrue(SwitcherSearch.matches("cancion", title: "Canción triste", app: "Música"))
        XCTAssertTrue(SwitcherSearch.matches("mus tris", title: "Canción triste", app: "Música"))
        XCTAssertFalse(SwitcherSearch.matches("safari", title: "Canción", app: "Música"))
        XCTAssertTrue(SwitcherSearch.matches("  ", title: "x", app: "y"))
    }

    func testSelection() {
        var s = SwitcherSelection(count: 3)
        XCTAssertEqual(s.index, 1)
        s.next()
        s.next()
        XCTAssertEqual(s.index, 0)
        s.previous()
        XCTAssertEqual(s.index, 2)
        s.resize(to: 1)
        XCTAssertEqual(s.index, 0)
        XCTAssertEqual(SwitcherSelection(count: 1).index, 0)
        XCTAssertEqual(SwitcherSelection(count: 4, reverse: true).index, 3)
        var e = SwitcherSelection(count: 0)
        e.next()
        XCTAssertEqual(e.index, 0)
        var t = SwitcherSelection(count: 5)
        t.select(99)
        XCTAssertEqual(t.index, 4)
    }

    func testSettings() {
        XCTAssertEqual(SwitcherSettings.default.shortcut?.description, "⌥⇥")
        var s = SwitcherSettings.default
        s.reverseShortcut = nil
        XCTAssertNil(SettingsCoding.decode(SwitcherSettings.self, from: SettingsCoding.encode(s)).reverseShortcut)
    }

    func testDockSettings() {
        XCTAssertEqual(DockSettings.default.clickAction, .none)
        let s = SettingsCoding.decode(DockSettings.self, from: Data(#"{"clickAction": "hide", "showPreviews": false}"#.utf8))
        XCTAssertEqual(s.clickAction, .hide)
        XCTAssertFalse(s.showPreviews)
        XCTAssertEqual(SettingsCoding.decode(DockSettings.self, from: Data(#"{"clickAction": "explode"}"#.utf8)).clickAction, .none)
    }
}
