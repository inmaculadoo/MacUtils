import XCTest
@testable import LigeroCore

final class SnapZonesTests: XCTestCase {
    // Notched laptop panel: 1470×956, menu bar 33 pt; external display to its right.
    let air = ScreenInfo(frame: LRect(x: 0, y: 0, width: 1470, height: 956),
                         visibleFrame: LRect(x: 0, y: 33, width: 1470, height: 923))
    let external = ScreenInfo(frame: LRect(x: 1470, y: 0, width: 1920, height: 1080),
                              visibleFrame: LRect(x: 1470, y: 25, width: 1920, height: 1055))

    func action(_ x: Double, _ y: Double, _ screens: [ScreenInfo]? = nil) -> SnapAction? {
        SnapZones.zone(atX: x, y: y, screens: screens ?? [air])?.action
    }

    func testEdgesGiveHalvesAndMaximise() {
        XCTAssertEqual(action(0, 500), .leftHalf)
        XCTAssertEqual(action(1469, 500), .rightHalf)
        XCTAssertEqual(action(700, 0), .maximize)
    }

    func testCornersGiveQuarters() {
        XCTAssertEqual(action(0, 20), .topLeft)
        XCTAssertEqual(action(30, 0), .topLeft)
        XCTAssertEqual(action(1469, 940), .bottomRight)
        XCTAssertEqual(action(20, 955), .bottomLeft)
        XCTAssertEqual(action(1450, 0), .topRight)
    }

    func testMiddleOfTheScreenAndBottomMiddleAreNotZones() {
        XCTAssertNil(action(700, 500))
        XCTAssertNil(action(700, 955))
        XCTAssertNil(action(20, 500)) // 20 pt from the edge: not yet
    }

    func testSharedEdgeBetweenDisplaysIsNotAZone() {
        let both = [air, external]
        XCTAssertNil(action(1469, 500, both))   // right edge of the Air touches the external one
        XCTAssertNil(action(1470, 500, both))   // left edge of the external one
        XCTAssertEqual(action(0, 500, both), .leftHalf)
        XCTAssertEqual(SnapZones.zone(atX: 3389, y: 500, screens: both), .init(action: .rightHalf, screen: 1))
    }

    func testTargetIsOnTheZonesDisplay() {
        let both = [air, external]
        let left = SnapZones.target(for: .init(action: .leftHalf, screen: 0), screens: both, options: .init())
        XCTAssertEqual(left, LRect(x: 0, y: 33, width: 735, height: 923))
        let max = SnapZones.target(for: .init(action: .maximize, screen: 1), screens: both, options: .init())
        XCTAssertEqual(max, external.visibleFrame)
    }
}
