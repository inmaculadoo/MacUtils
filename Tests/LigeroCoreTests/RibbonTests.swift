import Foundation
import XCTest
@testable import LigeroCore

final class RibbonTests: XCTestCase {
    // 1200×800 viewport starting at x=0, y=30 (menu bar).
    let vp = LRect(x: 0, y: 30, width: 1200, height: 800)

    func strip(_ ids: [Int], width: ColumnWidth = .half, gap: Double = 0) -> RibbonStrip<Int> {
        var s = RibbonStrip<Int>(viewport: vp, gap: gap, defaultWidth: width)
        for id in ids { s.insert(id) }
        return s
    }

    // MARK: Widths

    func testWidthsFillViewportWithGaps() {
        let s = RibbonStrip<Int>(viewport: vp, gap: 10)
        XCTAssertEqual(s.points(for: .full), 1180)
        XCTAssertEqual(2 * s.points(for: .half) + 3 * 10, 1200, accuracy: 1e-9)
        XCTAssertEqual(3 * s.points(for: .third) + 4 * 10, 1200, accuracy: 1e-9)
        XCTAssertEqual(4 * s.points(for: .quarter) + 5 * 10, 1200, accuracy: 1e-9)
        XCTAssertEqual(s.points(for: .twoThirds) + s.points(for: .third) + 3 * 10, 1200, accuracy: 1e-9)
    }

    func testWidthCycle() {
        XCTAssertEqual(ColumnWidth.quarter.next(), .third)
        XCTAssertEqual(ColumnWidth.full.next(), .quarter)
        XCTAssertEqual(ColumnWidth.quarter.next(backwards: true), .full)
    }

    // MARK: Insertion

    func testInsertGoesRightOfFocusedAndKeepsOthersSize() {
        var s = strip([1, 2, 3])
        XCTAssertEqual(s.windowIDs, [1, 2, 3])
        XCTAssertEqual(s.focusedWindow, 3)
        s.focusWindow(1)
        s.insert(9, width: .third)
        XCTAssertEqual(s.windowIDs, [1, 9, 2, 3])
        XCTAssertEqual(s.focusedWindow, 9)
        XCTAssertEqual(s.columns.map(\.width), [.half, .third, .half, .half])
    }

    func testInsertExistingJustFocuses() {
        var s = strip([1, 2])
        s.insert(1)
        XCTAssertEqual(s.windowIDs, [1, 2])
        XCTAssertEqual(s.focusedWindow, 1)
    }

    func testInsertScrollsNewColumnIntoView() {
        let s = strip([1, 2, 3, 4])
        // Four halves: content 2400, viewport 1200: the last two are visible.
        XCTAssertEqual(s.offset, 1200)
        let l = s.layout()
        XCTAssertEqual(l[4]?.state, .visible)
        XCTAssertEqual(l[3]?.state, .visible)
        XCTAssertEqual(l[1]?.state, .parkedLeft)
    }

    // MARK: Removal

