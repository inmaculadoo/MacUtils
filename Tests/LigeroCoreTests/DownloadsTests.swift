import Foundation
import XCTest
@testable import LigeroCore

final class DownloadsTests: XCTestCase {
    let names: [DownloadCategory: String] = [
        .images: "Imágenes", .documents: "Documentos", .pdfs: "PDFs", .video: "Vídeo",
        .audio: "Audio", .archives: "Comprimidos", .installers: "Instaladores", .code: "Código",
    ]
    var settings: DownloadsSettings {
        var s = DownloadsSettings.default
        s.folderNames = names
        s.previewAccepted = true
        return s
    }

    func testClassificationByExtension() {
        XCTAssertEqual(DownloadCategory.forExtension("JPG"), .images)
        XCTAssertEqual(DownloadCategory.forExtension("pdf"), .pdfs)
        XCTAssertEqual(DownloadCategory.forExtension("dmg"), .installers)
        XCTAssertEqual(DownloadCategory.forExtension("tgz"), .archives)
        XCTAssertEqual(DownloadCategory.forExtension("swift"), .code)
        XCTAssertEqual(DownloadCategory.forExtension("flac"), .audio)
        XCTAssertNil(DownloadCategory.forExtension("weird"))
    }

    func testEveryExtensionHasOneCategory() {
        XCTAssertGreaterThan(DownloadCategory.byExtension.count, 100)
        XCTAssertEqual(Set(DownloadCategory.byExtension.values), Set(DownloadCategory.allCases))
    }

    func testIgnoresPartialHiddenFoldersAndPackages() {
        let ignored = [
            DownloadEntry(name: "movie.mp4.crdownload"), DownloadEntry(name: "a.zip.part"),
            DownloadEntry(name: "b.pdf.download"), DownloadEntry(name: ".DS_Store"),
            DownloadEntry(name: ".hidden.png"), DownloadEntry(name: "PDFs", isDirectory: true),
            DownloadEntry(name: "Some.app", isDirectory: true, isPackage: true),
            DownloadEntry(name: "~$doc.docx"), DownloadEntry(name: "x.opdownload"),
        ]
        for e in ignored { XCTAssertTrue(DownloadsPlanner.shouldIgnore(e), e.name) }
        XCTAssertFalse(DownloadsPlanner.shouldIgnore(DownloadEntry(name: "report.pdf")))
        XCTAssertTrue(DownloadsPlanner.plan(ignored, settings: settings, folderNames: names).isEmpty)
    }

    func testPlanSortsKnownFilesAndLeavesTheRest() {
        let entries = ["foto.HEIC", "factura.pdf", "notes.txt", "song.mp3", "setup.dmg", "code.py", "mystery.xyz", "noext"]
            .map { DownloadEntry(name: $0) }
        let plan = DownloadsPlanner.plan(entries, settings: settings, folderNames: names)
        let map = Dictionary(uniqueKeysWithValues: plan.map { ($0.source, $0.destination) })
        XCTAssertEqual(map["foto.HEIC"], "Imágenes/foto.HEIC")
        XCTAssertEqual(map["factura.pdf"], "PDFs/factura.pdf")
        XCTAssertEqual(map["notes.txt"], "Documentos/notes.txt")
        XCTAssertEqual(map["song.mp3"], "Audio/song.mp3")
        XCTAssertEqual(map["setup.dmg"], "Instaladores/setup.dmg")
        XCTAssertEqual(map["code.py"], "Código/code.py")
        XCTAssertNil(map["mystery.xyz"])
        XCTAssertNil(map["noext"])
    }

    func testFallbackCategoryAndDisabledCategories() {
        var s = settings
        s.enabledCategories.remove(.pdfs)
        let entries = [DownloadEntry(name: "a.pdf"), DownloadEntry(name: "scan.xyz")]
        let plan = DownloadsPlanner.plan(entries, settings: s, folderNames: names) { $0.name == "scan.xyz" ? .images : nil }
        XCTAssertEqual(plan.map(\.destination), ["Imágenes/scan.xyz"])
    }

    func testMissingFolderNameSkipsCategory() {
        var n = names
        n[.pdfs] = nil
        XCTAssertTrue(DownloadsPlanner.plan([DownloadEntry(name: "a.pdf")], settings: settings, folderNames: n).isEmpty)
        n[.pdfs] = "../evil"
        XCTAssertTrue(DownloadsPlanner.plan([DownloadEntry(name: "a.pdf")], settings: settings, folderNames: n).isEmpty)
    }

