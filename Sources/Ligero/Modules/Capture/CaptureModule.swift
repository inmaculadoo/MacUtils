import AppKit
import LigeroCore
@preconcurrency import ScreenCaptureKit
import Vision

/// Region → OCR text, and floating pins (SPEC §4.9). macOS already has a
/// plain region screenshot, so the module doesn't duplicate it.
/// Works only on demand: idle it only holds Carbon hotkeys. Captures use
/// `SCScreenshotManager` one-shot; there is never an `SCStream`.
@MainActor
final class CaptureModule: LigeroModule, MenuContributing {
    static let id = "capture"
    static let requiredPermissions: Set<Permission> = [.screenRecording]

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(CaptureModule.self, titleKey: "module.capture.title", summaryKey: "module.capture.summary") {
            CaptureModule(context: $0)
        }
    }

    enum Mode {
        case text, pin
    }

    private let context: AppContext
    private let settings: CaptureSettings
    private var tokens: [HotKeyToken] = []
    private var overlay: SelectionOverlay?
    private var pins: [PinWindow] = []

    init(context: AppContext) {
        self.context = context
        settings = context.settings.load(CaptureSettings.self, module: Self.id)
    }

    func start() {
        let shortcuts: [(KeyCombo?, Mode)] = [
            (settings.textShortcut, .text), (settings.pinShortcut, .pin),
        ]
        for (combo, mode) in shortcuts {
            guard let combo else { continue }
            if let t = context.hotKeys.register(combo, action: { [weak self] in self?.begin(mode) }) { tokens.append(t) }
        }
    }

    func stop() {
        for t in tokens { context.hotKeys.unregister(t) }
        tokens.removeAll()
        overlay?.dismiss()
        overlay = nil
        for p in pins { p.close() }
        pins.removeAll()
    }

    func menuItems() -> [NSMenuItem] {
        func title(_ key: String, _ combo: KeyCombo?) -> String {
            combo.map { L("capture.menu.withShortcut", L(key), $0.description) } ?? L(key)
        }
        return [
            ClosureMenuItem(title: title("capture.menu.text", settings.textShortcut)) { [weak self] in self?.begin(.text) },
            ClosureMenuItem(title: title("capture.menu.pin", settings.pinShortcut)) { [weak self] in self?.begin(.pin) },
        ]
    }

    // MARK: Flow

    func begin(_ mode: Mode) {
        guard overlay == nil else { return }
        // The overlay activates Ligero to get Esc; give focus back afterwards.
        let previous = NSWorkspace.shared.frontmostApplication
        let overlay = SelectionOverlay { [weak self] selection in
            if previous?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previous?.activate() }
            guard let self else { return }
            self.overlay = nil
            guard let selection else { return }
            Task { @MainActor in await self.capture(selection, mode: mode) }
        }
        self.overlay = overlay
        overlay.present()
    }

    private func capture(_ selection: LRect, mode: Mode) async {
        guard let screen = NSScreen.screens.first(where: { LRect($0.frame).intersection(selection).area > 0 }),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let source = CaptureGeometry.sourceRect(selection: selection, displayFrame: LRect(screen.frame)) else { return }
        let scale = Double(screen.backingScaleFactor)
        let request = CaptureRequest(
            displayID: displayID,
            sourceRect: CGRect(x: source.x, y: source.y, width: source.width, height: source.height),
            pixels: CaptureGeometry.pixelSize(of: source, scale: scale),
            bundleID: Bundle.main.bundleIdentifier ?? ""
        )
        let image: CGImage
        do {
            image = try await Self.screenshot(request).image
        } catch {
            Log.modules.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            Self.tell(L("capture.error.title"), L("capture.error.permission"))
            return
        }
        switch mode {
        case .pin:
            output(image)
            pin(image, at: selection)
        case .text:
            let text = await Self.recognizeText(SendableImage(image: image))
            guard !text.isEmpty else {
                // Say so: a silent beep left the old clipboard in place and
                // looked like the OCR had copied the wrong thing.
                Self.tell(L("capture.noText.title"), L("capture.noText.message"))
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            NSSound(named: NSSound.Name("Tink"))?.play()
        }
    }

    /// A short explanation when a capture can't do what was asked.
    private static func tell(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        NSApp.activate()
        alert.runModal()
    }

    private func output(_ image: CGImage) {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        if settings.copyToClipboard {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)
        }
        if settings.saveToDesktop {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let name = L("capture.fileName", formatter.string(from: Date())) + ".png"
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: desktop.path)) ?? [])
            let url = desktop.appendingPathComponent(DownloadsPlanner.uniqueName(name, taken: taken))
            do { try png.write(to: url) } catch {
                Log.modules.error("Saving capture failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        NSSound(named: NSSound.Name("Pop"))?.play()
    }

    private func pin(_ image: CGImage, at selection: LRect) {
        let window = PinWindow(image: image, frame: selection) { [weak self] closed in
            self?.pins.removeAll { $0 === closed }
        }
        pins.append(window)
        window.orderFrontRegardless()
    }

    // MARK: Off the main actor

    struct CaptureRequest: Sendable {
        let displayID: CGDirectDisplayID
        let sourceRect: CGRect
        let pixels: (width: Int, height: Int)
        let bundleID: String
    }

    struct SendableImage: @unchecked Sendable {
        let image: CGImage
    }

    enum CaptureError: Error {
        case noDisplay
    }

    /// One-shot screenshot of a display region, excluding Ligero's own
    /// windows (the selection overlay).
    nonisolated static func screenshot(_ r: CaptureRequest) async throws -> SendableImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == r.displayID }) else { throw CaptureError.noDisplay }
        let me = content.applications.filter { $0.bundleIdentifier == r.bundleID }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = r.sourceRect
        config.width = r.pixels.width
        config.height = r.pixels.height
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return SendableImage(image: image)
    }

    /// Vision OCR in Spanish and English (SPEC §4.9).
    nonisolated static func recognizeText(_ image: SendableImage) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es-ES", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image.image, options: [:])
            do { try handler.perform([request]) } catch { return "" }
            let boxes: [TextBox] = (request.results ?? []).compactMap { obs in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                let b = obs.boundingBox
                return TextBox(candidate.string, x: Double(b.minX), y: Double(b.minY),
                               width: Double(b.width), height: Double(b.height))
            }
            return OCRText.assemble(boxes)
        }.value
    }
}

