import XCTest
@testable import LigeroCore

final class CaptureTests: XCTestCase {
    func testSelectionNormalisesDirection() {
        XCTAssertEqual(CaptureGeometry.selection(fromX: 100, y: 50, toX: 20, y: 10), LRect(x: 20, y: 10, width: 80, height: 40))
        XCTAssertNil(CaptureGeometry.selection(fromX: 10, y: 10, toX: 12, y: 40))
    }

    func testSourceRectIsLocalAndTopLeft() {
        // Primary display 1470×956 at the origin (Cocoa coordinates).
        let primary = LRect(x: 0, y: 0, width: 1470, height: 956)
        let sel = LRect(x: 100, y: 800, width: 200, height: 100)
        XCTAssertEqual(CaptureGeometry.sourceRect(selection: sel, displayFrame: primary),
                       LRect(x: 100, y: 56, width: 200, height: 100))
        // External display to the right, lower than the primary.
        let ext = LRect(x: 1470, y: -200, width: 1920, height: 1080)
        let sel2 = LRect(x: 1500, y: 0, width: 100, height: 100)
        XCTAssertEqual(CaptureGeometry.sourceRect(selection: sel2, displayFrame: ext),
                       LRect(x: 30, y: 780, width: 100, height: 100))
        // Clipped at the display edge; nil when outside.
        let across = LRect(x: 1400, y: 0, width: 200, height: 50)
        XCTAssertEqual(CaptureGeometry.sourceRect(selection: across, displayFrame: primary)?.width, 70)
        XCTAssertNil(CaptureGeometry.sourceRect(selection: LRect(x: 5000, y: 0, width: 10, height: 10), displayFrame: primary))
    }

    func testPixelAndPinSizes() {
        let px = CaptureGeometry.pixelSize(of: LRect(x: 0, y: 0, width: 100.4, height: 50), scale: 2)
        XCTAssertEqual(px.width, 201)
        XCTAssertEqual(px.height, 100)
        let pin = CaptureGeometry.pinSize(width: 1280, height: 640)
        XCTAssertEqual(pin.0, 640)
        XCTAssertEqual(pin.1, 320)
        XCTAssertEqual(CaptureGeometry.pinSize(width: 300, height: 200).0, 300)
    }

    func testOCRReadingOrder() {
        // Two words on the top line (given right-to-left), then a line, then a
        // paragraph far below.
        let boxes = [
            TextBox("mundo", x: 0.3, y: 0.90, width: 0.2, height: 0.05),
            TextBox("Hola", x: 0.05, y: 0.905, width: 0.2, height: 0.05),
            TextBox("segunda línea", x: 0.05, y: 0.83, width: 0.5, height: 0.05),
            TextBox("Otro párrafo", x: 0.05, y: 0.50, width: 0.5, height: 0.05),
            TextBox("  ", x: 0, y: 0, width: 0.1, height: 0.05),
        ]
        XCTAssertEqual(OCRText.assemble(boxes), "Hola mundo\nsegunda línea\n\nOtro párrafo")
        XCTAssertEqual(OCRText.assemble([]), "")
    }

    func testSettingsDefaultsAndClearedShortcut() {
        let d = CaptureSettings.default
        let all = [d.textShortcut, d.pinShortcut].compactMap { $0 }
        XCTAssertEqual(Set(all).count, 2)
        XCTAssertTrue(all.allSatisfy(\.isValidGlobalShortcut))
        // Must not collide with Snap's defaults.
        XCTAssertTrue(Set(all).isDisjoint(with: Set(SnapSettings.defaultShortcuts.values)))
        var s = d
        s.textShortcut = nil
        XCTAssertNil(SettingsCoding.decode(CaptureSettings.self, from: SettingsCoding.encode(s)).textShortcut)
    }
}
