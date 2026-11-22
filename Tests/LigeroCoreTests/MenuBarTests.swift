import XCTest
@testable import LigeroCore

final class MenuBarTests: XCTestCase {
    func testLengths() {
        XCTAssertEqual(MenuBarState.collapsed.lengths(alwaysHiddenSection: false).separator, MenuBarState.hiddenLength)
        XCTAssertNil(MenuBarState.collapsed.lengths(alwaysHiddenSection: false).alwaysHidden)
        XCTAssertEqual(MenuBarState.expanded.lengths(alwaysHiddenSection: true).separator, MenuBarState.separatorLength)
        XCTAssertEqual(MenuBarState.expanded.lengths(alwaysHiddenSection: true).alwaysHidden, MenuBarState.hiddenLength)
        XCTAssertEqual(MenuBarState.all.lengths(alwaysHiddenSection: true).alwaysHidden, MenuBarState.separatorLength)
    }

    func testToggle() {
        XCTAssertEqual(MenuBarState.collapsed.toggled(option: false), .expanded)
        XCTAssertEqual(MenuBarState.expanded.toggled(option: false), .collapsed)
        XCTAssertEqual(MenuBarState.all.toggled(option: false), .collapsed)
        XCTAssertEqual(MenuBarState.collapsed.toggled(option: true), .all)
        XCTAssertEqual(MenuBarState.all.toggled(option: true), .collapsed)
    }

    func testSettings() {
        var s = MenuBarSettings.default
        XCTAssertTrue(s.autoHide)
        s.shortcut = nil
        XCTAssertNil(SettingsCoding.decode(MenuBarSettings.self, from: SettingsCoding.encode(s)).shortcut)
    }
}