    func testRemoveFocusedFocusesLeftNeighbour() {
        var s = strip([1, 2, 3])
        s.focusWindow(2)
        XCTAssertEqual(s.remove(2), .half)
        XCTAssertEqual(s.windowIDs, [1, 3])
        XCTAssertEqual(s.focusedWindow, 1)
        s.remove(1)
        XCTAssertEqual(s.focusedWindow, 3)
        s.remove(3)
        XCTAssertNil(s.focus)
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.remove(42))
    }

    func testRemoveUnfocusedKeepsFocusedWindow() {
        var s = strip([1, 2, 3])
        s.focusWindow(3)
        s.remove(1)
        XCTAssertEqual(s.focusedWindow, 3)
        XCTAssertEqual(s.focus, RibbonPosition(column: 1, row: 0))
    }

    func testRemoveFromStackKeepsColumn() {
        var s = strip([1, 2, 3])
        s.focusWindow(3)
        s.stackIntoLeft() // column 1 = [2, 3]
        XCTAssertNil(s.remove(3))
        XCTAssertEqual(s.columns.count, 2)
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testRemoveClampsOffset() {
        var s = strip([1, 2, 3, 4])
        XCTAssertEqual(s.offset, 1200)
        s.remove(4)
        s.remove(3)
        XCTAssertEqual(s.offset, 0)
    }

    // MARK: Focus and scrolling

    func testFocusLeftRightScrollsMinimally() {
        var s = strip([1, 2, 3, 4])
        XCTAssertEqual(s.focusLeft(), 3)
        XCTAssertEqual(s.offset, 1200) // already visible
        XCTAssertEqual(s.focusLeft(), 2)
        XCTAssertEqual(s.offset, 600)
        XCTAssertEqual(s.focusLeft(), 1)
        XCTAssertEqual(s.offset, 0)
        XCTAssertNil(s.focusLeft())
        XCTAssertEqual(s.focusedWindow, 1)
        XCTAssertEqual(s.focusRight(), 2)
        XCTAssertEqual(s.offset, 0)
        XCTAssertEqual(s.focusRight(), 3)
        XCTAssertEqual(s.offset, 600)
    }

    func testFocusRemembersActiveRow() {
        var s = strip([1, 2, 3])
        s.focusWindow(2)
        s.stackIntoLeft() // column 0 = [1, 2]
        XCTAssertEqual(s.focusedWindow, 2)
        XCTAssertEqual(s.focusUp(), 1)
        XCTAssertNil(s.focusUp())
        XCTAssertEqual(s.focusRight(), 3)
        XCTAssertEqual(s.focusLeft(), 1) // remembered row 0
        XCTAssertEqual(s.focusDown(), 2)
        XCTAssertNil(s.focusDown())
    }

    func testScrollClamps() {
        var s = strip([1, 2, 3])
        s.scroll(by: -5000)
        XCTAssertEqual(s.offset, 0)
        s.scroll(by: 5000)
        XCTAssertEqual(s.offset, s.maxOffset)
        XCTAssertEqual(s.maxOffset, 600)
        var single = strip([1])
        single.scroll(by: 300)
        XCTAssertEqual(single.offset, 0)
    }

    func testWideColumnAlignsLeftEdgeWhenFocusedFromRight() {
        var s = strip([1, 2], width: .full)
        XCTAssertEqual(s.offset, 1200)
        s.focusLeft()
        XCTAssertEqual(s.offset, 0)
    }

    // MARK: Moving, widths, stacking

    func testMoveColumn() {
        var s = strip([1, 2, 3])
        s.focusWindow(1)
        s.moveColumnRight()
        XCTAssertEqual(s.windowIDs, [2, 1, 3])
        XCTAssertEqual(s.focusedWindow, 1)
        s.moveColumnRight()
        s.moveColumnRight() // at the end: no-op
        XCTAssertEqual(s.windowIDs, [2, 3, 1])
        s.moveColumnLeft()
        XCTAssertEqual(s.windowIDs, [2, 1, 3])
    }

    func testCycleWidthOnlyChangesFocusedColumn() {
        var s = strip([1, 2])
        s.focusWindow(1)
        s.cycleWidth()
        XCTAssertEqual(s.columns.map(\.width), [.twoThirds, .half])
        s.cycleWidth(backwards: true)
        s.cycleWidth(backwards: true)
        XCTAssertEqual(s.columns.map(\.width), [.third, .half])
        s.setWidth(.full)
        XCTAssertEqual(s.columns[0].width, .full)
    }

    func testStackAndExpel() {
        var s = strip([1, 2, 3])
        s.focusWindow(3)
        s.stackIntoLeft()
        XCTAssertEqual(s.columns.map(\.windows), [[1], [2, 3]])
        XCTAssertEqual(s.focusedWindow, 3)
        s.stackIntoLeft()
        XCTAssertEqual(s.columns.map(\.windows), [[1, 3], [2]])
        s.focusWindow(1)
        s.stackIntoLeft() // first column: nothing on the left
        XCTAssertEqual(s.columns.map(\.windows), [[1, 3], [2]])
        s.expel()
        XCTAssertEqual(s.columns.map(\.windows), [[3], [1], [2]])
        XCTAssertEqual(s.focusedWindow, 1)
        s.expel() // single window column: no-op
        XCTAssertEqual(s.columns.count, 3)
    }

    // MARK: Layout

    func testLayoutFramesWithGap() {
        var s = strip([1, 2], gap: 10)
        s.focusWindow(1)
        let l = s.layout()
        XCTAssertEqual(l[1]?.frame, LRect(x: 10, y: 40, width: 585, height: 780))
        XCTAssertEqual(l[2]?.frame, LRect(x: 605, y: 40, width: 585, height: 780))
        XCTAssertEqual(l[2]?.state, .visible)
    }

    func testStackedRowsSplitHeight() {
        var s = strip([1, 2, 3], gap: 10)
        s.focusWindow(2)
        s.stackIntoLeft()
        let l = s.layout()
        XCTAssertEqual(l[1]?.frame.height, 385)
        XCTAssertEqual(l[2]?.frame.y, 435)
        XCTAssertEqual(l[1]?.frame.x, l[2]?.frame.x)
    }

    func testParkingLeavesOnePointVisible() {
        let s = strip([1, 2, 3, 4])
        let l = s.layout()
        XCTAssertEqual(l[1]?.state, .parkedLeft)
        XCTAssertEqual(l[1]?.frame.maxX, vp.minX + 1)
        var s2 = s
        s2.focusWindow(1) // offset 0: 3 and 4 off the right edge
        let l2 = s2.layout()
        XCTAssertEqual(l2[3]?.state, .parkedRight)
        XCTAssertEqual(l2[3]?.frame.x, vp.maxX - 1)
        XCTAssertEqual(l2[4]?.frame.x, vp.maxX - 1)
    }

    func testPartiallyVisibleColumnIsNotParked() {
        var s = strip([1, 2], width: .twoThirds)
        s.focusWindow(1)
        let l = s.layout()
        XCTAssertEqual(l[2]?.state, .visible)
        XCTAssertLessThan(l[2]!.frame.x, vp.maxX)
    }

    func testParkingAvoidsEdgeTouchingAnotherDisplay() {
        var s = strip([1, 2, 3, 4])
        s.canParkLeft = false // a display sits to the left
        XCTAssertEqual(s.layout()[1]?.state, .parkedRight)
        s.canParkRight = false // nowhere is safe: fall back to the natural side
        XCTAssertEqual(s.layout()[1]?.state, .parkedLeft)
    }

    func testOnlyChangedWindowsMove() {
        var s = strip([1, 2, 3])
        s.focusWindow(1)
        let before = s.layout()
        var current = before.mapValues(\.frame)
        current[3] = LRect(x: 5, y: 5, width: 5, height: 5) // moved by the user
        XCTAssertEqual(RibbonStrip<Int>.windowsToMove(current: current, target: before), [3])
        s.focusWindow(3) // scrolls by 600
        let after = s.layout()
        XCTAssertEqual(Set(RibbonStrip<Int>.windowsToMove(current: before.mapValues(\.frame), target: after)), [1, 2, 3])
        // Unknown current frame: must move.
        XCTAssertEqual(RibbonStrip<Int>.windowsToMove(current: [:], target: after).count, 3)
    }

    func testAdoptingOrdersByXAndPicksClosestWidth() {
        let s = RibbonStrip<Int>.adopting([
            (id: 7, frame: LRect(x: 600, y: 0, width: 590, height: 500)),
            (id: 5, frame: LRect(x: 0, y: 0, width: 390, height: 500)),
            (id: 6, frame: LRect(x: 300, y: 0, width: 1200, height: 500)),
        ], viewport: vp)
        XCTAssertEqual(s.windowIDs, [5, 6, 7])
        XCTAssertEqual(s.columns.map(\.width), [.third, .full, .half])
        XCTAssertEqual(s.focusedWindow, 5)
    }

    func testViewportChangeReclampsOffset() {
        var s = strip([1, 2, 3])
        XCTAssertEqual(s.offset, 600)
        // Widths are proportional, so a narrower display shrinks the maximum scroll.
        s.viewport = LRect(x: 0, y: 0, width: 100, height: 800)
        XCTAssertEqual(s.offset, 50)
    }

    // MARK: Mouse

    func testDraggingAnEdgeKeepsThatWidthAndShiftsNeighbours() {
        var s = strip([1, 2, 3]) // 600 pt columns, columns 1 and 2 on screen
        let slot = s.layout()[2]!.frame
        let edit = s.userEdit(2, frame: LRect(x: slot.x, y: slot.y, width: 400, height: slot.height))
        XCTAssertEqual(edit, .resized(400))
        s.apply(edit, to: 2)
        XCTAssertEqual(s.columnWidth(1), 400)
        XCTAssertEqual(s.layout()[2]!.frame.width, 400)
        XCTAssertEqual(s.layout()[3]!.frame.x, s.layout()[2]!.frame.maxX)
        XCTAssertEqual(s.focusedWindow, 2)
        // A width shortcut goes back to the fixed widths.
        s.cycleWidth()
        XCTAssertEqual(s.columnWidth(1), s.points(for: .twoThirds))
    }

    func testResizeIsClampedToTheViewport() {
        var s = strip([1])
        s.apply(.resized(5000), to: 1)
        XCTAssertEqual(s.columnWidth(0), 1200)
        s.apply(.resized(10), to: 1)
        XCTAssertEqual(s.columnWidth(0), 100)
    }

    func testDroppingAWindowReordersByItsCentre() {
        var s = strip([1, 2, 3])
        let slot = s.layout()[3]!.frame // x = 600 on screen
        let edit = s.userEdit(3, frame: LRect(x: -100, y: slot.y, width: slot.width, height: slot.height))
        XCTAssertEqual(edit, .moved(toColumn: 1))
        s.apply(edit, to: 3)
        XCTAssertEqual(s.columns.map(\.windows), [[1], [3], [2]])
        XCTAssertEqual(s.focusedWindow, 3)
    }

    func testSmallDragOrHeightChangeIsIgnored() {
        let s = strip([1, 2, 3])
        let slot = s.layout()[3]!.frame
        XCTAssertEqual(s.userEdit(3, frame: LRect(x: slot.x + 50, y: slot.y + 40, width: slot.width, height: slot.height)), .none)
        XCTAssertEqual(s.userEdit(3, frame: LRect(x: slot.x, y: slot.y, width: slot.width, height: 300)), .none)
        XCTAssertEqual(s.userEdit(9, frame: slot), .none)
    }

    func testDraggingOutOfAStackMakesANewColumn() {
        var s = strip([1, 2])
        s.stackIntoLeft()
        XCTAssertEqual(s.columns.map(\.windows), [[1, 2]])
        let slot = s.layout()[2]!.frame
        let edit = s.userEdit(2, frame: LRect(x: 700, y: slot.y, width: slot.width, height: slot.height))
        XCTAssertEqual(edit, .moved(toColumn: 1))
        s.apply(edit, to: 2)
        XCTAssertEqual(s.columns.map(\.windows), [[1], [2]])
    }
}

