import Foundation

/// Folders the Downloads module sorts into (SPEC §4.3).
public enum DownloadCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case images, documents, pdfs, video, audio, archives, installers, code

    /// Localization key of the default folder name.
    public var folderKey: String { "downloads.folder.\(rawValue)" }
    public var titleKey: String { "downloads.category.\(rawValue)" }

    static let byExtension: [String: DownloadCategory] = {
        var map: [String: DownloadCategory] = [:]
        let table: [DownloadCategory: [String]] = [
            .images: ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "svg",
                      "avif", "ico", "psd", "raw", "cr2", "cr3", "nef", "arw", "dng", "jxl"],
            .pdfs: ["pdf"],
            .documents: ["doc", "docx", "odt", "rtf", "txt", "md", "pages", "key", "numbers", "xls", "xlsx",
                         "ods", "csv", "tsv", "ppt", "pptx", "odp", "epub", "mobi", "tex", "vcf", "ics"],
            .video: ["mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg", "3gp", "ts"],
            .audio: ["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "ogg", "opus", "wma", "mid", "midi", "caf"],
            .archives: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "zst", "lz", "lzma", "cab"],
            .installers: ["dmg", "pkg", "mpkg", "iso", "xip"],
            .code: ["swift", "py", "js", "mjs", "ts", "tsx", "jsx", "json", "yaml", "yml", "toml", "xml", "html",
                    "htm", "css", "scss", "c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt", "go", "rs",
                    "rb", "php", "sh", "zsh", "bash", "sql", "ipynb", "lua", "pl", "r", "dart", "patch", "diff"],
        ]
        for (category, extensions) in table {
            for e in extensions { map[e] = category }
        }
        return map
    }()

    /// Category for a file extension (case-insensitive), or nil to leave the
    /// file where it is.
    public static func forExtension(_ ext: String) -> DownloadCategory? {
        byExtension[ext.lowercased()]
    }
}

/// Settings of the Downloads module.
public struct DownloadsSettings: ModuleSettings {
    public var enabledCategories: Set<DownloadCategory>
    /// Folder name per category. Empty until the module is first configured;
    /// the app then fills it from the localized defaults, so changing the
    /// app language later does not move the folders.
    public var folderNames: [DownloadCategory: String]
    /// The user has seen the preview and turned sorting on (SPEC §4.3).
    public var previewAccepted: Bool

    public init(enabledCategories: Set<DownloadCategory>, folderNames: [DownloadCategory: String], previewAccepted: Bool) {
        self.enabledCategories = enabledCategories
        self.folderNames = folderNames
        self.previewAccepted = previewAccepted
    }

    public static let `default` = DownloadsSettings(
        enabledCategories: Set(DownloadCategory.allCases), folderNames: [:], previewAccepted: false
    )

    enum CodingKeys: String, CodingKey { case enabledCategories, folderNames, previewAccepted }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawCategories: [String]? = c.value(.enabledCategories, or: nil)
        enabledCategories = rawCategories.map { Set($0.compactMap(DownloadCategory.init(rawValue:))) }
            ?? Self.default.enabledCategories
        let rawNames: [String: String] = c.value(.folderNames, or: [:])
        var names: [DownloadCategory: String] = [:]
        for (k, v) in rawNames {
            if let cat = DownloadCategory(rawValue: k), DownloadsPlanner.isValidFolderName(v) { names[cat] = v }
        }
        folderNames = names
        previewAccepted = c.value(.previewAccepted, or: false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabledCategories.map(\.rawValue).sorted(), forKey: .enabledCategories)
        try c.encode(Dictionary(uniqueKeysWithValues: folderNames.map { ($0.key.rawValue, $0.value) }), forKey: .folderNames)
        try c.encode(previewAccepted, forKey: .previewAccepted)
    }
}

/// One entry found at the top level of ~/Downloads.
public struct DownloadEntry: Equatable, Sendable {
    public var name: String
    public var isDirectory: Bool
    public var size: Int64
    public var isPackage: Bool

    public init(name: String, isDirectory: Bool = false, size: Int64 = 0, isPackage: Bool = false) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.isPackage = isPackage
    }
}

/// A planned move, relative to the Downloads folder.
public struct PlannedMove: Equatable, Sendable {
    public var source: String
    public var folder: String
    public var destinationName: String
    public var category: DownloadCategory

    public var destination: String { folder + "/" + destinationName }
}

public enum DownloadsPlanner {
    /// Extensions of files that are still being downloaded.
    public static let partialExtensions: Set<String> = [
        "crdownload", "part", "partial", "download", "opdownload", "tmp", "temp", "!ut", "aria2", "filepart",
    ]

    /// Files that are never touched: hidden files, in-progress downloads,
    /// folders and packages (including our own category folders).
    public static func shouldIgnore(_ entry: DownloadEntry) -> Bool {
        if entry.isDirectory || entry.isPackage { return true }
        if entry.name.hasPrefix(".") || entry.name.hasPrefix("~$") { return true }
        let ext = fileExtension(entry.name)
        if partialExtensions.contains(ext) { return true }
        return false
    }

