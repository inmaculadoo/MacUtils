import AppKit
import ApplicationServices
import LigeroCore

/// Windows in a horizontal strip per display (SPEC §4.12). EXPERIMENTAL.
///
/// The module itself only registers hotkeys. The tiling mode is switched on
/// with a shortcut; only then does it use the WindowService events (window
/// created/destroyed, focus) and move windows by AX. When the mode is turned
/// off, every window goes back to the frame it had before.
///
/// All placement math is the tested `RibbonStrip` model in LigeroCore; this
/// file only reads/writes AX frames, and only for windows whose target changed.
@MainActor
final class RibbonModule: LigeroModule, MenuContributing {
    static let id = "ribbon"
    static let requiredPermissions: Set<Permission> = [.accessibility]

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(RibbonModule.self, titleKey: "module.ribbon.title", summaryKey: "module.ribbon.summary",
                         experimental: true) { RibbonModule(context: $0) }
    }

    private let context: AppContext
    private let settings: RibbonSettings
    private let service = WindowService.shared
    private var tokens: [HotKeyToken] = []

    private var active = false
    /// One strip per display, keyed by the display's frame (AX coordinates).
    private var strips: [LRect: RibbonStrip<CGWindowID>] = [:]
    private var elements: [CGWindowID: AXUIElement] = [:]
    private var original: [CGWindowID: LRect] = [:]
    private var applied: [CGWindowID: LRect] = [:]
    private var gesture: RibbonGestureTap?
    /// Tiled windows the user moved or resized with the mouse button down.
    /// They are read once, when the button comes up (SPEC §4.12: no polling).
    private var dragged: Set<CGWindowID> = []
    /// Exists only between a drag of a tiled window and its mouse-up.
    private var mouseUpMonitor: Any?
    /// Times a parked window was pushed back after its app pulled it on
    /// screen (AppKit does that on activation). Capped so an app that keeps
    /// fighting can't start a loop; reset whenever the layout moves it.
    private var reparks: [CGWindowID: Int] = [:]
    /// Windows just dropped by the user. macOS may still move them after the
    /// mouse-up (its own tiling); they are put back in their slot too.
    private var settling: Set<CGWindowID> = []
    /// Windows taken out of the strip (float shortcut, or placed with Snap).
    /// Ribbon leaves them alone until they are floated back in.
    private var floating: Set<CGWindowID> = []
    /// Observes Snap placing a window; exists only while the mode is on.
    private var placedObserver: NSObjectProtocol?
    /// Horizontal gesture distance not applied yet: windows move only every
    /// `gestureStep` points, not on each scroll event (each move is AX calls
    /// to every visible window).
    private var pendingScroll: Double = 0
    private let gestureStep: Double = 24

    init(context: AppContext) {
        self.context = context
        settings = context.settings.load(RibbonSettings.self, module: Self.id)
    }

    func start() {
        for action in RibbonAction.allCases {
            guard let combo = settings.shortcuts[action] else { continue }
            if let t = context.hotKeys.register(combo, action: { [weak self] in self?.perform(action) }) { tokens.append(t) }
        }
    }

    func stop() {
        if active { deactivate() }
        for t in tokens { context.hotKeys.unregister(t) }
        tokens.removeAll()
    }

    func menuItems() -> [NSMenuItem] {
        let title = active ? L("ribbon.menu.turnOff") : L("ribbon.menu.turnOn")
        let toggle = ClosureMenuItem(title: title) { [weak self] in self?.perform(.toggleMode) }
        toggle.showShortcut(settings.shortcuts[.toggleMode])
        guard active else { return [toggle] }
        var items: [NSMenuItem] = [toggle]
        // Read once, now: the focused window of the app in front.
        let front = NSWorkspace.shared.frontmostApplication.flatMap { focusedWindowID($0.processIdentifier) }
        let titles = Dictionary(service.windows().map { ($0.id, $0.appName.isEmpty ? $0.title : L("ribbon.menu.windowName", $0.appName, $0.title)) },
                                uniquingKeysWith: { a, _ in a })
        let keys = strips.keys.sorted { $0.minX != $1.minX ? $0.minX < $1.minX : $0.minY < $1.minY }
        for key in keys {
            guard let strip = strips[key], !strip.isEmpty else { continue }
            items.append(.separator())
            items.append(NSMenuItem.sectionHeader(title: L("ribbon.menu.columns")))
            for (c, column) in strip.columns.enumerated() {
                for (r, id) in column.windows.enumerated() {
                    let name = titles[id] ?? "#\(id)"
                    let label = r == 0 ? L("ribbon.menu.column", c + 1, name) : L("ribbon.menu.stacked", name)
                    let item = ClosureMenuItem(title: label) { [weak self] in self?.reveal(id) }
                    item.state = id == front ? .on : .off
                    items.append(item)
                }
            }
        }
        if let front {
            items.append(.separator())
            items.append(windowMenu(for: front))
        }
        return items
    }

    /// "This window" submenu: width, position, stack and float.
    private func windowMenu(for id: CGWindowID) -> NSMenuItem {
        let root = NSMenuItem(title: L("ribbon.menu.window"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        func add(_ title: String, _ action: RibbonAction? = nil, _ run: @escaping @MainActor () -> Void) {
            let item = ClosureMenuItem(title: title, handler: run)
            if let action { item.showShortcut(settings.shortcuts[action]) }
            sub.addItem(item)
        }
        if floating.contains(id) {
            add(L("ribbon.menu.unfloat"), .toggleFloat) { [weak self] in self?.edit(id) { $0.toggleFloat(id) } }
            root.submenu = sub
            return root
        }
        guard let key = stripKey(containing: id), let strip = strips[key], let p = strip.position(of: id) else {
            root.isEnabled = false
            return root
        }
        let widths = NSMenuItem(title: L("ribbon.menu.width"), action: nil, keyEquivalent: "")
        let widthMenu = NSMenu()
        for w in ColumnWidth.allCases {
            let item = ClosureMenuItem(title: L(w.titleKey)) { [weak self] in
                self?.edit(id) { m in m.change(id) { $0.setWidth(w) } }
            }
            item.state = strip.columns[p.column].customPoints == nil && strip.columns[p.column].width == w ? .on : .off
            widthMenu.addItem(item)
        }
        widths.submenu = widthMenu
        sub.addItem(widths)

        let stacked = strip.columns[p.column].windows.count > 1
        let slots = strip.columns.count + (stacked ? 1 : 0)
        if slots > 1 {
            let position = NSMenuItem(title: L("ribbon.menu.position"), action: nil, keyEquivalent: "")
            let positionMenu = NSMenu()
            for i in 0..<slots {
                let item = ClosureMenuItem(title: L("ribbon.menu.slot", i + 1)) { [weak self] in
                    self?.edit(id) { m in m.change(id) { $0.apply(.moved(toColumn: i), to: id) } }
                }
                item.state = !stacked && i == p.column ? .on : .off
                positionMenu.addItem(item)
            }
            position.submenu = positionMenu
            sub.addItem(position)
        }
        sub.addItem(.separator())
        add(L(RibbonAction.moveLeft.localizationKey), .moveLeft) { [weak self] in self?.perform(.moveLeft, window: id) }
        add(L(RibbonAction.moveRight.localizationKey), .moveRight) { [weak self] in self?.perform(.moveRight, window: id) }
        if p.column > 0 {
            add(L(RibbonAction.stackLeft.localizationKey), .stackLeft) { [weak self] in self?.perform(.stackLeft, window: id) }
        }
        if stacked {
            add(L(RibbonAction.expel.localizationKey), .expel) { [weak self] in self?.perform(.expel, window: id) }
        }
        if strips.count > 1 {
            add(L(RibbonAction.sendToNextScreen.localizationKey), .sendToNextScreen) { [weak self] in
                self?.perform(.sendToNextScreen, window: id)
            }
        }
        sub.addItem(.separator())
        add(L("ribbon.menu.float"), .toggleFloat) { [weak self] in self?.edit(id) { $0.toggleFloat(id) } }
        root.submenu = sub
        return root
    }

    /// Runs a menu edit only if the mode is still on when the item fires.
    private func edit(_ id: CGWindowID, _ body: (RibbonModule) -> Void) {
        guard active else { return }
        body(self)
    }

    /// Applies `body` to the strip holding `id`, lays it out and focuses `id`.
    private func change(_ id: CGWindowID, _ body: (inout RibbonStrip<CGWindowID>) -> Void) {
        guard let key = stripKey(containing: id), var strip = strips[key] else { return }
        strip.focusWindow(id)
        body(&strip)
        strips[key] = strip
        layout(strip)
        focus(id)
    }

    /// Scrolls the strip to `id` and focuses it (menu column list).
    private func reveal(_ id: CGWindowID) {
        guard active else { return }
        change(id) { _ in }
    }

    // MARK: Mode

    private func activate() {
        active = true
        service.acquire(self) { [weak self] event in self?.windowEvent(event) }
        let screens = ScreenGeometry.screens()
        let frames = screens.map(\.frame)
        strips.removeAll()
        for s in screens {
            var strip = RibbonStrip<CGWindowID>(viewport: s.visibleFrame, gap: settings.gap, defaultWidth: settings.defaultWidth)
            let n = RibbonScreens.neighbours(of: s.frame, among: frames)
            strip.canParkLeft = !n.left
            strip.canParkRight = !n.right
            strips[s.frame] = strip
        }
        var perScreen: [LRect: [(id: CGWindowID, frame: LRect)]] = [:]
        for w in service.windows(includeMinimized: false) where isTileable(w) {
            // Fresh frame: it is what the windows go back to when the mode ends.
            guard let frame = WindowService.frame(w.element) ?? w.frame,
                  let screen = screenFrame(for: frame, screens) else { continue }
            elements[w.id] = w.element
            original[w.id] = frame
            applied[w.id] = frame
            perScreen[screen, default: []].append((id: w.id, frame: frame))
        }
        for (screen, windows) in perScreen {
            guard var strip = strips[screen] else { continue }
            let adopted = RibbonStrip<CGWindowID>.adopting(windows, viewport: strip.viewport, gap: settings.gap)
            for column in adopted.columns { strip.insert(column.windows[0], width: column.width) }
            strips[screen] = strip
        }
        placedObserver = NotificationCenter.default.addObserver(forName: .ligeroWindowPlaced, object: nil, queue: nil) {
            [weak self] note in
            guard let id = (note.object as? NSNumber)?.uint32Value else { return }
            MainActor.assumeIsolated { self?.letGo(CGWindowID(id)) }
        }
        if settings.gestureScroll {
            gesture = RibbonGestureTap { [weak self] dx in self?.gestureScroll(dx) ?? false }
        }
        layoutAll()
        Log.modules.info("Ribbon on: \(self.elements.count) windows")
    }

    private func deactivate() {
        gesture?.invalidate()
        gesture = nil
        if let placedObserver { NotificationCenter.default.removeObserver(placedObserver) }
        placedObserver = nil
        pendingScroll = 0
        endDragWatch()
        // Put every window back where it was before the mode started.
        for (id, frame) in original {
            if let e = elements[id] { WindowService.setFrame(e, frame) }
        }
        service.release(self)
        strips.removeAll()
        elements.removeAll()
        original.removeAll()
        applied.removeAll()
        reparks.removeAll()
        settling.removeAll()
        floating.removeAll()
        active = false
        Log.modules.info("Ribbon off")
    }

    private func isTileable(_ w: WindowInfo) -> Bool {
        guard !w.isMinimized, !floating.contains(w.id), let bundle = w.app?.bundleIdentifier else { return false }
        return !settings.excludedApps.contains(bundle) && bundle != Bundle.main.bundleIdentifier
    }

    private func screenFrame(for window: LRect, _ screens: [ScreenInfo]) -> LRect? {
        guard !screens.isEmpty else { return nil }
        return screens[SnapEngine.screenIndex(for: window, in: screens)].frame
    }

    // MARK: Layout

    /// Moves only the windows whose target frame changed.
    private func layoutAll() {
        for strip in strips.values { layout(strip) }
    }

    private func layout(_ strip: RibbonStrip<CGWindowID>) {
        let target = strip.layout()
        for id in RibbonStrip<CGWindowID>.windowsToMove(current: applied, target: target) {
            guard let e = elements[id], let placement = target[id] else { continue }
            WindowService.setFrame(e, placement.frame)
            applied[id] = placement.frame
            reparks[id] = nil
        }
    }

    private func stripKey(containing id: CGWindowID) -> LRect? {
        strips.first { $0.value.position(of: id) != nil }?.key
    }

    /// The strip of the focused window, or of the display under the mouse.
    private func currentStripKey() -> LRect? {
        if let front = NSWorkspace.shared.frontmostApplication,
           let id = focusedWindowID(front.processIdentifier), let key = stripKey(containing: id) {
            return key
        }
        let mouse = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return strips.keys.first }
        let p = CoordinateSpace.topLeft(fromCocoa: LRect(x: mouse.x, y: mouse.y, width: 0, height: 0),
                                        primaryHeight: Double(primary.frame.height))
        return strips.keys.first { $0.contains(x: p.x, y: p.y) } ?? strips.keys.first
    }

    private func focusedWindowID(_ pid: pid_t) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(WindowService.appElement(pid), kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return WindowService.windowID(value as! AXUIElement)
    }

    // MARK: Actions

    private func perform(_ action: RibbonAction, window: CGWindowID? = nil) {
        if action == .toggleMode {
            active ? deactivate() : activate()
            return
        }
        guard active else { return }
        if action == .toggleFloat {
            if let id = window ?? NSWorkspace.shared.frontmostApplication.flatMap({ focusedWindowID($0.processIdentifier) }) {
                toggleFloat(id)
            }
            return
        }
        guard let key = window.flatMap(stripKey(containing:)) ?? currentStripKey(), var strip = strips[key] else { return }
        if let window { strip.focusWindow(window) }
        var focusAfter: CGWindowID?
        switch action {
        case .toggleMode, .toggleFloat: return
        case .focusLeft: focusAfter = strip.focusLeft()
        case .focusRight: focusAfter = strip.focusRight()
        case .focusUp: focusAfter = strip.focusUp()
        case .focusDown: focusAfter = strip.focusDown()
        case .moveLeft: strip.moveColumnLeft()
        case .moveRight: strip.moveColumnRight()
        case .cycleWidth: strip.cycleWidth()
        case .cycleWidthBack: strip.cycleWidth(backwards: true)
        case .stackLeft: strip.stackIntoLeft()
        case .expel: strip.expel()
        case .sendToNextScreen:
            sendToNextScreen(from: key, strip: &strip)
            return
        }
        strips[key] = strip
        layout(strip)
        if let id = focusAfter { focus(id) }
    }

    private func sendToNextScreen(from key: LRect, strip: inout RibbonStrip<CGWindowID>) {
        let keys = strips.keys.sorted { $0.minX != $1.minX ? $0.minX < $1.minX : $0.minY < $1.minY }
        guard keys.count > 1, let i = keys.firstIndex(of: key), let id = strip.focusedWindow else { return }
        let width = strip.columns[strip.focus!.column].width
        strip.remove(id)
        strips[key] = strip
        let destinationKey = keys[(i + 1) % keys.count]
        guard var destination = strips[destinationKey] else { return }
        destination.insert(id, width: width)
        strips[destinationKey] = destination
        layout(strip)
        layout(destination)
        focus(id)
    }

    private func focus(_ id: CGWindowID) {
        guard let e = elements[id] else { return }
        AXUIElementPerformAction(e, kAXRaiseAction as CFString)
        var pid: pid_t = 0
        AXUIElementGetPid(e, &pid)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    // MARK: Events

    private func windowEvent(_ event: WindowEvent) {
        guard active else { return }
        switch event {
        case .created(let pid, let element):
            guard WindowService.isStandardWindow(element), let id = WindowService.windowID(element),
                  let app = NSRunningApplication(processIdentifier: pid),
                  let bundle = app.bundleIdentifier, !settings.excludedApps.contains(bundle),
                  !floating.contains(id) else { return }
            if let key = add(id, element: element) { layout(strips[key]!) }
        case .destroyed(_, let id):
            if let id { floating.remove(id) }
            guard let id, let key = stripKey(containing: id), var strip = strips[key] else { return }
            strip.remove(id)
            strips[key] = strip
            elements.removeValue(forKey: id)
            original.removeValue(forKey: id)
            applied.removeValue(forKey: id)
            dragged.remove(id)
            reparks.removeValue(forKey: id)
            settling.remove(id)
            layout(strip)
        case .focused(let pid):
            // "Window created" is lost for apps that did not answer AX yet when
            // they opened it (just launched): pick those windows up now.
            var touched = Set(adoptMissing(pid))
            defer { for key in touched { layout(strips[key]!) } }
            guard let id = focusedWindowID(pid), let key = stripKey(containing: id), var strip = strips[key] else { return }
            touched.remove(key)
            strip.focusWindow(id)
            strips[key] = strip
            layout(strip)
        case .appTerminated:
            // Each window also posts "destroyed"; prune anything left over.
            let live = Set(service.windows().map(\.id))
            floating.formIntersection(live)
            for (key, var strip) in strips {
                for id in strip.windowIDs where !live.contains(id) {
                    strip.remove(id)
                    elements.removeValue(forKey: id)
                    original.removeValue(forKey: id)
                    applied.removeValue(forKey: id)
                    reparks.removeValue(forKey: id)
                }
                strips[key] = strip
                layout(strip)
            }
        case .changed(_, let id):
            guard let id, let e = elements[id] else { return }
            guard NSEvent.pressedMouseButtons & 1 != 0 else {
                repark(id, e)
                return
            }
            settling.removeAll()
            dragged.insert(id)
            if mouseUpMonitor == nil {
                mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dragEnded() }
                }
            }
        }
    }

    /// Adds a window to the strip of its display, right of the focused column.
    /// Returns that strip's key, or nil if it was already tiled or off-screen.
    @discardableResult
    private func add(_ id: CGWindowID, element: AXUIElement) -> LRect? {
        guard elements[id] == nil, let frame = WindowService.frame(element),
              let key = screenFrame(for: frame, ScreenGeometry.screens()), var strip = strips[key] else { return nil }
        elements[id] = element
        original[id] = frame
        applied[id] = frame
        // New windows open to the right of the focused one (SPEC §4.12).
        strip.insert(id)
        strips[key] = strip
        return key
    }

    /// Tiles every visible window of `pid` that the strip doesn't have yet.
    private func adoptMissing(_ pid: pid_t) -> [LRect] {
        let onScreen = WindowService.onScreenWindowIDs()
        var keys: [LRect] = []
        for w in service.windows(ofApp: pid) where elements[w.id] == nil && onScreen.contains(w.id) && isTileable(w) {
            if let key = add(w.id, element: w.element) { keys.append(key) }
        }
        return keys
    }

    // MARK: Floating

    /// Takes a tiled window out of the strip where it is, or puts a floating
    /// one back in (right of the focused column).
    private func toggleFloat(_ id: CGWindowID) {
        if floating.contains(id) {
            floating.remove(id)
            guard let e = service.windows().first(where: { $0.id == id })?.element,
                  let key = add(id, element: e) else { return }
            layout(strips[key]!)
            focus(id)
        } else {
            letGo(id)
        }
    }

    /// Stops tiling `id` and leaves it where it is: it won't go back to its
    /// pre-mode frame either, the user has placed it.
    private func letGo(_ id: CGWindowID) {
        guard active, let key = stripKey(containing: id), var strip = strips[key] else { return }
        let parked = strip.layout()[id]?.state != .visible
        strip.remove(id)
        strips[key] = strip
        floating.insert(id)
        if parked, let e = elements[id], let frame = original[id] { WindowService.setFrame(e, frame) }
        elements.removeValue(forKey: id)
        original.removeValue(forKey: id)
        applied.removeValue(forKey: id)
        dragged.remove(id)
        reparks.removeValue(forKey: id)
        settling.remove(id)
        layout(strip)
    }

    // MARK: Mouse

    /// The user let go of a tiled window they dragged: a new width sticks to
    /// its column, a move reorders the strip, and everything snaps into place.
    private func dragEnded() {
        let ids = dragged
        endDragWatch()
        guard active else { return }
        var touched = Set<LRect>()
        for id in ids {
            guard let e = elements[id], let frame = WindowService.frame(e),
                  let key = stripKey(containing: id), var strip = strips[key],
                  strip.layout()[id]?.state == .visible else { continue }
            let edit = strip.userEdit(id, frame: frame)
            Log.modules.debug("Ribbon drop \(id): \(String(describing: edit))")
            strip.apply(edit, to: id)
            strips[key] = strip
            applied[id] = frame // where it really is, so the layout puts it back
            touched.insert(key)
            settling.insert(id)
        }
        for key in touched { layout(strips[key]!) }
    }

    /// Puts a parked window back at the edge if its app moved it on screen,
    /// and a just-dropped window back in its slot.
    private func repark(_ id: CGWindowID, _ e: AXUIElement) {
        guard let key = stripKey(containing: id), let placement = strips[key]?.layout()[id],
              placement.state != .visible || settling.contains(id), reparks[id, default: 0] < 3,
              let frame = WindowService.frame(e), !frame.isClose(to: placement.frame, tolerance: 2) else { return }
        reparks[id, default: 0] += 1
        Log.modules.debug("Ribbon repark \(id)")
        WindowService.setFrame(e, placement.frame)
        applied[id] = placement.frame
    }

    private func endDragWatch() {
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        mouseUpMonitor = nil
        dragged.removeAll()
    }

    /// ⌥ + horizontal two-finger scroll. Returns true to swallow the event.
    private func gestureScroll(_ dx: Double) -> Bool {
        guard active, let key = currentStripKey(), var strip = strips[key] else { return false }
        pendingScroll -= dx
        guard abs(pendingScroll) >= gestureStep else { return true }
        strip.scroll(by: pendingScroll)
        pendingScroll = 0
        strips[key] = strip
        layout(strip)
        return true
    }
}

/// Event tap for the optional ⌥ + horizontal scroll gesture. Exists only
/// while the Ribbon mode is on and the option is enabled.
@MainActor
private final class RibbonGestureTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate let handler: @MainActor (Double) -> Bool

    init(handler: @escaping @MainActor (Double) -> Bool) {
        self.handler = handler
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: ribbonGestureCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.port = port
        self.source = source
    }

    func invalidate() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }

    fileprivate func reenable() {
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }
}

private func ribbonGestureCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                   refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<RibbonGestureTap>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel, event.flags.contains(.maskAlternate),
          event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else { return Unmanaged.passUnretained(event) }
    let dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
    let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
    guard abs(dx) > abs(dy) else { return Unmanaged.passUnretained(event) }
    let swallow = MainActor.assumeIsolated { tap.handler(dx) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
