import XCTest
@testable import LigeroCore

final class DockPreviewTests: XCTestCase {
    // Bottom Dock on a 1470×956 screen; preview panel 6 pt above an icon.
    let dock = LRect(x: 454, y: 904, width: 562, height: 42)
    let panel = LRect(x: 520, y: 740, width: 300, height: 158)

    func keeps(_ x: Double, _ y: Double, dock: LRect? = nil) -> Bool {
        DockPreviewHover.keepsPreview(mouseX: x, mouseY: y, panel: panel, dock: dock ?? self.dock)
    }

    func testStaysOverPanelDockAndGap() {
        XCTAssertTrue(keeps(670, 800))   // on the panel
        XCTAssertTrue(keeps(670, 925))   // on the Dock icons
        XCTAssertTrue(keeps(670, 901))   // in the 6 pt gap between them
    }

    func testHidesAnywhereElse() {
        XCTAssertFalse(keeps(670, 400))  // moved up into a window
        XCTAssertFalse(keeps(1200, 925)) // beside the Dock
        XCTAssertFalse(keeps(100, 950))
    }

    func testWithoutDockFrameOnlyThePanelCounts() {
        XCTAssertTrue(DockPreviewHover.keepsPreview(mouseX: 670, mouseY: 800, panel: panel, dock: nil))
        XCTAssertFalse(DockPreviewHover.keepsPreview(mouseX: 670, mouseY: 925, panel: panel, dock: nil))
    }
}
