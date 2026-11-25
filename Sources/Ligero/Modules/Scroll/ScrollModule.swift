import AppKit
import CoreGraphics
import IOKit.hid
import LigeroCore

/// Mouse wheel direction independent of the trackpad, linear scrolling and
/// side buttons as Back/Forward (SPEC §4.2).
///
/// Cost model: IOHIDManager only reports devices being plugged in or removed.
/// The CGEventTap exists only while an external mouse is connected and is
/// removed as soon as the last one goes away.
@MainActor
final class ScrollModule: LigeroModule {
    static let id = "scroll"
    static let requiredPermissions: Set<Permission> = [.accessibility]

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(ScrollModule.self, titleKey: "module.scroll.title", summaryKey: "module.scroll.summary") {
            ScrollModule(context: $0)
        }
    }

    private let settings: ScrollSettings
    private var manager: IOHIDManager?
    private var mice: Set<CFHashCode> = []
    private var tap: EventTap?

    init(context: AppContext) {
        settings = context.settings.load(ScrollSettings.self, module: Self.id)
    }

    func start() {
        guard settings.needsEventTap else {
            Log.scroll.info("All scroll options are off; not watching devices")
            return
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        let matching: [String: Int] = [
            "DeviceUsagePage": HIDDeviceInfo.genericDesktop,
            "DeviceUsage": HIDDeviceInfo.mouseUsage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // Opening a mouse-only manager needs no Input Monitoring permission.
        let result = IOHIDManagerOpen(manager, IOOptionBits(0))
        if result != IOReturn(kIOReturnSuccess) {
            Log.scroll.error("IOHIDManagerOpen failed: \(result)")
        }
        self.manager = manager
    }

    func stop() {
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(0))
        }
        manager = nil
        mice.removeAll()
        removeTap()
    }

    fileprivate func deviceMatched(_ id: CFHashCode, info: HIDDeviceInfo) {
        guard info.isExternalMouse else { return }
        Log.scroll.info("Mouse connected: \(info.product ?? "?", privacy: .public)")
        mice.insert(id)
        updateTap()
    }

    fileprivate func deviceRemoved(_ id: CFHashCode) {
        guard mice.remove(id) != nil else { return }
        Log.scroll.info("Mouse disconnected")
        updateTap()
    }

    private func updateTap() {
        if mice.isEmpty {
            removeTap()
        } else if tap == nil {
            tap = EventTap(settings: settings)
        }
    }

    private func removeTap() {
        tap?.invalidate()
        tap = nil
    }
}

// MARK: - IOHID callbacks (main run loop)

private func deviceInfo(_ device: IOHIDDevice) -> HIDDeviceInfo {
    func property(_ key: String) -> CFTypeRef? { IOHIDDeviceGetProperty(device, key as CFString) }
    return HIDDeviceInfo(
        product: property("Product") as? String,
        transport: property("Transport") as? String,
        builtIn: (property("Built-In") as? NSNumber)?.boolValue ?? false,
        usagePage: (property("PrimaryUsagePage") as? NSNumber)?.intValue ?? HIDDeviceInfo.genericDesktop,
        usage: (property("PrimaryUsage") as? NSNumber)?.intValue ?? HIDDeviceInfo.mouseUsage
    )
}

private func hidDeviceMatched(_ context: UnsafeMutableRawPointer?, _ result: IOReturn,
                              _ sender: UnsafeMutableRawPointer?, _ device: IOHIDDevice) {
    guard let context else { return }
    let module = Unmanaged<ScrollModule>.fromOpaque(context).takeUnretainedValue()
    let id = CFHash(device)
    let info = deviceInfo(device)
    MainActor.assumeIsolated { module.deviceMatched(id, info: info) }
}

private func hidDeviceRemoved(_ context: UnsafeMutableRawPointer?, _ result: IOReturn,
                              _ sender: UnsafeMutableRawPointer?, _ device: IOHIDDevice) {
    guard let context else { return }
    let module = Unmanaged<ScrollModule>.fromOpaque(context).takeUnretainedValue()
    let id = CFHash(device)
    MainActor.assumeIsolated { module.deviceRemoved(id) }
}

// MARK: - Event tap

/// The CGEventTap for wheel and side-button events. It runs on the main run
/// loop and does a few field reads/writes per event: no allocation beyond
/// what CGEvent itself does, no locks.
private final class EventTap {
    private let settings: ScrollSettings
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Side buttons whose mouse-down was swallowed, so the matching
    /// mouse-up is swallowed too.
    private var swallowed: Set<Int64> = []

    init(settings: ScrollSettings) {
        self.settings = settings
        var mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        if settings.sideButtonsNavigate {
            mask |= CGEventMask(1) << CGEventType.otherMouseDown.rawValue
            mask |= CGEventMask(1) << CGEventType.otherMouseUp.rawValue
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.scroll.error("CGEvent.tapCreate failed (Accessibility not granted?)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        Log.scroll.info("Event tap installed")
    }

    func invalidate() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        port = nil
        source = nil
        swallowed.removeAll()
        Log.scroll.info("Event tap removed")
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout:
            // macOS disables a tap that is too slow; turn it back on.
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        case .scrollWheel:
            rewriteScroll(event)
        case .otherMouseDown:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            if let action = MouseButtons.navigation(forButton: button, settings: settings) {
                swallowed.insert(button)
                postNavigation(action)
                return nil
            }
        case .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            if swallowed.remove(button) != nil { return nil }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func rewriteScroll(_ event: CGEvent) {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if continuous { return }
        let input = ScrollDeltas(
            lines1: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            lines2: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            fixed1: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            fixed2: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            point1: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
            point2: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        )
        guard let out = ScrollTransform.transform(input, isContinuous: false, settings: settings) else { return }
        // Line deltas first: setting them makes CoreGraphics recompute the
        // others, which are then overwritten with the exact values.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: out.lines1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: out.lines2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: out.fixed1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: out.fixed2)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: out.point1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: out.point2)
    }

    /// ⌘[ / ⌘], the Back/Forward shortcut of Safari, Finder, Chrome, Xcode…
    /// The Unicode string is set explicitly so it works on non-US layouts.
    private func postNavigation(_ action: NavigationAction) {
        let keyCode = CGKeyCode(action == .back ? KeyCode.leftBracket : KeyCode.rightBracket)
        var character: UniChar = action == .back ? 0x5B : 0x5D
        for down in [true, false] {
            guard let key = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            key.flags = .maskCommand
            key.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
            key.post(tap: .cghidEventTap)
        }
    }
}

private func scrollTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handle(type, event)
}