final class RibbonSettingsTests: XCTestCase {
    func testDefaultsAreUniqueAndDoNotClashWithOtherModules() {
        let ribbon = Array(RibbonSettings.defaultShortcuts.values)
        XCTAssertEqual(Set(ribbon).count, ribbon.count)
        XCTAssertEqual(RibbonSettings.defaultShortcuts.count, RibbonAction.allCases.count)
        var others: [KeyCombo] = Array(SnapSettings.defaultShortcuts.values)
        let capture = CaptureSettings.default
        others += [capture.regionShortcut, capture.textShortcut, capture.pinShortcut].compactMap { $0 }
        others += [ShelfSettings.default.shortcut, MenuBarSettings.default.shortcut].compactMap { $0 }
        others += [SwitcherSettings.default.shortcut, SwitcherSettings.default.reverseShortcut].compactMap { $0 }
        XCTAssertEqual(Set(others).count, others.count, "two modules share a default shortcut")
        XCTAssertTrue(Set(ribbon).isDisjoint(with: Set(others)))
    }

    func testDecodingAndAssign() {
        var s = RibbonSettings.default
        s.assign(RibbonSettings.defaultShortcuts[.focusLeft], to: .expel)
        XCTAssertNil(s.shortcuts[.focusLeft])
        s.gap = 99
        let decoded = SettingsCoding.decode(RibbonSettings.self, from: SettingsCoding.encode(s))
        XCTAssertEqual(decoded.gap, 40)
        XCTAssertEqual(decoded.shortcuts, s.shortcuts)
        XCTAssertTrue(RibbonSettings.default.gestureScroll)
    }

    func testNeighbours() {
        let main = LRect(x: 0, y: 0, width: 1470, height: 956)
        let right = LRect(x: 1470, y: -200, width: 1920, height: 1080)
        let above = LRect(x: 0, y: -1080, width: 1920, height: 1080)
        XCTAssertTrue(RibbonScreens.neighbours(of: main, among: [main, right, above]).right)
        XCTAssertFalse(RibbonScreens.neighbours(of: main, among: [main, right, above]).left)
        XCTAssertTrue(RibbonScreens.neighbours(of: right, among: [main, right]).left)
        XCTAssertFalse(RibbonScreens.neighbours(of: main, among: [main, above]).right)
    }
}
