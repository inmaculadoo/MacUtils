import XCTest
@testable import LigeroCore

final class NotchHoverTests: XCTestCase {
    // 15-inch notched laptop panel: 1470×956, notch ~186 pt wide, menu bar 33 pt.
    let screen = LRect(x: 0, y: 0, width: 1470, height: 956)
    let left = LRect(x: 0, y: 923, width: 642, height: 33)
    let right = LRect(x: 828, y: 923, width: 642, height: 33)

    func testNotchIsBetweenTheTwoMenuBarAreas() {
        let n = NotchHover.notchRect(screen: screen, topLeftArea: left, topRightArea: right)
        XCTAssertEqual(n, LRect(x: 642, y: 923, width: 186, height: 33))
    }

    func testNoNotchWithoutAuxiliaryAreas() {
        XCTAssertNil(NotchHover.notchRect(screen: screen, topLeftArea: nil, topRightArea: nil))
        XCTAssertNil(NotchHover.notchRect(screen: screen, topLeftArea: left, topRightArea: LRect(x: 642, y: 923, width: 828, height: 33)))
    }

    func testShelfStaysWhileMovingFromNotchToPanel() {
        let notch = LRect(x: 642, y: 923, width: 186, height: 33)
        let panel = LRect(x: 525, y: 785, width: 420, height: 130) // 8 pt under the menu bar
        XCTAssertTrue(NotchHover.keepsShelf(mouseX: 735, mouseY: 940, notch: notch, panel: panel)) // on the notch
        XCTAssertTrue(NotchHover.keepsShelf(mouseX: 735, mouseY: 919, notch: notch, panel: panel)) // the gap
        XCTAssertTrue(NotchHover.keepsShelf(mouseX: 600, mouseY: 850, notch: notch, panel: panel)) // on the panel
        XCTAssertFalse(NotchHover.keepsShelf(mouseX: 735, mouseY: 500, notch: notch, panel: panel))
        XCTAssertFalse(NotchHover.keepsShelf(mouseX: 300, mouseY: 940, notch: notch, panel: panel)) // menu bar, left
    }
}
