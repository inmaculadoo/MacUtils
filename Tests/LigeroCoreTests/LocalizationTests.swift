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

    /// Every .strings table (Localizable, InfoPlist…) exists in both languages
    /// with the same keys, and InfoPlist.strings covers the usage strings of
    /// Info.plist.
    func testAllTablesMatch() throws {
        let fm = FileManager.default
        let enDir = Self.root.appendingPathComponent("Resources/en.lproj")
        let esDir = Self.root.appendingPathComponent("Resources/es.lproj")
        let enFiles = try fm.contentsOfDirectory(atPath: enDir.path).filter { $0.hasSuffix(".strings") }.sorted()
        let esFiles = try fm.contentsOfDirectory(atPath: esDir.path).filter { $0.hasSuffix(".strings") }.sorted()
        XCTAssertEqual(enFiles, esFiles)
        for file in enFiles {
            let en = try StringsFile.parse(String(contentsOf: enDir.appendingPathComponent(file), encoding: .utf8))
            let es = try StringsFile.parse(String(contentsOf: esDir.appendingPathComponent(file), encoding: .utf8))
            XCTAssertEqual(Set(en.keys), Set(es.keys), file)
        }
        let plist = try String(contentsOf: Self.root.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        let usage = try NSRegularExpression(pattern: #"<key>(NS[A-Za-z]+UsageDescription)</key>"#)
        let keys = usage.matches(in: plist, range: NSRange(plist.startIndex..., in: plist)).compactMap {
            Range($0.range(at: 1), in: plist).map { String(plist[$0]) }
        }
        if !keys.isEmpty {
            for lang in Self.languages {
                let url = Self.root.appendingPathComponent("Resources/\(lang).lproj/InfoPlist.strings")
                let t = try StringsFile.parse(String(contentsOf: url, encoding: .utf8))
                for k in keys { XCTAssertNotNil(t[k], "\(lang) InfoPlist.strings: missing \(k)") }
            }
        }
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
        // Literal keys passed to L(...) or stored as title/summary keys, plus
        // any string literal that looks like a key of one of our namespaces
        // (keys handed to helper functions before reaching L).
        let patterns = [
            #"(?:\bL\(|titleKey: |summaryKey: |Key: )"([a-zA-Z0-9_.]+)""#,
            #""((?:app|menu|settings|permission|module|snap|downloads|shelf|uninstall|capture|monitor|switcher|dock|menubar|audio|ribbon)\.[a-zA-Z0-9_.]*[a-zA-Z0-9_])""#,
        ]
        // Contexts where such a literal is not a localization key.
        let notKeys = ["systemImage:", "systemName:", "symbol:", "id:", "static let", "autosaveName"]
        var keys = Set<String>()
        for pattern in patterns {
            let r = try NSRegularExpression(pattern: pattern)
            for (_, text) in try appSources() {
                for m in r.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(m.range(at: 1), in: text) else { continue }
                    let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
                    let before = text[lineStart..<range.lowerBound]
                    if notKeys.contains(where: { before.contains($0) }) { continue }
                    keys.insert(String(text[range]))
                }
            }
        }
        return keys
    }
}
