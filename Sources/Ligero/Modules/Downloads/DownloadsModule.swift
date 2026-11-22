import AppKit
import CoreServices
import LigeroCore
import UniformTypeIdentifiers

/// Sorts finished downloads into ~/Downloads/<Category>/ (SPEC §4.3).
///
/// Mechanism: one FSEvents stream on ~/Downloads with 2 s latency. Each event
/// rescans only the top level of the folder. A file is moved once its size has
/// been stable for 2 s; the re-check is a single delayed task started by the
/// event, never a periodic timer. Nothing is ever deleted.
@MainActor
final class DownloadsModule: LigeroModule, MenuContributing {
    static let id = "downloads"
    static let requiredPermissions: Set<Permission> = []
    static let historyKey = "module.downloads.history"

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(DownloadsModule.self, titleKey: "module.downloads.title", summaryKey: "module.downloads.summary") {
            DownloadsModule(context: $0)
        }
    }

    private let context: AppContext
    private let settings: DownloadsSettings
    private var history: UndoHistory
    private var stream: FSEventStreamRef?
    private var tracker = StabilityTracker(delay: 2)
    private var recheck: Task<Void, Never>?
    private var recheckAt: Date?

    init(context: AppContext) {
        self.context = context
        settings = context.settings.load(DownloadsSettings.self, module: Self.id)
        history = context.settings.loadValue(UndoHistory.self, key: Self.historyKey) ?? UndoHistory()
    }

    static var downloadsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    func start() {
        guard settings.previewAccepted else {
            // SPEC §4.3: show the preview before the first activation.
            Log.modules.info("Downloads waits for the preview to be accepted")
            context.actions.openSettings(Self.id)
            return
        }
        startStream()
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        recheck?.cancel()
        recheck = nil
        recheckAt = nil
        tracker.removeAll()
    }

    private func startStream() {
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [Self.downloadsURL.path] as CFArray
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagIgnoreSelf)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, downloadsEventCallback, &ctx, paths,
            FSEventStreamEventId(UInt64.max), // kFSEventStreamEventIdSinceNow
            2.0, flags
        ) else {
            Log.modules.error("FSEventStreamCreate failed for Downloads")
            return
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    // MARK: Sorting

    fileprivate func folderChanged() {
        scan()
    }

    /// Looks at the top level of ~/Downloads and moves the files that are
    /// ready. Files still changing get one delayed re-check.
    private func scan() {
        let entries = Self.listEntries()
        let names = Set(entries.map(\.entry.name))
        tracker.retain(only: names)
        let now = Date().timeIntervalSinceReferenceDate
        var ready: [DownloadEntry] = []
        var nextCheck: Double?
        for item in entries where !DownloadsPlanner.shouldIgnore(item.entry) {
            guard !history.restoredNames.contains(item.entry.name),
                  Self.category(for: item.entry) != nil else { continue }
            switch tracker.observe(item.entry.name, size: item.entry.size, modified: item.modified, now: now) {
            case .ready:
                ready.append(item.entry)
            case .recheck(let after):
                nextCheck = min(nextCheck ?? after, after)
            }
        }
        if !ready.isEmpty { perform(Self.plan(for: ready, settings: settings, history: history)) }
        if let nextCheck { scheduleRecheck(after: nextCheck) }
    }

    private func scheduleRecheck(after seconds: Double) {
        let due = Date().addingTimeInterval(seconds)
        if let recheckAt, recheckAt <= due, recheck != nil { return }
        recheck?.cancel()
        recheckAt = due
        recheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 0.1))
            guard !Task.isCancelled, let self else { return }
            self.recheck = nil
            self.recheckAt = nil
            self.scan()
        }
    }

    /// Sorts everything sortable right now, without waiting (menu action and
    /// first activation).
    func sortNow() {
        let entries = Self.listEntries().map(\.entry)
        perform(Self.plan(for: entries, settings: settings, history: history))
    }

    private func perform(_ moves: [PlannedMove]) {
        guard !moves.isEmpty else { return }
        let fm = FileManager.default
        let base = Self.downloadsURL
        for move in moves {
            let source = base.appendingPathComponent(move.source)
            let folder = base.appendingPathComponent(move.folder, isDirectory: true)
            let destination = folder.appendingPathComponent(move.destinationName)
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                // moveItem never overwrites: it fails if the destination exists.
                try fm.moveItem(at: source, to: destination)
                history.push(MoveRecord(from: source.path, to: destination.path, date: Date()))
            } catch {
                Log.modules.error("Move failed for \(move.source, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        context.settings.saveValue(history, key: Self.historyKey)
    }

    func undo(at index: Int) {
        guard let record = history.take(at: index) else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: record.to) else {
            context.settings.saveValue(history, key: Self.historyKey)
            return
        }
        let target = UndoHistory.restorePath(for: record) { fm.fileExists(atPath: $0) }
        do {
            try fm.moveItem(atPath: record.to, toPath: target)
            history.markRestored((target as NSString).lastPathComponent)
        } catch {
            Log.modules.error("Undo failed: \(error.localizedDescription, privacy: .public)")
        }
        context.settings.saveValue(history, key: Self.historyKey)
    }

    // MARK: Shared with the preview

    struct ScannedEntry {
        let entry: DownloadEntry
        let modified: Double
    }

    static func listEntries() -> [ScannedEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL, includingPropertiesForKeys: keys, options: []
        ) else { return [] }
        return urls.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let entry = DownloadEntry(
                name: url.lastPathComponent,
                isDirectory: v?.isDirectory ?? false,
                size: Int64(v?.fileSize ?? 0),
                isPackage: v?.isPackage ?? false
            )
            return ScannedEntry(entry: entry, modified: v?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)
        }
    }

    /// Folder names from settings, falling back to the localized defaults.
    static func folderNames(_ settings: DownloadsSettings) -> [DownloadCategory: String] {
        var names: [DownloadCategory: String] = [:]
        for c in DownloadCategory.allCases {
            names[c] = settings.folderNames[c] ?? L(c.folderKey)
        }
        return names
    }

    static func plan(for entries: [DownloadEntry], settings: DownloadsSettings, history: UndoHistory) -> [PlannedMove] {
        let names = folderNames(settings)
        var existing: [String: Set<String>] = [:]
        for folder in Set(names.values) {
            let url = downloadsURL.appendingPathComponent(folder, isDirectory: true)
            if let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                existing[folder] = Set(items)
            }
        }
        return DownloadsPlanner.plan(
            entries, settings: settings, folderNames: names, existing: existing,
            excluded: history.restoredNames, category: category(for:)
        )
    }

    /// Extension table first, then UTType for unusual extensions.
    static func category(for entry: DownloadEntry) -> DownloadCategory? {
        let ext = DownloadsPlanner.fileExtension(entry.name)
        if let c = DownloadCategory.forExtension(ext) { return c }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .pdf) { return .pdfs }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .diskImage) { return .installers }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .code }
        if type.conforms(to: .presentation) || type.conforms(to: .spreadsheet) || type.conforms(to: .text) {
            return .documents
        }
        return nil
    }

    // MARK: Menu

    func menuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let sort = ClosureMenuItem(title: L("downloads.menu.sortNow")) { [weak self] in self?.sortNow() }
        sort.isEnabled = settings.previewAccepted
        items.append(sort)
        if !settings.previewAccepted {
            items.append(ClosureMenuItem(title: L("downloads.menu.preview")) { [weak self] in
                self?.context.actions.openSettings(Self.id)
            })
        }

        let undoMenu = NSMenu()
        undoMenu.autoenablesItems = false
        if history.records.isEmpty {
            let empty = NSMenuItem(title: L("downloads.menu.historyEmpty"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            undoMenu.addItem(empty)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        for (i, record) in history.records.enumerated() {
            let folder = ((record.to as NSString).deletingLastPathComponent as NSString).lastPathComponent
            let title = L("downloads.menu.undoEntry", record.fileName, folder, formatter.string(from: record.date))
            undoMenu.addItem(ClosureMenuItem(title: title) { [weak self] in self?.undo(at: i) })
        }
        let historyItem = NSMenuItem(title: L("downloads.menu.history"), action: nil, keyEquivalent: "")
        historyItem.submenu = undoMenu
        items.append(historyItem)
        return items
    }
}

private func downloadsEventCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ paths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let module = Unmanaged<DownloadsModule>.fromOpaque(info).takeUnretainedValue()
    // The stream is scheduled on the main queue.
    MainActor.assumeIsolated { module.folderChanged() }
}
