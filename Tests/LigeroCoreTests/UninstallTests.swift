import XCTest
@testable import LigeroCore

final class UninstallTests: XCTestCase {
    let home = "/Users/example"
    let app = LeftoverFinder.App(bundleID: "com.example.Notely", names: ["Notely"], path: "/Applications/Notely.app")

    func fs(_ tree: [String: [String]]) -> (String) -> [String] {
        { tree[$0] ?? [] }
    }

    func lib(_ s: String) -> String { home + "/Library/" + s }

    func testFindsTypicalLeftovers() {
        let tree: [String: [String]] = [
            lib("Application Support"): ["Notely", "OtherApp", "com.example.Notely"],
            lib("Caches"): ["com.example.Notely", "com.example.Notely.ShipIt", "com.example.NotelyPro"],
            lib("Preferences"): ["com.example.Notely.plist", "com.example.Notely.helper.plist", "com.other.plist"],
            lib("Preferences/ByHost"): ["com.example.Notely.0123-ABCD.plist"],
            lib("Containers"): ["com.example.Notely", "com.example.Notely.extension"],
            lib("Group Containers"): ["ABCDE12345.com.example.Notely", "group.com.example.Notely", "ABCDE12345.com.example.NotelyPro"],
            lib("Saved Application State"): ["com.example.Notely.savedState"],
            lib("LaunchAgents"): ["com.example.Notely.updater.plist", "com.unrelated.agent.plist"],
            lib("Logs"): ["Notely", "notely"],
            lib("HTTPStorages"): ["com.example.Notely", "com.example.Notely.binarycookies"],
            lib("WebKit"): ["com.example.Notely"],
            lib("Cookies"): ["com.example.Notely.binarycookies"],
        ]
        let found = LeftoverFinder.find(app, home: home, list: fs(tree))
        let expected = [
            lib("Application Support/Notely"), lib("Application Support/com.example.Notely"),
            lib("Caches/com.example.Notely"), lib("Caches/com.example.Notely.ShipIt"),
            lib("Preferences/com.example.Notely.plist"), lib("Preferences/com.example.Notely.helper.plist"),
            lib("Preferences/ByHost/com.example.Notely.0123-ABCD.plist"),
            lib("Containers/com.example.Notely"), lib("Containers/com.example.Notely.extension"),
            lib("Group Containers/ABCDE12345.com.example.Notely"), lib("Group Containers/group.com.example.Notely"),
            lib("Saved Application State/com.example.Notely.savedState"),
            lib("LaunchAgents/com.example.Notely.updater.plist"),
            lib("Logs/Notely"), lib("Logs/notely"),
            lib("HTTPStorages/com.example.Notely"), lib("HTTPStorages/com.example.Notely.binarycookies"),
            lib("WebKit/com.example.Notely"), lib("Cookies/com.example.Notely.binarycookies"),
        ].sorted()
        XCTAssertEqual(found, expected)
    }

    func testDoesNotClaimSimilarIdsOrOtherApps() {
        for entry in ["com.example.NotelyPro", "com.example.Notely2", "xcom.example.Notely", "com.example", "OtherApp"] {
            XCTAssertFalse(LeftoverFinder.matches(entry, app: app, folder: "Library/Caches"), entry)
        }
        XCTAssertFalse(LeftoverFinder.matches("ABCDE12345.com.example.NotelyPro", app: app, folder: "Library/Group Containers"))
    }

    func testNamesOnlyInNameFoldersAndNotGeneric() {
        XCTAssertFalse(LeftoverFinder.matches("Notely", app: app, folder: "Library/Preferences"))
        XCTAssertFalse(LeftoverFinder.matches("Notely", app: app, folder: "Library/LaunchAgents"))
        let generic = LeftoverFinder.App(bundleID: "com.x.y", names: ["Google", "Go"], path: "/Applications/Go.app")
        XCTAssertFalse(LeftoverFinder.matches("Google", app: generic, folder: "Library/Application Support"))
        XCTAssertFalse(LeftoverFinder.matches("Go", app: generic, folder: "Library/Application Support"))
    }

    func testRefusesSystemApps() {
        let safari = LeftoverFinder.App(bundleID: "com.apple.Safari", names: ["Safari"], path: "/Applications/Safari.app")
        XCTAssertEqual(LeftoverFinder.refusal(for: safari), .systemApp)
        XCTAssertEqual(LeftoverFinder.find(safari, home: home, list: { _ in ["com.apple.Safari"] }), [])
        XCTAssertEqual(LeftoverFinder.refusal(for: .init(bundleID: " ", names: [], path: "/x.app")), .missingBundleID)
        XCTAssertEqual(LeftoverFinder.refusal(for: .init(bundleID: "a.b", names: [], path: "/System/Applications/X.app")), .systemApp)
        XCTAssertNil(LeftoverFinder.refusal(for: app))
    }

    func testPlanAndTrashListSafety() {
        var items = UninstallPlan.items(app: "/Applications/Notely.app", appSize: 100,
                                        leftovers: [(lib("Caches/com.example.Notely"), 50), (lib("Logs/Notely"), 5)])
        XCTAssertEqual(items.first?.isApp, true)
        XCTAssertEqual(UninstallPlan.totalSelected(items), 155)
        items[2].selected = false
        XCTAssertEqual(UninstallPlan.totalSelected(items), 150)
        items.append(UninstallItem(path: "/etc/hosts", size: 1))
        XCTAssertEqual(UninstallPlan.trashList(items, home: home), ["/Applications/Notely.app", lib("Caches/com.example.Notely")])
    }
}
