import XCTest
@testable import LigeroCore

final class AwakeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func testTimedSessionEndsOnItsOwn() {
        let s = AwakeSession(duration: .hour1, now: now)
        XCTAssertTrue(s.isActive(at: now.addingTimeInterval(59 * 60)))
        XCTAssertFalse(s.isActive(at: now.addingTimeInterval(60 * 60)))
        XCTAssertTrue(AwakeSession(duration: .indefinitely, now: now).isActive(at: .distantFuture))
    }

    func testSessionWinsOverTriggerApps() {
        let s = AwakeSession(duration: .minutes30, now: now)
        let r = AwakePlanner.reason(session: s, triggers: ["com.apple.Safari"], running: ["com.apple.Safari"], now: now)
        XCTAssertEqual(r, .session(s))
    }

    func testTriggerAppsKeepAwakeOnlyWhileOpen() {
        let triggers = ["org.videolan.vlc", "com.apple.Safari"]
        XCTAssertEqual(AwakePlanner.reason(session: nil, triggers: triggers, running: ["com.apple.Safari", "x"], now: now),
                       .apps(["com.apple.Safari"]))
        XCTAssertEqual(AwakePlanner.reason(session: nil, triggers: triggers, running: ["x"], now: now), .off)
        // An expired session falls back to the trigger apps.
        let old = AwakeSession(duration: .minutes30, now: now.addingTimeInterval(-3600))
        XCTAssertEqual(AwakePlanner.reason(session: old, triggers: [], running: [], now: now), .off)
    }

    func testSettingsRoundTripAndToggle() throws {
        var s = AwakeSettings.default
        s.toggleTrigger("a")
        s.toggleTrigger("b")
        s.toggleTrigger("a")
        XCTAssertEqual(s.triggerApps, ["b"])
        s.shortcut = nil
        let decoded = try JSONDecoder().decode(AwakeSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
        XCTAssertEqual(try JSONDecoder().decode(AwakeSettings.self, from: Data("{}".utf8)), .default)
    }
}
