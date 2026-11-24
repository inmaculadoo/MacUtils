import XCTest
@testable import LigeroCore

final class SnapEngineTests: XCTestCase {
    // A 1470×956 laptop panel, menu bar 37 pt (notch), no Dock.
    let laptop = ScreenInfo(
        frame: LRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: LRect(x: 0, y: 37, width: 1470, height: 919)
    )
    // External 2560×1440 display to the right, Dock at the bottom (70 pt).
    let external = ScreenInfo(
        frame: LRect(x: 1470, y: -200, width: 2560, height: 1440),
        visibleFrame: LRect(x: 1470, y: -175, width: 2560, height: 1345)
    )
    let window = LRect(x: 100, y: 100, width: 800, height: 600)

    func target(_ a: SnapAction, _ w: LRect? = nil, screens: [ScreenInfo]? = nil, gap: Double = 0, cycle: Bool = true) -> LRect? {
        SnapEngine.target(for: a, window: w ?? window, screens: screens ?? [laptop],
                          options: .init(gap: gap, cycleHalves: cycle))
    }

    func testHalvesUseVisibleFrame() {
        XCTAssertEqual(target(.leftHalf), LRect(x: 0, y: 37, width: 735, height: 919))
        XCTAssertEqual(target(.rightHalf), LRect(x: 735, y: 37, width: 735, height: 919))
        XCTAssertEqual(target(.topHalf), LRect(x: 0, y: 37, width: 1470, height: 460))
        XCTAssertEqual(target(.bottomHalf), LRect(x: 0, y: 497, width: 1470, height: 459))
    }

    func testQuartersTileTheScreen() {
        let q = [SnapAction.topLeft, .topRight, .bottomLeft, .bottomRight].compactMap { target($0) }
        XCTAssertEqual(q.count, 4)
        XCTAssertEqual(q.reduce(0) { $0 + $1.area }, laptop.visibleFrame.area, accuracy: 0.5)
        XCTAssertEqual(q[0].maxX, q[1].minX)
        XCTAssertEqual(q[0].maxY, q[2].minY)
    }

    func testThirdsAndTwoThirds() {
        XCTAssertEqual(target(.firstThird), LRect(x: 0, y: 37, width: 490, height: 919))
        XCTAssertEqual(target(.centerThird), LRect(x: 490, y: 37, width: 490, height: 919))
        XCTAssertEqual(target(.lastThird), LRect(x: 980, y: 37, width: 490, height: 919))
        XCTAssertEqual(target(.firstTwoThirds), LRect(x: 0, y: 37, width: 980, height: 919))
        XCTAssertEqual(target(.lastTwoThirds), LRect(x: 490, y: 37, width: 980, height: 919))
    }

    func testThirdsStackOnPortraitDisplay() {
        let portrait = ScreenInfo(frame: LRect(x: 0, y: 0, width: 1080, height: 1920),
                                  visibleFrame: LRect(x: 0, y: 0, width: 1080, height: 1920))
        XCTAssertEqual(target(.firstThird, screens: [portrait]), LRect(x: 0, y: 0, width: 1080, height: 640))
        XCTAssertEqual(target(.lastThird, screens: [portrait]), LRect(x: 0, y: 1280, width: 1080, height: 640))
    }

    func testMaximizeCenterAndHeight() {
        XCTAssertEqual(target(.maximize), laptop.visibleFrame)
        XCTAssertEqual(target(.center), LRect(x: 335, y: 197, width: 800, height: 600))
        XCTAssertEqual(target(.maximizeHeight), LRect(x: 100, y: 37, width: 800, height: 919))
        // Too big a window is shrunk to fit when centring.
        let huge = LRect(x: 0, y: 0, width: 3000, height: 2000)
        XCTAssertEqual(target(.center, huge), laptop.visibleFrame)
    }

