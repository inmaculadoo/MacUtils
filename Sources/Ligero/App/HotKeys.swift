import Carbon
import LigeroCore

struct HotKeyToken: Hashable {
    fileprivate let id: UInt32
}

/// Global shortcuts with Carbon `RegisterEventHotKey` (SPEC §2.1): the
/// system delivers only the registered combos, so there is no event tap and
/// no cost while idle. The Carbon event handler exists only while at least
/// one shortcut is registered.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    nonisolated fileprivate static let signature: OSType = 0x4C47_524F // 'LGRO'

    private struct Entry {
        let combo: KeyCombo
        let action: @MainActor () -> Void
        var ref: EventHotKeyRef?
    }

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private var suspended = false

    private init() {}

    var registeredCount: Int { entries.count }

    /// Registers `combo`. Returns nil if macOS refuses it (for example,
    /// another app already owns that shortcut).
    func register(_ combo: KeyCombo, action: @escaping @MainActor () -> Void) -> HotKeyToken? {
        installHandlerIfNeeded()
        let id = nextID
        nextID &+= 1
        var entry = Entry(combo: combo, action: action, ref: nil)
        if !suspended {
            guard let ref = carbonRegister(combo, id: id) else {
                removeHandlerIfUnused()
                return nil
            }
            entry.ref = ref
        }
        entries[id] = entry
        return HotKeyToken(id: id)
    }

    func unregister(_ token: HotKeyToken) {
        guard let entry = entries.removeValue(forKey: token.id) else { return }
        if let ref = entry.ref {
            UnregisterEventHotKey(ref)
        }
        removeHandlerIfUnused()
    }

    /// Releases every combo while the Settings window records a new
    /// shortcut, so that pressing an existing one reaches the recorder.
    func suspend() {
        guard !suspended else { return }
        suspended = true
        for (id, var e) in entries {
            if let ref = e.ref { UnregisterEventHotKey(ref) }
            e.ref = nil
            entries[id] = e
        }
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        for (id, var e) in entries {
            e.ref = carbonRegister(e.combo, id: id)
            entries[id] = e
        }
    }

    fileprivate func fire(_ id: UInt32) {
        entries[id]?.action()
    }

    private func carbonRegister(_ combo: KeyCombo, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers.rawValue,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == OSStatus(noErr), let ref else {
            Log.hotKeys.error("RegisterEventHotKey \(combo.description, privacy: .public) failed: \(status)")
            return nil
        }
        return ref
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &ref)
        if status == OSStatus(noErr) {
            handler = ref
        } else {
            Log.hotKeys.error("InstallEventHandler failed: \(status)")
        }
    }

    private func removeHandlerIfUnused() {
        guard entries.isEmpty, let h = handler else { return }
        RemoveEventHandler(h)
        handler = nil
    }
}

/// Carbon calls this on the main thread.
private func hotKeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKey = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKey
    )
    guard status == OSStatus(noErr), hotKey.signature == HotKeyCenter.signature else {
        return OSStatus(eventNotHandledErr)
    }
    let id = hotKey.id
    MainActor.assumeIsolated {
        HotKeyCenter.shared.fire(id)
    }
    return OSStatus(noErr)
}