    public static func fileExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    public static func isValidFolderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains("/") && trimmed != "." && trimmed != ".." && !trimmed.hasPrefix(".")
    }

    /// What sorting would do with `entries` right now. Used both for the
    /// preview and for the real run, so the preview never lies.
    ///
    /// - Parameters:
    ///   - existing: names already present in each destination folder, to pick
    ///     a free name ("file 2.pdf") instead of overwriting.
    ///   - category: optional override for files whose extension is unknown
    ///     (the app asks UTType).
    public static func plan(
        _ entries: [DownloadEntry],
        settings: DownloadsSettings,
        folderNames: [DownloadCategory: String],
        existing: [String: Set<String>] = [:],
        excluded: Set<String> = [],
        category: (DownloadEntry) -> DownloadCategory? = { _ in nil }
    ) -> [PlannedMove] {
        var taken = existing
        var moves: [PlannedMove] = []
        for entry in entries.sorted(by: { $0.name < $1.name }) where !shouldIgnore(entry) && !excluded.contains(entry.name) {
            guard let cat = DownloadCategory.forExtension(fileExtension(entry.name)) ?? category(entry),
                  settings.enabledCategories.contains(cat),
                  let folder = folderNames[cat], isValidFolderName(folder) else { continue }
            let name = uniqueName(entry.name, taken: taken[folder, default: []])
            taken[folder, default: []].insert(name)
            moves.append(PlannedMove(source: entry.name, folder: folder, destinationName: name, category: cat))
        }
        return moves
    }

    /// "a.pdf" → "a 2.pdf" → "a 3.pdf"… until it is free. Keeps double
    /// extensions such as ".tar.gz" together.
    public static func uniqueName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let (stem, ext) = splitExtension(name)
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            if !taken.contains(candidate) { return candidate }
            n += 1
        }
    }

    static func splitExtension(_ name: String) -> (String, String) {
        let lower = name.lowercased()
        for double in ["tar.gz", "tar.bz2", "tar.xz", "tar.zst"] where lower.hasSuffix("." + double) {
            let stem = String(name.dropLast(double.count + 1))
            if !stem.isEmpty { return (stem, String(name.suffix(double.count))) }
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }
}

/// "Wait until the size has been stable for 2 s" without a periodic timer
/// (SPEC §4.3): every file-system event calls `observe`, which either says
/// the file is ready or asks for a single re-check after `delay` seconds.
public struct StabilityTracker {
    public enum Decision: Equatable, Sendable {
        case ready
        case recheck(after: Double)
    }

    struct Sample {
        var size: Int64
        var modified: Double
        var since: Double
    }

    public let delay: Double
    private var samples: [String: Sample] = [:]

    public init(delay: Double = 2) {
        self.delay = delay
    }

    public var pendingCount: Int { samples.count }

    public mutating func observe(_ name: String, size: Int64, modified: Double, now: Double) -> Decision {
        if let s = samples[name], s.size == size, s.modified == modified {
            let elapsed = now - s.since
            if elapsed >= delay - 0.05 {
                samples.removeValue(forKey: name)
                return .ready
            }
            return .recheck(after: delay - elapsed)
        }
        samples[name] = Sample(size: size, modified: modified, since: now)
        return .recheck(after: delay)
    }

    /// Forget files that disappeared (renamed or deleted by the browser).
    public mutating func retain(only names: Set<String>) {
        samples = samples.filter { names.contains($0.key) }
    }

    public mutating func removeAll() {
        samples.removeAll()
    }
}

/// One move Ligero made, kept so it can be undone from the menu.
public struct MoveRecord: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
    public var date: Date

    public init(from: String, to: String, date: Date) {
        self.from = from
        self.to = to
        self.date = date
    }

    public var fileName: String { (to as NSString).lastPathComponent }
}

/// Last 50 moves, newest first (SPEC §4.3).
public struct UndoHistory: Codable, Equatable, Sendable {
    public static let capacity = 50
    public private(set) var records: [MoveRecord] = []
    /// Names of files put back by an undo. Sorting skips them so an undone
    /// file is not moved again on the next event.
    public private(set) var restored: [String] = []

    public init(records: [MoveRecord] = []) {
        self.records = Array(records.prefix(Self.capacity))
    }

    public var restoredNames: Set<String> { Set(restored) }

    public mutating func markRestored(_ name: String) {
        restored.removeAll { $0 == name }
        restored.insert(name, at: 0)
        if restored.count > Self.capacity { restored.removeLast(restored.count - Self.capacity) }
    }

    enum CodingKeys: String, CodingKey { case records, restored }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = c.value(.records, or: [])
        restored = c.value(.restored, or: [])
    }

    public mutating func push(_ record: MoveRecord) {
        records.insert(record, at: 0)
        if records.count > Self.capacity { records.removeLast(records.count - Self.capacity) }
    }

    /// Removes and returns the record at `index` (0 = newest).
    public mutating func take(at index: Int) -> MoveRecord? {
        guard records.indices.contains(index) else { return nil }
        return records.remove(at: index)
    }

    public mutating func removeAll() {
        records.removeAll()
    }

    /// Where an undone file goes: its original path, or a free name next to
    /// it if something new took that name meanwhile.
    public static func restorePath(for record: MoveRecord, exists: (String) -> Bool) -> String {
        guard exists(record.from) else { return record.from }
        let dir = (record.from as NSString).deletingLastPathComponent
        let name = (record.from as NSString).lastPathComponent
        var taken: Set<String> = [name]
        var candidate = DownloadsPlanner.uniqueName(name, taken: taken)
        while exists(dir + "/" + candidate) {
            taken.insert(candidate)
            candidate = DownloadsPlanner.uniqueName(name, taken: taken)
        }
        return dir + "/" + candidate
    }
}