// MARK: - Selection overlay

/// Dimmed full-screen windows (one per display) where the user drags a
/// rectangle. Created per capture and released right after.
@MainActor
final class SelectionOverlay {
    private var windows: [OverlayWindow] = []
    private let completion: @MainActor (LRect?) -> Void
    private var finished = false

    init(completion: @escaping @MainActor (LRect?) -> Void) {
        self.completion = completion
    }

    func present() {
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen) { [weak self] rect in self?.finish(rect) }
            windows.append(w)
            w.orderFrontRegardless()
        }
        NSApp.activate()
        windows.first { $0.screen == NSScreen.main }?.makeKey()
        windows.first?.makeKey()
        NSCursor.crosshair.push()
    }

    func dismiss() {
        finish(nil)
    }

    private func finish(_ rect: LRect?) {
        guard !finished else { return }
        finished = true
        NSCursor.pop()
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        completion(rect)
    }
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen, onFinish: @escaping @MainActor (LRect?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setFrame(screen.frame, display: false)
        contentView = SelectionView(onFinish: onFinish)
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private let onFinish: @MainActor (LRect?) -> Void
    private var start: NSPoint?
    private var current: NSPoint?

    init(onFinish: @escaping @MainActor (LRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = NSEvent.mouseLocation
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return onFinish(nil) }
        let end = NSEvent.mouseLocation
        onFinish(CaptureGeometry.selection(fromX: start.x, y: start.y, toX: end.x, y: end.y))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(KeyCode.escape) { onFinish(nil) } else { super.keyDown(with: event) }
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let start, let current, let window else { return }
        let a = window.convertPoint(fromScreen: start)
        let b = window.convertPoint(fromScreen: current)
        let rect = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        path.lineWidth = 1
        path.stroke()
    }
}

// MARK: - Pin

/// Floating, movable copy of a capture. Esc or double-click closes it.
@MainActor
final class PinWindow: NSPanel {
    private let onClose: @MainActor (PinWindow) -> Void

    init(image: CGImage, frame selection: LRect, onClose: @escaping @MainActor (PinWindow) -> Void) {
        self.onClose = onClose
        let size = CaptureGeometry.pinSize(width: selection.width, height: selection.height)
        let rect = NSRect(x: selection.x, y: selection.maxY - size.1, width: size.0, height: size.1)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PinImageView(frame: NSRect(origin: .zero, size: rect.size))
        view.image = NSImage(cgImage: image, size: rect.size)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.onDoubleClick = { [weak self] in self?.close() }
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        super.close()
        onClose(self)
    }
}

private final class PinImageView: NSImageView {
    var onDoubleClick: (@MainActor () -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }
}