    func testNameCollisionsNeverOverwrite() {
        let existing = ["PDFs": Set(["a.pdf", "a 2.pdf"])]
        let entries = [DownloadEntry(name: "a.pdf")]
        let plan = DownloadsPlanner.plan(entries, settings: settings, folderNames: names, existing: existing)
        XCTAssertEqual(plan.first?.destination, "PDFs/a 3.pdf")
        XCTAssertEqual(DownloadsPlanner.uniqueName("backup.tar.gz", taken: ["backup.tar.gz"]), "backup 2.tar.gz")
        XCTAssertEqual(DownloadsPlanner.uniqueName("README", taken: ["README"]), "README 2")
        XCTAssertEqual(DownloadsPlanner.uniqueName("free.pdf", taken: []), "free.pdf")
    }

    func testTwoFilesWithSameNameInOnePlan() {
        // Same name cannot happen in one folder, but different case can on a
        // case-sensitive volume; the plan must still not collide.
        let plan = DownloadsPlanner.plan([DownloadEntry(name: "x.png"), DownloadEntry(name: "x.png")],
                                         settings: settings, folderNames: names)
        XCTAssertEqual(Set(plan.map(\.destination)).count, 2)
    }

    func testStabilityNeedsTwoSecondsOfSameSize() {
        var t = StabilityTracker(delay: 2)
        XCTAssertEqual(t.observe("a", size: 10, modified: 1, now: 0), .recheck(after: 2))
        // Still growing.
        XCTAssertEqual(t.observe("a", size: 20, modified: 2, now: 1), .recheck(after: 2))
        // Same size, but only 1 s later.
        XCTAssertEqual(t.observe("a", size: 20, modified: 2, now: 2), .recheck(after: 1))
        XCTAssertEqual(t.observe("a", size: 20, modified: 2, now: 3), .ready)
        XCTAssertEqual(t.pendingCount, 0)
    }

    func testStabilityForgetsVanishedFiles() {
        var t = StabilityTracker()
        _ = t.observe("a.crdownload", size: 1, modified: 0, now: 0)
        _ = t.observe("b", size: 1, modified: 0, now: 0)
        t.retain(only: ["b"])
        XCTAssertEqual(t.pendingCount, 1)
    }

    func testUndoHistoryCapacityAndOrder() {
        var h = UndoHistory()
        for i in 0..<60 { h.push(MoveRecord(from: "/d/\(i)", to: "/d/X/\(i)", date: Date(timeIntervalSince1970: Double(i)))) }
        XCTAssertEqual(h.records.count, 50)
        XCTAssertEqual(h.records.first?.from, "/d/59")
        XCTAssertEqual(h.take(at: 0)?.from, "/d/59")
        XCTAssertNil(h.take(at: 99))
        XCTAssertEqual(h.records.first?.fileName, "58")
        let data = try! JSONEncoder().encode(h)
        XCTAssertEqual(try! JSONDecoder().decode(UndoHistory.self, from: data), h)
    }

    func testRestoredFilesAreExcluded() {
        var h = UndoHistory()
        h.markRestored("a.pdf")
        h.markRestored("a.pdf")
        XCTAssertEqual(h.restored, ["a.pdf"])
        let plan = DownloadsPlanner.plan([DownloadEntry(name: "a.pdf"), DownloadEntry(name: "b.pdf")],
                                         settings: settings, folderNames: names, excluded: h.restoredNames)
        XCTAssertEqual(plan.map(\.source), ["b.pdf"])
    }

    func testRestorePathAvoidsOverwriting() {
        let r = MoveRecord(from: "/Users/example/Downloads/a.pdf", to: "/Users/example/Downloads/PDFs/a.pdf", date: Date())
        XCTAssertEqual(UndoHistory.restorePath(for: r) { _ in false }, "/Users/example/Downloads/a.pdf")
        let taken: Set<String> = ["/Users/example/Downloads/a.pdf", "/Users/example/Downloads/a 2.pdf"]
        XCTAssertEqual(UndoHistory.restorePath(for: r) { taken.contains($0) }, "/Users/example/Downloads/a 3.pdf")
    }

    func testSettingsDecoding() {
        let json = #"{"enabledCategories": ["pdfs", "gone"], "folderNames": {"pdfs": "Mis PDFs", "images": "a/b"}, "previewAccepted": true}"#
        let s = SettingsCoding.decode(DownloadsSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.enabledCategories, [.pdfs])
        XCTAssertEqual(s.folderNames, [.pdfs: "Mis PDFs"])
        XCTAssertTrue(s.previewAccepted)
        XCTAssertEqual(SettingsCoding.decode(DownloadsSettings.self, from: SettingsCoding.encode(s)), s)
        XCTAssertFalse(DownloadsSettings.default.previewAccepted)
    }
}
