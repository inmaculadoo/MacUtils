import AppKit
import LigeroCore
import SwiftUI

/// ⌥Tab window switcher with thumbnails (SPEC §4.5). EXPERIMENTAL.
///
/// Idle cost is zero: Carbon hotkeys plus the event-driven WindowService.
/// Key monitors exist only while the panel is open. Thumbnails are captured
/// with SCScreenshotManager when the panel opens and cached until the window
/// changes (AXObserver). Without Screen Recording it shows app icons.
@MainActor
final class SwitcherModule: LigeroModule {
    static let id = "switcher"
    static let requiredPermissions: Set<Permission> = [.accessibility]

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(SwitcherModule.self, titleKey: "module.switcher.title", summaryKey: "module.switcher.summary",
                         experimental: true) { SwitcherModule(context: $0) }
    }

    private let context: AppContext
    private let settings: SwitcherSettings
    private let service = WindowService.shared
    private var tokens: [HotKeyToken] = []
    private var panel: SwitcherPanel?
    private let viewModel = SwitcherViewModel()
    private var monitors: [Any] = []
    private var all: [WindowInfo] = []
    private var shown: [WindowInfo] = []
    private var selection = SwitcherSelection(count: 0)
    private var holdModifiers: NSEvent.ModifierFlags = []
    private var thumbnailTask: Task<Void, Never>?

    init(context: AppContext) {
        self.context = context
        settings = context.settings.load(SwitcherSettings.self, module: Self.id)
    }

    func start() {
        service.acquire(self) { [weak self] event in self?.windowEvent(event) }
        if let combo = settings.shortcut, let t = context.hotKeys.register(combo, action: { [weak self] in self?.trigger(reverse: false) }) {
            tokens.append(t)
        }
        if let combo = settings.reverseShortcut, let t = context.hotKeys.register(combo, action: { [weak self] in self?.trigger(reverse: true) }) {
            tokens.append(t)
        }
        holdModifiers = Self.cocoaModifiers(settings.shortcut?.modifiers ?? [])
    }

    func stop() {
        close()
        for t in tokens { context.hotKeys.unregister(t) }
        tokens.removeAll()
        service.release(self)
        panel?.orderOut(nil)
        panel = nil
    }

    private var isOpen: Bool { panel?.isVisible == true }

    private func trigger(reverse: Bool) {
        if isOpen {
            reverse ? selection.previous() : selection.next()
            publish()
        } else {
            open(reverse: reverse)
        }
    }

    private func open(reverse: Bool) {
        all = service.windows()
        guard !all.isEmpty else {
            NSSound.beep()
            return
        }
        viewModel.query = ""
        shown = all
        selection = SwitcherSelection(count: shown.count, reverse: reverse)
        let panel = self.panel ?? SwitcherPanel(viewModel: viewModel)
        self.panel = panel
        publish()
        panel.present()
        installMonitors()
        // Released the modifier before the panel could see it: quick switch.
        if !holdModifiers.isEmpty, NSEvent.modifierFlags.intersection(holdModifiers).isEmpty {
            commit()
            return
        }
        loadThumbnails()
    }

    private func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        panel?.orderOut(nil)
        all = []
        shown = []
        viewModel.items = []
    }

    private func commit() {
        let target = shown.indices.contains(selection.index) ? shown[selection.index] : nil
        close()
        if let target { service.activate(target) }
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let code = event.keyCode
            let flags = event.modifierFlags
            let chars = event.charactersIgnoringModifiers ?? ""
            return MainActor.assumeIsolated { self?.key(code, flags, chars) ?? false } ? nil : event
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.flags(flags) }
            return event
        }) { monitors.append(m) }
    }

    private func flags(_ flags: NSEvent.ModifierFlags) {
        guard isOpen, !holdModifiers.isEmpty, flags.intersection(holdModifiers).isEmpty else { return }
        commit()
    }

    /// Returns true when the key was handled.
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags, _ chars: String) -> Bool {
        guard isOpen else { return false }
        let k = UInt32(code)
        let command = flags.contains(.command)
        switch k {
        case KeyCode.escape: close()
        case KeyCode.returnKey: commit()
        case KeyCode.tab: flags.contains(.shift) ? selection.previous() : selection.next()
        case KeyCode.rightArrow, KeyCode.downArrow: selection.next()
        case KeyCode.leftArrow, KeyCode.upArrow: selection.previous()
        case KeyCode.delete:
            if !viewModel.query.isEmpty { viewModel.query.removeLast(); filter() }
        case KeyCode.w where command: act(service.close)
        case KeyCode.m where command: act(service.minimize)
        case KeyCode.q where command: act(service.quit)
        default:
            guard !command, let scalar = chars.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) else {
                return true
            }
            viewModel.query += chars
            filter()
            return true
        }
        publish()
        return true
    }

    private func act(_ action: @MainActor (WindowInfo) -> Void) {
        guard shown.indices.contains(selection.index) else { return }
        action(shown[selection.index])
        // The AX events will invalidate the cache; refresh what we show now.
        let removed = shown[selection.index].id
        all.removeAll { $0.id == removed }
        filter()
    }

    private func filter() {
        shown = all.filter { SwitcherSearch.matches(viewModel.query, title: $0.title, app: $0.appName) }
        selection.resize(to: shown.count)
        if viewModel.query.isEmpty == false { selection.select(0) }
        publish()
    }

    private func publish() {
        viewModel.items = shown.map { w in
            SwitcherItem(
                id: w.id,
                title: w.title.isEmpty ? w.appName : w.title,
                appName: w.appName,
                icon: w.app?.icon,
                thumbnail: service.thumbnails.peek(w.id).map { NSImage(cgImage: $0, size: .zero) },
                minimized: w.isMinimized
            )
        }
        viewModel.selected = selection.index
        panel?.resize()
    }

    private func loadThumbnails() {
        guard settings.showThumbnails, CGPreflightScreenCaptureAccess() else { return }
        let ids = all.map(\.id)
        thumbnailTask = Task { @MainActor [weak self] in
            await self?.service.loadThumbnails(for: ids)
            guard let self, !Task.isCancelled, self.isOpen else { return }
            self.publish()
        }
    }

    private func windowEvent(_ event: WindowEvent) {
        guard isOpen else { return }
        switch event {
        case .destroyed, .appTerminated, .created:
            let query = viewModel.query
            all = service.windows()
            viewModel.query = query
            filter()
        case .focused, .changed:
            break
        }
    }

    static func cocoaModifiers(_ m: KeyCombo.Modifiers) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if m.contains(.command) { f.insert(.command) }
        if m.contains(.option) { f.insert(.option) }
        if m.contains(.control) { f.insert(.control) }
        // Shift alone is not a "hold" modifier: ⌥⇧Tab still commits on ⌥ release.
        return f
    }
}

