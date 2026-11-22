import AppKit
import LigeroCore
import SwiftUI
import UniformTypeIdentifiers

/// AppCleaner-style uninstaller (SPEC §4.8). Works only on demand: the
/// module registers nothing; it adds a menu entry that opens a window, and
/// the window is released when it closes. Everything goes to the Trash with
/// `FileManager.trashItem`, never `rm` (CLAUDE.md rule 7).
@MainActor
final class UninstallModule: LigeroModule, MenuContributing {
    static let id = "uninstall"
    static let requiredPermissions: Set<Permission> = []

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(UninstallModule.self, titleKey: "module.uninstall.title", summaryKey: "module.uninstall.summary") { _ in
            UninstallModule()
        }
    }

    private var window: UninstallWindowController?

    func start() {}

    func stop() {
        window?.close()
        window = nil
    }

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: L("uninstall.menu.open")) { [weak self] in self?.open(nil) }]
    }

    func open(_ app: URL?) {
        let controller = window ?? UninstallWindowController { [weak self] in self?.window = nil }
        window = controller
        controller.show()
        if let app { controller.model.load(app) }
    }
}

@MainActor
final class UninstallWindowController: NSObject, NSWindowDelegate {
    let model = UninstallModel()
    private var window: NSWindow?
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: UninstallView(model: model)))
            w.title = L("uninstall.window.title")
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
        onClose()
    }
}

@MainActor
final class UninstallModel: ObservableObject {
    enum Phase: Equatable {
        case empty
        case scanning
        case ready
        case refused(String)
        case done(trashed: Int, failed: Int)
    }

    @Published private(set) var phase: Phase = .empty
    @Published var items: [UninstallItem] = []
    @Published private(set) var appName = ""
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var isRunning = false
    private var bundleID = ""
    private var scan: Task<Void, Never>?

    var totalSize: Int64 { UninstallPlan.totalSelected(items) }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("uninstall.choosePrompt")
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ url: URL) {
        scan?.cancel()
        items = []
        guard url.pathExtension == "app", let bundle = Bundle(url: url) else {
            phase = .refused(L("uninstall.error.notApp"))
            return
        }
        let info = bundle.infoDictionary ?? [:]
        let name = url.deletingPathExtension().lastPathComponent
        let names = [info["CFBundleName"] as? String, info["CFBundleDisplayName"] as? String, name].compactMap { $0 }
        let app = LeftoverFinder.App(bundleID: bundle.bundleIdentifier ?? "", names: names, path: url.path)
        appName = names.first ?? name
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
        bundleID = app.bundleID
        switch LeftoverFinder.refusal(for: app) {
        case .systemApp:
            phase = .refused(L("uninstall.error.system"))
            return
        case .missingBundleID:
            phase = .refused(L("uninstall.error.noBundleID"))
            return
        case nil:
            break
        }
        if app.bundleID == Bundle.main.bundleIdentifier {
            phase = .refused(L("uninstall.error.self"))
            return
        }
        refreshRunning()
        phase = .scanning
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        scan = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> [UninstallItem] in
                let fm = FileManager.default
                let leftovers = LeftoverFinder.find(app, home: home) { (try? fm.contentsOfDirectory(atPath: $0)) ?? [] }
                return UninstallPlan.items(
                    app: app.path,
                    appSize: Self.size(of: app.path),
                    leftovers: leftovers.map { ($0, Self.size(of: $0)) }
                )
            }.value
            guard let self, !Task.isCancelled else { return }
            self.items = result
            self.phase = .ready
        }
    }

    func refreshRunning() {
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func quitApp() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.terminate() }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.refreshRunning()
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Sends every selected item to the Trash. Never deletes.
    func moveToTrash() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var trashed = 0
        var failed = 0
        for path in UninstallPlan.trashList(items, home: home) {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                trashed += 1
            } catch {
                failed += 1
                Log.modules.error("Trash failed for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        items = []
        phase = .done(trashed: trashed, failed: failed)
    }

    func reset() {
        scan?.cancel()
        items = []
        phase = .empty
    }

    /// Allocated size of a file or folder, following no symlinks.
    nonisolated static func size(of path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        if v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let item = e?.nextObject() as? URL {
            let r = try? item.resourceValues(forKeys: keys)
            total += Int64(r?.totalFileAllocatedSize ?? r?.fileAllocatedSize ?? 0)
        }
        return total
    }
}

struct UninstallView: View {
    @ObservedObject var model: UninstallModel
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.phase {
            case .empty:
                dropZone
            case .scanning:
                header
                ProgressView(L("uninstall.scanning"))
                    .frame(maxWidth: .infinity, alignment: .center)
            case .refused(let reason):
                dropZone
                Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
            case .done(let trashed, let failed):
                Label(L("uninstall.done", trashed), systemImage: "trash")
                if failed > 0 {
                    Text(L("uninstall.doneFailed", failed)).foregroundStyle(Color.orange)
                }
                Button(L("uninstall.another")) { model.reset() }
            case .ready:
                header
                list
                footer
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 380)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.dashed").font(.system(size: 44)).foregroundStyle(.secondary)
            Text(L("uninstall.dropHint")).foregroundStyle(.secondary)
            Button(L("uninstall.choose")) { model.choose() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.4),
                                                                     style: StrokeStyle(lineWidth: 2, dash: [6])))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            DropLoader.load(providers) { items in
                for case .file(let path) in items { model.load(URL(fileURLWithPath: path)) }
            }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = model.appIcon {
                Image(nsImage: icon).resizable().frame(width: 40, height: 40)
            }
            Text(model.appName).font(.title2.weight(.semibold))
            Spacer()
            if model.isRunning {
                Text(L("uninstall.running")).foregroundStyle(Color.orange)
                Button(L("uninstall.quit")) { model.quitApp() }
            }
        }
    }

    private var list: some View {
        List {
            ForEach($model.items) { $item in
                HStack {
                    Toggle(isOn: $item.selected) {
                        Text(item.path).lineLimit(1).truncationMode(.middle).help(item.path)
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button { model.reveal(item.path) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless)
                        .help(L("uninstall.reveal"))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(L("uninstall.total", ByteCountFormatter.string(fromByteCount: model.totalSize, countStyle: .file)))
            Spacer()
            Button(L("uninstall.cancel")) { model.reset() }
            Button(L("uninstall.moveToTrash")) { model.moveToTrash() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning || !model.items.contains { $0.selected })
        }
    }
}