    func testGapSeparatesNeighbours() {
        let l = target(.leftHalf, gap: 10)!
        let r = target(.rightHalf, gap: 10)!
        XCTAssertEqual(l.minX, 10)
        XCTAssertEqual(l.minY, 47)
        XCTAssertEqual(r.maxX, 1460)
        XCTAssertEqual(r.minX - l.maxX, 10, accuracy: 1)
        XCTAssertEqual(target(.maximize, gap: 10), laptop.visibleFrame.insetBy(10))
    }

    func testHalfCycling() {
        let half = target(.leftHalf)!
        let twoThirds = target(.leftHalf, half)!
        XCTAssertEqual(twoThirds.width, 980)
        let third = target(.leftHalf, twoThirds)!
        XCTAssertEqual(third.width, 490)
        XCTAssertEqual(target(.leftHalf, third), half)
        // Right side cycles the same way, anchored to the right edge.
        let r = target(.rightHalf)!
        let r2 = target(.rightHalf, r)!
        XCTAssertEqual(r2, LRect(x: 490, y: 37, width: 980, height: 919))
        // Cycling off: always a half.
        XCTAssertEqual(target(.leftHalf, half, cycle: false), half)
    }

    func testPicksScreenWithLargestOverlap() {
        let both = [laptop, external]
        let mostlyExternal = LRect(x: 1400, y: 100, width: 800, height: 600)
        XCTAssertEqual(SnapEngine.screenIndex(for: mostlyExternal, in: both), 1)
        XCTAssertEqual(target(.leftHalf, mostlyExternal, screens: both),
                       LRect(x: 1470, y: -175, width: 1280, height: 1345))
        // Off every screen: falls back to the primary one.
        let lost = LRect(x: -5000, y: -5000, width: 10, height: 10)
        XCTAssertEqual(SnapEngine.screenIndex(for: lost, in: both), 0)
    }

    func testNextDisplayKeepsRelativeFrame() {
        let both = [external, laptop] // order in the array must not matter
        let leftHalfLaptop = target(.leftHalf)!
        let moved = target(.nextDisplay, leftHalfLaptop, screens: both)!
        XCTAssertEqual(moved, LRect(x: 1470, y: -175, width: 1280, height: 1345))
        // And back, wrapping around.
        let back = target(.nextDisplay, moved, screens: both)!
        XCTAssertEqual(back, leftHalfLaptop)
        XCTAssertEqual(target(.previousDisplay, moved, screens: both), leftHalfLaptop)
    }

    func testNextDisplayWithOneScreenDoesNothing() {
        XCTAssertNil(target(.nextDisplay))
        XCTAssertNil(target(.restore))
        XCTAssertNil(SnapEngine.target(for: .maximize, window: window, screens: []))
    }

    func testMoveClampsIntoDestination() {
        let small = ScreenInfo(frame: LRect(x: 1470, y: 0, width: 800, height: 600),
                               visibleFrame: LRect(x: 1470, y: 0, width: 800, height: 600))
        let max = target(.maximize)!
        let moved = target(.nextDisplay, max, screens: [laptop, small])!
        XCTAssertEqual(moved, small.visibleFrame)
    }

    func testCoordinateConversion() {
        // Secondary screen above the primary one in Cocoa coordinates.
        let cocoa = LRect(x: 0, y: 956, width: 1920, height: 1080)
        let tl = CoordinateSpace.topLeft(fromCocoa: cocoa, primaryHeight: 956)
        XCTAssertEqual(tl, LRect(x: 0, y: -1080, width: 1920, height: 1080))
        XCTAssertEqual(CoordinateSpace.cocoa(fromTopLeft: tl, primaryHeight: 956), cocoa)
    }

    func testIntegralAndIntersection() {
        XCTAssertEqual(LRect(x: 0.4, y: 0.6, width: 10.2, height: 10.2).integral, LRect(x: 0, y: 1, width: 11, height: 10))
        XCTAssertEqual(LRect(x: 0, y: 0, width: 10, height: 10).intersection(LRect(x: 20, y: 0, width: 5, height: 5)), .zero)
    }

