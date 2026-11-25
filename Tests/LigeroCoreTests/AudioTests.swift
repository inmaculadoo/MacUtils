import Foundation
import XCTest
@testable import LigeroCore

final class AudioTests: XCTestCase {
    func testTapOnlyWhenNeeded() {
        let neutral = AppAudioSetting()
        XCTAssertFalse(AudioRouting.needsTap(nil, isPlaying: true, defaultOutputUID: "spk"))
        XCTAssertFalse(AudioRouting.needsTap(neutral, isPlaying: true, defaultOutputUID: "spk"))
        XCTAssertFalse(AudioRouting.needsTap(AppAudioSetting(volume: 0.5), isPlaying: false, defaultOutputUID: "spk"))
        XCTAssertTrue(AudioRouting.needsTap(AppAudioSetting(volume: 0.5), isPlaying: true, defaultOutputUID: "spk"))
        XCTAssertTrue(AudioRouting.needsTap(AppAudioSetting(volume: 1.4), isPlaying: true, defaultOutputUID: "spk"))
        XCTAssertTrue(AudioRouting.needsTap(AppAudioSetting(muted: true), isPlaying: true, defaultOutputUID: "spk"))
        XCTAssertTrue(AudioRouting.needsTap(AppAudioSetting(outputUID: "headphones"), isPlaying: true, defaultOutputUID: "spk"))
        // Redirected to the device that is the default anyway: no tap.
        XCTAssertFalse(AudioRouting.needsTap(AppAudioSetting(outputUID: "spk"), isPlaying: true, defaultOutputUID: "spk"))
    }

    func testGainAndOutput() {
        XCTAssertEqual(AudioRouting.gain(for: AppAudioSetting(volume: 3)), 1.5)
        XCTAssertEqual(AudioRouting.gain(for: AppAudioSetting(volume: -1)), 0)
        XCTAssertEqual(AudioRouting.gain(for: AppAudioSetting(volume: 0.8, muted: true)), 0)
        XCTAssertEqual(AudioRouting.outputUID(for: AppAudioSetting(), defaultOutputUID: "spk"), "spk")
        XCTAssertEqual(AudioRouting.outputUID(for: AppAudioSetting(outputUID: "hp"), defaultOutputUID: "spk"), "hp")
    }

    func testSettingsDropNeutralApps() {
        var s = AudioSettings.default
        s.set(AppAudioSetting(volume: 0.5), for: "com.spotify.client")
        s.set(AppAudioSetting(), for: "com.apple.Music")
        XCTAssertEqual(Array(s.apps.keys), ["com.spotify.client"])
        s.set(AppAudioSetting(), for: "com.spotify.client")
        XCTAssertTrue(s.apps.isEmpty)
        s.set(AppAudioSetting(volume: 1.2, outputUID: "hp"), for: "x")
        XCTAssertEqual(SettingsCoding.decode(AudioSettings.self, from: SettingsCoding.encode(s)), s)
    }

    func testApplyGainClipsAndAliases() {
        var buf: [Float] = [0.5, -0.5, 0.9, -0.9]
        buf.withUnsafeMutableBufferPointer { p in
            AudioDSP.apply(gain: 1.5, input: UnsafePointer(p.baseAddress!), output: p.baseAddress!, count: p.count)
        }
        XCTAssertEqual(buf, [0.75, -0.75, 1, -1])
    }

    func testDeinterleave() {
        let input: [Float] = [0.1, -0.1, 0.2, -0.2, 0.3, -0.3]
        var l = [Float](repeating: 9, count: 3)
        var r = [Float](repeating: 9, count: 3)
        input.withUnsafeBufferPointer { i in
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    AudioDSP.deinterleave(gain: 2, input: i.baseAddress!, left: lp.baseAddress!, right: rp.baseAddress!, frames: 3)
                }
            }
        }
        XCTAssertEqual(l, [0.2, 0.4, 0.6].map(Float.init), accuracy: 1e-6)
        XCTAssertEqual(r, [-0.2, -0.4, -0.6].map(Float.init), accuracy: 1e-6)
    }

    func testSilenceAndBits() {
        var b: [Float] = [1, 2, 3]
        b.withUnsafeMutableBufferPointer { AudioDSP.silence($0.baseAddress!, count: 3) }
        XCTAssertEqual(b, [0, 0, 0])
        XCTAssertEqual(AudioDSP.gain(AudioDSP.bits(0.42)), 0.42)
    }
}

private func XCTAssertEqual(_ a: [Float], _ b: [Float], accuracy: Float, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
