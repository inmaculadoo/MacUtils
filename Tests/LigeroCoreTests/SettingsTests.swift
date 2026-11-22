import Foundation
import XCTest
@testable import LigeroCore

final class SettingsTests: XCTestCase {
    func testRoundTrip() {
        var s = SnapSettings.default
        s.gap = 8
        s.cycleHalves = false
        let data = SettingsCoding.encode(s)
        XCTAssertEqual(SettingsCoding.decode(SnapSettings.self, from: data), s)
    }

    func testMissingOrCorruptDataGivesDefaults() {
        XCTAssertEqual(SettingsCoding.decode(SnapSettings.self, from: nil), .default)
        XCTAssertEqual(SettingsCoding.decode(SnapSettings.self, from: Data("garbage".utf8)), .default)
        XCTAssertEqual(SettingsCoding.decode(AppSettings.self, from: Data("{}".utf8)), .default)
    }

    func testPartialAndUnknownFieldsAreTolerated() {
        let json = #"{"gap": 12, "shortcuts": {"leftHalf": {"keyCode": 123, "modifiers": 6144}, "removedAction": {"keyCode": 1, "modifiers": 256}}, "future": true}"#
        let s = SettingsCoding.decode(SnapSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.gap, 12)
        XCTAssertEqual(s.cycleHalves, true)
        XCTAssertEqual(s.shortcuts, [.leftHalf: KeyCombo(keyCode: 123, modifiers: [.control, .option])])
    }

    func testWrongTypeFallsBackPerField() {
        let json = #"{"gap": "wide", "cycleHalves": false}"#
        let s = SettingsCoding.decode(SnapSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.gap, 0)
        XCTAssertEqual(s.cycleHalves, false)
    }

    func testDefaultShortcutsAreUniqueAndValid() {
        let combos = Array(SnapSettings.defaultShortcuts.values)
        XCTAssertEqual(Set(combos).count, combos.count)
        XCTAssertEqual(SnapSettings.defaultShortcuts.count, SnapAction.allCases.count)
        XCTAssertTrue(combos.allSatisfy(\.isValidGlobalShortcut))
    }

    func testAssignRemovesDuplicates() {
        var s = SnapSettings.default
        let combo = SnapSettings.defaultShortcuts[.leftHalf]!
        s.assign(combo, to: .maximize)
        XCTAssertNil(s.shortcuts[.leftHalf])
        XCTAssertEqual(s.shortcuts[.maximize], combo)
        s.assign(nil, to: .maximize)
        XCTAssertNil(s.shortcuts[.maximize])
    }

    func testLanguageChoice() {
        XCTAssertEqual(LanguageChoice(appleLanguages: nil), .system)
        XCTAssertEqual(LanguageChoice(appleLanguages: ["es-ES"]), .es)
        XCTAssertEqual(LanguageChoice(appleLanguages: ["en"]), .en)
        XCTAssertEqual(LanguageChoice(appleLanguages: ["fr"]), .system)
        XCTAssertNil(LanguageChoice.system.appleLanguages)
        XCTAssertEqual(LanguageChoice.es.appleLanguages, ["es"])
    }

    func testKeyComboDescription() {
        XCTAssertEqual(KeyCombo(keyCode: KeyCode.leftArrow, modifiers: [.option, .control]).description, "⌃⌥←")
        XCTAssertEqual(KeyCombo(keyCode: KeyCode.k, modifiers: [.command, .shift, .option, .control]).description, "⌃⌥⇧⌘K")
        XCTAssertFalse(KeyCombo(keyCode: KeyCode.a, modifiers: [.shift]).isValidGlobalShortcut)
        XCTAssertTrue(KeyCombo(keyCode: 0x7A, modifiers: []).isValidGlobalShortcut)
        // Non-modifier bits are dropped.
        XCTAssertEqual(KeyCombo(keyCode: 1, modifiers: .init(rawValue: 0xFFFF)).modifiers, .all)
    }
}
