import Foundation
import XCTest
@testable import LigeroCore

final class MonitorTests: XCTestCase {
    func testCPUUsage() {
        let a = [CPUTicks(user: 100, system: 50, idle: 850, nice: 0), CPUTicks(user: 0, system: 0, idle: 1000, nice: 0)]
        let b = [CPUTicks(user: 150, system: 100, idle: 850, nice: 0), CPUTicks(user: 0, system: 0, idle: 1100, nice: 0)]
        let r = CPUUsage.between(a, b)
        XCTAssertEqual(r.perCore[0], 1.0, accuracy: 1e-9)
        XCTAssertEqual(r.perCore[1], 0.0, accuracy: 1e-9)
        XCTAssertEqual(r.total, 0.5, accuracy: 1e-9)
        XCTAssertEqual(CPUUsage.between(a, []).perCore, [])
    }

    func testCPUCounterWrap() {
        let a = [CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)]
        let b = [CPUTicks(user: 10, system: 0, idle: 20, nice: 0)]
        XCTAssertEqual(CPUUsage.between(a, b).total, 20.0 / 40.0, accuracy: 1e-9)
    }

    func testMemory() {
        let m = MemoryStats.from(pageSize: 16384, total: 16 << 30, internalPages: 400_000, purgeablePages: 50_000,
                                 wiredPages: 100_000, compressedPages: 50_000, pressureLevel: 2)
        XCTAssertEqual(m.used, UInt64(500_000) * 16384)
        XCTAssertEqual(m.pressure, .warning)
        XCTAssertEqual(m.usedFraction, Double(500_000 * 16384) / Double(16 << 30), accuracy: 1e-9)
        let silly = MemoryStats.from(pageSize: 16384, total: 1000, internalPages: 1, purgeablePages: 5,
                                     wiredPages: 1, compressedPages: 0, pressureLevel: 9)
        XCTAssertEqual(silly.used, 1000)
        XCTAssertEqual(silly.pressure, .normal)
    }

    func testBatteryOnBattery() {
        let d: [String: Any] = [
            "CurrentCapacity": 76, "MaxCapacity": 100, "IsCharging": false, "ExternalConnected": false,
            "CycleCount": 123, "AppleRawMaxCapacity": 4300, "DesignCapacity": 4500,
            "Voltage": 12_000, "InstantAmperage": UInt64(bitPattern: -500), "AvgTimeToEmpty": 245,
        ]
        let b = BatteryInfo.parse(d)!
        XCTAssertEqual(b.percent, 76)
        XCTAssertEqual(b.cycleCount, 123)
        XCTAssertEqual(b.health, 96)
        XCTAssertEqual(b.watts!, -6.0, accuracy: 1e-9)
        XCTAssertEqual(b.minutesRemaining, 245)
        XCTAssertEqual(BatteryInfo.hoursMinutes(245), "4:05")
    }

    func testBatteryHealthFromNestedBatteryData() {
        // macOS 27: capacities only inside BatteryData; nominal wins over raw.
        let d: [String: Any] = [
            "CurrentCapacity": 74, "MaxCapacity": 100,
            "BatteryData": ["AppleRawMaxCapacity": 4452, "NominalChargeCapacity": 4579, "DesignCapacity": 4629],
        ]
        XCTAssertEqual(BatteryInfo.parse(d)!.health, 99)
        // A new battery can report more than its design capacity.
        let fresh: [String: Any] = ["CurrentCapacity": 50, "NominalChargeCapacity": 4700, "DesignCapacity": 4629]
        XCTAssertEqual(BatteryInfo.parse(fresh)!.health, 100)
    }

    func testBatteryChargingAndCalculating() {
        let d: [String: Any] = [
            "CurrentCapacity": 2000, "MaxCapacity": 4000, "IsCharging": true, "ExternalConnected": true,
            "Voltage": 12_500, "Amperage": 2000, "AvgTimeToFull": 65535,
        ]
        let b = BatteryInfo.parse(d)!
        XCTAssertEqual(b.percent, 50)
        XCTAssertTrue(b.isCharging)
        XCTAssertEqual(b.watts!, 25, accuracy: 1e-9)
        XCTAssertNil(b.minutesRemaining)
        XCTAssertNil(b.health)
        XCTAssertNil(BatteryInfo.parse([:]))
        // Plugged in but not charging (held at 80 %): no time shown.
        let held = BatteryInfo.parse(["CurrentCapacity": 80, "IsCharging": false, "ExternalConnected": true, "AvgTimeToEmpty": 300])!
        XCTAssertNil(held.minutesRemaining)
    }

    func testNetworkRates() {
        let old = ["en0": NetworkCounters(received: 1000, sent: 500), "lo0": NetworkCounters(received: 0, sent: 0),
                   "utun3": NetworkCounters(received: 0, sent: 0)]
        let new = ["en0": NetworkCounters(received: 3000, sent: 1500), "lo0": NetworkCounters(received: 9999, sent: 9999),
                   "utun3": NetworkCounters(received: 5000, sent: 5000), "en1": NetworkCounters(received: 10, sent: 10)]
        let r = NetworkCounters.rate(from: old, to: new, seconds: 2)
        XCTAssertEqual(r.down, 1000)
        XCTAssertEqual(r.up, 500)
        XCTAssertEqual(NetworkCounters.total(new), NetworkCounters(received: 3010, sent: 1510))
    }

    func testNetworkWrap() {
        let old = ["en0": NetworkCounters(received: UInt64(UInt32.max) - 99, sent: 0)]
        let new = ["en0": NetworkCounters(received: 100, sent: 0)]
        XCTAssertEqual(NetworkCounters.rate(from: old, to: new, seconds: 1).down, 200)
        // A reset of a 64-bit counter is not a huge spike.
        let big = ["en0": NetworkCounters(received: 1 << 40, sent: 0)]
        XCTAssertEqual(NetworkCounters.rate(from: big, to: new, seconds: 1).down, 0)
    }

    func testEnergyRanking() {
        let old = [ProcessEnergySample(pid: 1, name: "a", energy: 1_000_000_000),
                   ProcessEnergySample(pid: 2, name: "b", energy: 0),
                   ProcessEnergySample(pid: 3, name: "c", energy: 5_000_000_000)]
        let new = [ProcessEnergySample(pid: 1, name: "a", energy: 3_000_000_000),
                   ProcessEnergySample(pid: 2, name: "b", energy: 4_000_000_000),
                   ProcessEnergySample(pid: 3, name: "c", energy: 100), // restarted
                   ProcessEnergySample(pid: 4, name: "new", energy: 9_000_000_000)]
        let top = EnergyRanking.top(old, new, seconds: 2)
        XCTAssertEqual(top.map(\.name), ["b", "a"])
        XCTAssertEqual(top[0].watts, 2, accuracy: 1e-9)
        XCTAssertEqual(EnergyRanking.top(old, new, seconds: 2, limit: 1).count, 1)
    }

    func testSettings() {
        XCTAssertFalse(MonitorSettings.default.menuBarReading)
        var s = MonitorSettings.default
        s.menuBarInterval = 2
        XCTAssertEqual(s.clampedInterval, 10)
    }
}
