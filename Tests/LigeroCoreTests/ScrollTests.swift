import Foundation
import XCTest
@testable import LigeroCore

final class ScrollTests: XCTestCase {
    let notchDown = ScrollDeltas(lines1: -1, fixed1: -1, point1: -10)
    let fastDown = ScrollDeltas(lines1: -7, fixed1: -7.4, point1: -84)

    func settings(_ change: (inout ScrollSettings) -> Void = { _ in }) -> ScrollSettings {
        var s = ScrollSettings.default
        s.invertVertical = false
        s.invertHorizontal = false
        s.linear = false
        change(&s)
        return s
    }

    func testContinuousEventsAreNeverTouched() {
        let s = settings { $0.invertVertical = true; $0.linear = true }
        XCTAssertNil(ScrollTransform.transform(notchDown, isContinuous: true, settings: s))
    }

    func testNothingEnabledLeavesEventAlone() {
        XCTAssertNil(ScrollTransform.transform(notchDown, isContinuous: false, settings: settings()))
    }

    func testInvertVertical() {
        let out = ScrollTransform.transform(fastDown, isContinuous: false, settings: settings { $0.invertVertical = true })
        XCTAssertEqual(out, ScrollDeltas(lines1: 7, fixed1: 7.4, point1: 84))
    }

    func testInvertHorizontalOnly() {
        let input = ScrollDeltas(lines1: -1, lines2: 2, fixed1: -1, fixed2: 2, point1: -10, point2: 20)
        let out = ScrollTransform.transform(input, isContinuous: false, settings: settings { $0.invertHorizontal = true })
        XCTAssertEqual(out, ScrollDeltas(lines1: -1, lines2: -2, fixed1: -1, fixed2: -2, point1: -10, point2: -20))
    }

    func testLinearIgnoresAcceleration() {
        let s = settings { $0.linear = true; $0.linesPerTick = 3 }
        XCTAssertEqual(ScrollTransform.transform(fastDown, isContinuous: false, settings: s),
                       ScrollDeltas(lines1: -3, fixed1: -3, point1: -30))
        // Slow movement with lines == 0 still uses the fractional sign.
        let slow = ScrollDeltas(lines1: 0, fixed1: 0.2, point1: 2)
        XCTAssertEqual(ScrollTransform.transform(slow, isContinuous: false, settings: s)?.lines1, 3)
    }

    func testLinearAndInvertCombine() {
        let s = settings { $0.linear = true; $0.linesPerTick = 2; $0.invertVertical = true }
        XCTAssertEqual(ScrollTransform.transform(fastDown, isContinuous: false, settings: s),
                       ScrollDeltas(lines1: 2, fixed1: 2, point1: 20))
    }

    func testLinesAreClamped() {
        let s = settings { $0.linear = true; $0.linesPerTick = 99 }
        XCTAssertEqual(ScrollTransform.transform(notchDown, isContinuous: false, settings: s)?.lines1, -10)
    }

    func testSideButtons() {
        let s = settings()
        XCTAssertEqual(MouseButtons.navigation(forButton: 3, settings: s), .back)
        XCTAssertEqual(MouseButtons.navigation(forButton: 4, settings: s), .forward)
        XCTAssertNil(MouseButtons.navigation(forButton: 2, settings: s))
        XCTAssertEqual(MouseButtons.navigation(forButton: 3, settings: settings { $0.swapSideButtons = true }), .forward)
        XCTAssertNil(MouseButtons.navigation(forButton: 3, settings: settings { $0.sideButtonsNavigate = false }))
    }

    func testNeedsEventTap() {
        XCTAssertTrue(ScrollSettings.default.needsEventTap)
        XCTAssertFalse(settings { $0.sideButtonsNavigate = false }.needsEventTap)
    }

    func testDeviceClassification() {
        let mouse = HIDDeviceInfo(product: "MX Master 3S", transport: "Bluetooth Low Energy", builtIn: false, usagePage: 1, usage: 2)
        XCTAssertTrue(mouse.isExternalMouse)
        var t = mouse; t.product = "Magic Trackpad"
        XCTAssertFalse(t.isExternalMouse)
        var internalPad = mouse; internalPad.product = "Apple Internal Keyboard / Trackpad"; internalPad.transport = "SPI"
        XCTAssertFalse(internalPad.isExternalMouse)
        var builtIn = mouse; builtIn.builtIn = true
        XCTAssertFalse(builtIn.isExternalMouse)
        var keyboard = mouse; keyboard.usage = 6
        XCTAssertFalse(keyboard.isExternalMouse)
        let usbNoName = HIDDeviceInfo(product: nil, transport: "USB", builtIn: false, usagePage: 1, usage: 2)
        XCTAssertTrue(usbNoName.isExternalMouse)
    }

    func testSettingsDecodeTolerant() {
        let s = SettingsCoding.decode(ScrollSettings.self, from: Data(#"{"linear": true, "linesPerTick": "x"}"#.utf8))
        XCTAssertTrue(s.linear)
        XCTAssertEqual(s.linesPerTick, ScrollSettings.default.linesPerTick)
        XCTAssertEqual(SettingsCoding.decode(ScrollSettings.self, from: SettingsCoding.encode(s)), s)
    }
}
