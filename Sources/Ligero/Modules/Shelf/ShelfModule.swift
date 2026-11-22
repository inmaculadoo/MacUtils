import AppKit
import LigeroCore
import SwiftUI
import UniformTypeIdentifiers

/// Drop shelf under the notch (SPEC §4.4).
///
/// A global monitor for `leftMouseDragged` / `leftMouseUp` only fires while
/// the mouse button is used. The drag pasteboard's change count is read once
/// per gesture (first dragged event). The panel is created the first time it
/// is needed and then only hidden and shown.
@MainActor
final class ShelfModule: LigeroModule, MenuContributing {
    static let id = "shelf"
    static let requiredPermissions: Set<Permission> = []

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(ShelfModule.self, titleKey: "module.shelf.title", summaryKey: "module.shelf.summary") {
            ShelfModule(context: $0)
        }
    }

    private let context: AppContext
    private let settings: ShelfSettings
    private var monitor: Any?
    private var hotKey: HotKeyToken?
    private var detector = DragDetector(changeCount: NSPasteboard(name: .drag).changeCount)
    private var panel: NSPanel?
    private let viewModel = ShelfViewModel()
    private var shownByDrag = false
    private var hideCheck: Task<Void, Never>?

    init(context: AppContext) {
        self.context = context
        settings = context.settings.load(ShelfSettings.self, module: Self.id)
        viewModel.pinnedFolders = settings.pinnedFolders.map { URL(fileURLWithPath: $0, isDirectory: true) }
        viewModel.onClose = { [weak self] in self?.hide() }
    }

    func start() {
        if settings.showOnDrag {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                let isUp = event.type == .leftMouseUp
                MainActor.assumeIsolated { self?.mouseEvent(isUp: isUp) }
            }
        }
        if let combo = settings.shortcut {
            hotKey = context.hotKeys.register(combo) { [weak self] in self?.toggle() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let hotKey { context.hotKeys.unregister(hotKey) }
        hotKey = nil
        hideCheck?.cancel()
        hideCheck = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func mouseEvent(isUp: Bool) {
        if isUp {
            detector.mouseUp()
            guard shownByDrag else { return }
            // Let a drop on the shelf land before deciding to hide it.
            hideCheck?.cancel()
            hideCheck = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { return }
                if self.viewModel.shelf.isEmpty { self.hide() }
                self.shownByDrag = false
            }
            return
        }
        guard detector.draggedNeedsCheck() else { return }
        if detector.pasteboard(changeCount: NSPasteboard(name: .drag).changeCount), panel?.isVisible != true {
            shownByDrag = true
            show()
        }
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        viewModel.prune()
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        shownByDrag = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 130),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ShelfView(model: viewModel))
        return panel
    }

    /// Centred under the menu bar (and the notch) of the screen with the mouse.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let size = panel.frame.size
        let top = screen.visibleFrame.maxY - 8
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: top - size.height))
    }

    func menuItems() -> [NSMenuItem] {
        let title = settings.shortcut.map { L("shelf.menu.showWithShortcut", $0.description) } ?? L("shelf.menu.show")
        return [ClosureMenuItem(title: title) { [weak self] in self?.show() }]
    }
}

/// State of the shelf panel.
@MainActor
final class ShelfViewModel: ObservableObject {
    @Published private(set) var shelf = ShelfModel()
    @Published var pinnedFolders: [URL] = []
    @Published var targeted = false
    var onClose: @MainActor () -> Void = {}

    func prune() {
        shelf.prune { FileManager.default.fileExists(atPath: $0) }
    }

    func add(_ items: [ShelfItem]) {
        shelf.add(contentsOf: items)
    }

    func remove(_ item: ShelfItem) {
        shelf.remove(item)
    }

    func clear() {
        shelf.removeAll()
    }

    /// Copies dropped files into a pinned folder, never overwriting.
    func copy(_ files: [URL], to folder: URL) {
        let fm = FileManager.default
        let existing = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        var taken = existing
        for file in files {
            let name = DownloadsPlanner.uniqueName(file.lastPathComponent, taken: taken)
            taken.insert(name)
            do {
                try fm.copyItem(at: file, to: folder.appendingPathComponent(name))
            } catch {
                Log.modules.error("Shelf copy failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reads files, URLs and text from drop providers.
    static func load(_ providers: [NSItemProvider], into handler: @escaping @MainActor ([ShelfItem]) -> Void) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url = Self.url(from: item)
                    Task { @MainActor in if let url { handler([.file(path: url.path)]) } }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    let url = Self.url(from: item)
                    Task { @MainActor in if let url { handler([.url(url.absoluteString)]) } }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    let text: String?
                    if let s = item as? String { text = s } else if let d = item as? Data { text = String(data: d, encoding: .utf8) } else { text = nil }
                    Task { @MainActor in if let text { handler([.text(text)]) } }
                }
            }
        }
    }

    nonisolated static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let s = item as? String { return URL(string: s) }
        return nil
    }
}

struct ShelfView: View {
    @ObservedObject var model: ShelfViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("shelf.title")).font(.headline)
                Spacer()
                if !model.shelf.isEmpty {
                    Button(L("shelf.clear")) { model.clear() }.buttonStyle(.borderless)
                }
                Button { model.onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("shelf.close"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.shelf.isEmpty {
                        Text(L("shelf.dropHere"))
                            .foregroundStyle(.secondary)
                            .frame(width: 180, height: 64)
                    }
                    ForEach(model.shelf.items, id: \.self) { item in
                        ShelfTile(item: item) { model.remove(item) }
                    }
                    ForEach(model.pinnedFolders, id: \.self) { folder in
                        PinnedFolderTile(folder: folder, model: model)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 420, height: 130)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.targeted ? Color.accentColor : Color.clear, lineWidth: 2))
        )
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $model.targeted) { providers in
            ShelfViewModel.load(providers) { items in model.add(items) }
            return true
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    let remove: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 4) {
            icon.frame(width: 36, height: 36)
            Text(item.label).font(.caption2).lineLimit(1).frame(width: 72)
        }
        .padding(4)
        .contentShape(Rectangle())
        .onDrag { provider }
        .contextMenu { Button(L("shelf.remove"), action: remove) }
        .help(item.label)
    }

    @ViewBuilder private var icon: some View {
        switch item {
        case .file(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
        case .url:
            Image(systemName: "link").font(.title)
        case .text:
            Image(systemName: "text.alignleft").font(.title)
        }
    }

    private var provider: NSItemProvider {
        switch item {
        case .file(let path):
            return NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
        case .url(let s):
            return URL(string: s).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        case .text(let t):
            return NSItemProvider(object: t as NSString)
        }
    }
}

private struct PinnedFolderTile: View {
    let folder: URL
    @ObservedObject var model: ShelfViewModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path)).resizable().frame(width: 36, height: 36)
            Text(folder.lastPathComponent).font(.caption2).lineLimit(1).frame(width: 72)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Color.accentColor.opacity(0.25) : Color.clear))
        .help(L("shelf.pinnedHelp", folder.path))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            let destination = folder
            ShelfViewModel.load(providers) { items in
                let files = items.compactMap { item -> URL? in
                    if case .file(let p) = item { return URL(fileURLWithPath: p) }
                    return nil
                }
                model.copy(files, to: destination)
            }
            return true
        }
    }
}