    // Safari refuses widths under ~574 pt; a third of 1470 is 490.
    func testSettleKeepsRightAnchoredWindowOnScreen() {
        let t = target(.lastThird)!
        let actual = LRect(x: t.x, y: t.y, width: 574, height: t.height)
        XCTAssertEqual(SnapEngine.settle(actual: actual, target: t, screens: [laptop]),
                       LRect(x: 1470 - 574, y: 37, width: 574, height: 919))
    }

    func testSettleKeepsLeftAnchoredAndFittingWindowsAlone() {
        let first = target(.firstThird)!
        XCTAssertNil(SnapEngine.settle(actual: LRect(x: 0, y: 37, width: 574, height: 919), target: first, screens: [laptop]))
        let middle = target(.centerThird)!
        XCTAssertNil(SnapEngine.settle(actual: LRect(x: middle.x, y: 37, width: 574, height: 919), target: middle, screens: [laptop]))
        XCTAssertNil(SnapEngine.settle(actual: first, target: first, screens: [laptop]))
    }

    func testSettlePullsBackOverflowAndRespectsGap() {
        let t = target(.bottomRight, gap: 10)!
        let actual = LRect(x: t.x, y: t.y, width: 900, height: 600)
        let s = SnapEngine.settle(actual: actual, target: t, screens: [laptop], gap: 10)!
        XCTAssertEqual(s.maxX, 1470 - 10)
        XCTAssertEqual(s.maxY, 956 - 10)
    }
}

final class RestoreHistoryTests: XCTestCase {
    let a = LRect(x: 10, y: 10, width: 500, height: 400)
    let b = LRect(x: 0, y: 0, width: 735, height: 919)
    let c = LRect(x: 735, y: 0, width: 735, height: 919)

    func testRestoresFirstFrameAcrossSnaps() {
        var h = RestoreHistory<Int>()
        h.record(1, current: a, applied: b)
        h.record(1, current: b, applied: c)
        XCTAssertEqual(h.takeOriginal(1), a)
        XCTAssertNil(h.takeOriginal(1))
    }

    func testDraggingASnappedWindowToAnotherEdgeKeepsTheOriginal() {
        var h = RestoreHistory<Int>()
        h.record(1, current: a, applied: b)
        // The drag is noticed once the window moved a little: same size as b.
        let dragged = LRect(x: 40, y: 20, width: 735, height: 919)
        let current = h.appliedBeforeDrag(1, dragged: dragged) ?? dragged
        h.record(1, current: current, applied: c)
        XCTAssertEqual(h.takeOriginal(1), a)
        // A window resized by hand since is not part of the chain.
        h.record(1, current: a, applied: b)
        XCTAssertNil(h.appliedBeforeDrag(1, dragged: a))
    }

    func testManualMoveResetsOriginal() {
        var h = RestoreHistory<Int>()
        h.record(1, current: a, applied: b)
        let dragged = LRect(x: 300, y: 300, width: 600, height: 500)
        h.record(1, current: dragged, applied: c)
        XCTAssertEqual(h.takeOriginal(1), dragged)
    }

    func testCapacityEvictsOldest() {
        var h = RestoreHistory<Int>(capacity: 2)
        h.record(1, current: a, applied: b)
        h.record(2, current: a, applied: b)
        h.record(3, current: a, applied: b)
        XCTAssertEqual(h.count, 2)
        XCTAssertNil(h.takeOriginal(1))
        XCTAssertNotNil(h.takeOriginal(3))
    }

    func testLastTargetWhileWindowStaysPut() {
        var h = RestoreHistory<Int>()
        let rounded = LRect(x: 0, y: 37, width: 734, height: 915)
        h.record(1, current: a, applied: rounded, target: b)
        XCTAssertEqual(h.lastTarget(1, current: rounded), b)
        XCTAssertNil(h.lastTarget(1, current: c))
        XCTAssertNil(h.lastTarget(2, current: rounded))
        h.record(1, current: rounded, applied: c)
        XCTAssertEqual(h.lastTarget(1, current: c), c)
        XCTAssertEqual(h.takeOriginal(1), a)
    }
}
