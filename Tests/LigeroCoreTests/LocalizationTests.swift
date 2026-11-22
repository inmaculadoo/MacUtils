import Foundation
import XCTest
@testable import LigeroCore

/// Keeps the two Localizable.strings in sync and makes sure every key the app
/// uses exists (CLAUDE.md, rule 9). Reads the repository files directly, so it
/// runs on Linux CI without building the AppKit target.
final class LocalizationTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // LigeroCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
    static let languages = ["en", "es"]

    func table(_ lang: String) throws -> [String: String] {
        let url = Self.root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        return try StringsFile.parse(text)
    }

    func testBothLanguagesHaveTheSameKeys() throws {
        let en = try table("en")
        let es = try table("es")
        XCTAssertFalse(en.isEmpty)
        XCTAssertEqual(Set(en.keys).subtracting(es.keys).sorted(), [], "missing in es.lproj")
        XCTAssertEqual(Set(es.keys).subtracting(en.keys).sorted(), [], "missing in en.lproj")
    }

    func testFormatSpecifiersMatch() throws {
        let en = try table("en")
        let es = try table("es")
        for (key, value) in en {
            guard let other = es[key] else { continue }
            XCTAssertEqual(StringsFile.formatSpecifiers(in: value), StringsFile.formatSpecifiers(in: other),
                           "format specifiers differ for \(key)")
        }
    }

    func testNoEmptyValues() throws {
        for lang in Self.languages {
            for (key, value) in try table(lang) {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(lang): empty \(key)")
            }
        }
    }

    /// Keys built at run time from LigeroCore enums.
    func testDynamicKeysExist() throws {
        var keys: [String] = []
        keys += SnapAction.allCases.map(\.localizationKey)
        keys += Permission.allCases.flatMap { [$0.titleKey, $0.explanationKey] }
        keys += LanguageChoice.allCases.map(\.titleKey)
        keys += DynamicKeys.all
        for lang in Self.languages {
            let t = try table(lang)
            for k in keys { XCTAssertNotNil(t[k], "\(lang): missing \(k)") }
        }
    }

    /// Every literal key passed to L(...), or given as a titleKey/summaryKey,
    /// in Sources/Ligero must exist in both tables.
    func testKeysUsedInSourcesExist() throws {
        let used = try Self.keysUsedInAppSources()
        XCTAssertFalse(used.isEmpty, "no L(\"…\") calls found; did the source layout change?")
        for lang in Self.languages {
            let t = try table(lang)
            for k in used.sorted() { XCTAssertNotNil(t[k], "\(lang): missing \(k)") }
        }
    }

    /// No visible text written by hand: SwiftUI string literals and AppKit
    /// titles must go through L(...).
    func testNoHardCodedUserFacingStrings() throws {
        let patterns = [
            #"Text\("[^"]"#, #"Button\("[^"]"#, #"Toggle\("[^"]"#, #"Label\("[^"]"#,
            #"Section\("[^"]"#, #"Picker\("[^"]"#, #"title: "[^"]"#, #"withTitle: "[^"]"#,
            #"messageText = "[^"]"#, #"informativeText = "[^"]"#, #"toolTip = "[^"]"#,
        ]
        let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
        for (file, text) in try Self.appSources() {
            for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let s = String(line)
                for r in regexes where r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil {
                    XCTFail("\(file): hard-coded string: \(s.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
    }

    static func appSources() throws -> [(String, String)] {
        let dir = root.appendingPathComponent("Sources/Ligero")
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in e where url.pathExtension == "swift" {
            out.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return out
    }

    static func keysUsedInAppSources() throws -> Set<String> {
        let r = try NSRegularExpression(pattern: #"(?:\bL\(|titleKey: |summaryKey: |Key: )"([a-zA-Z0-9_.]+)""#)
        var keys = Set<String>()
        for (_, text) in try appSources() {
            for m in r.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(m.range(at: 1), in: text) { keys.insert(String(text[range])) }
            }
        }
        return keys
    }
}