struct SwitcherItem: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let icon: NSImage?
    let thumbnail: NSImage?
    let minimized: Bool
}

@MainActor
final class SwitcherViewModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selected = 0
    @Published var query = ""
}

/// Created once, then only shown and hidden (SPEC §2.4).
@MainActor
final class SwitcherPanel: NSPanel {
    private let viewModel: SwitcherViewModel

    init(viewModel: SwitcherViewModel) {
        self.viewModel = viewModel
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 240),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = NSHostingView(rootView: SwitcherView(model: viewModel))
    }

    override var canBecomeKey: Bool { true }

    func present() {
        resize()
        orderFrontRegardless()
        makeKey()
    }

    /// Centres the panel on the screen with the mouse, sized to the content.
    func resize() {
        guard let view = contentView else { return }
        let size = view.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        let w = min(size.width, frame.width - 40)
        let h = min(size.height, frame.height - 40)
        setFrame(NSRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h), display: true)
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherViewModel
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 190), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.query.isEmpty {
                Label(model.query, systemImage: "magnifyingglass").font(.headline)
            }
            if model.items.isEmpty {
                Text(L("switcher.noMatches")).foregroundStyle(.secondary).frame(width: 300, height: 80)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        tile(item, selected: index == model.selected)
                    }
                }
                .frame(width: gridWidth)
            }
            Text(L("switcher.hint")).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
        .fixedSize()
    }

    private var gridWidth: CGFloat {
        let perRow = min(max(model.items.count, 1), 6)
        return CGFloat(perRow) * 180 + CGFloat(perRow - 1) * 10
    }

    private func tile(_ item: SwitcherItem, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumb = item.thumbnail {
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                    } else if let icon = item.icon {
                        Image(nsImage: icon).resizable().frame(width: 64, height: 64)
                    }
                }
                .frame(width: 170, height: 106)
                if item.thumbnail != nil, let icon = item.icon {
                    Image(nsImage: icon).resizable().frame(width: 28, height: 28).offset(x: 4, y: 4)
                }
            }
            Text(item.title).font(.caption).lineLimit(1).frame(width: 170)
                .foregroundStyle(item.minimized ? .secondary : .primary)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.35) : Color.clear))
    }
}
