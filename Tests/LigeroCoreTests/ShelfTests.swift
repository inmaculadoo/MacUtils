import Foundation
import XCTest
@testable import LigeroCore

final class ShelfTests: XCTestCase {
    func testAddDedupesAndBounds() {
        var m = ShelfModel()
        m.add(.file(path: "/a"))
        m.add(.text("hola"))
        m.add(.file(path: "/a"))
        XCTAssertEqual(m.items, [.text("hola"), .file(path: "/a")])
        m.add(.text("  \n"))
        XCTAssertEqual(m.items.count, 2)
        for i in 0..<40 { m.add(.url("https://x/\(i)")) }
        XCTAssertEqual(m.items.count, ShelfModel.capacity)
        XCTAssertEqual(m.items.last, .url("https://x/39"))
    }

    func testPruneMissingFiles() {
        var m = ShelfModel(items: [.file(path: "/gone"), .file(path: "/here"), .text("t")])
        m.prune { $0 == "/here" }
        XCTAssertEqual(m.items, [.file(path: "/here"), .text("t")])
    }

    func testLabels() {
        XCTAssertEqual(ShelfItem.file(path: "/Users/example/Desktop/foto.png").label, "foto.png")
        XCTAssertEqual(ShelfItem.url("https://www.apple.com/mac").label, "www.apple.com")
        XCTAssertEqual(ShelfItem.text("primera\nsegunda").label, "primera")
        XCTAssertEqual(ShelfItem.text(String(repeating: "a", count: 50)).label.count, 40)
    }

    func testDragDetectorChecksOncePerGesture() {
        var d = DragDetector(changeCount: 5)
        // Text selection drag: pasteboard unchanged.
        XCTAssertTrue(d.draggedNeedsCheck())
        XCTAssertFalse(d.pasteboard(changeCount: 5))
        XCTAssertFalse(d.draggedNeedsCheck())
        d.mouseUp()
        // File drag: pasteboard changed.
        XCTAssertTrue(d.draggedNeedsCheck())
        XCTAssertTrue(d.pasteboard(changeCount: 6))
        XCTAssertFalse(d.draggedNeedsCheck())
        d.mouseUp()
        // Next gesture without a new drag.
        XCTAssertTrue(d.draggedNeedsCheck())
        XCTAssertFalse(d.pasteboard(changeCount: 6))
    }

    func testSettingsKeepExplicitlyClearedShortcut() {
        var s = ShelfSettings.default
        s.shortcut = nil
        s.pin("/Users/example/Desktop")
        s.pin("/Users/example/Desktop")
        let decoded = SettingsCoding.decode(ShelfSettings.self, from: SettingsCoding.encode(s))
        XCTAssertNil(decoded.shortcut)
        XCTAssertEqual(decoded.pinnedFolders, ["/Users/example/Desktop"])
        XCTAssertEqual(SettingsCoding.decode(ShelfSettings.self, from: Data("{}".utf8)).shortcut, ShelfSettings.default.shortcut)
    }
}
