import AppKit
import LigeroCore
import SwiftUI

/// Records a new shortcut with a local key monitor that exists only while
/// recording. Carbon hotkeys are suspended meanwhile so that an existing combo
/// reaches the recorder instead of triggering its action.
@MainActor
final class ShortcutRecorder: ObservableObject {
    /// Id of the shortcut being recorded.
    @Published private(set) var recording: String?
    private var monitor: Any?
    private var completion: (@MainActor (KeyCombo?) -> Void)?

    func start(_ id: String, completion: @escaping @MainActor (KeyCombo?) -> Void) {
        stop()
        recording = id
        self.completion = completion
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = UInt32(event.keyCode)
            let flags = event.modifierFlags.rawValue
            MainActor.assumeIsolated { self?.handle(keyCode: keyCode, flags: flags) }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil { HotKeyCenter.shared.resume() }
        recording = nil
        completion = nil
    }

    private func handle(keyCode: UInt32, flags: UInt) {
        guard recording != nil else { return }
        let modifiers = KeyCombo.Modifiers(cocoaFlags: flags)
        if keyCode == KeyCode.escape && modifiers.isEmpty {
            stop()
            return
        }
        if (keyCode == KeyCode.delete || keyCode == KeyCode.forwardDelete) && modifiers.isEmpty {
            finish(nil)
            return
        }
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        guard combo.isValidGlobalShortcut else {
            NSSound.beep()
            return
        }
        finish(combo)
    }

    private func finish(_ combo: KeyCombo?) {
        let completion = self.completion
        stop()
        completion?(combo)
    }
}

/// Button that shows a shortcut and records a new one when clicked.
struct ShortcutButton: View {
    @ObservedObject var recorder: ShortcutRecorder
    let id: String
    let combo: KeyCombo?
    let onChange: @MainActor (KeyCombo?) -> Void

    var body: some View {
        Button(title) {
            if recorder.recording == id {
                recorder.stop()
            } else {
                recorder.start(id) { onChange($0) }
            }
        }
        .frame(minWidth: 130)
    }

    private var title: String {
        if recorder.recording == id { return L("settings.shortcut.recording") }
        return combo?.description ?? L("settings.shortcut.none")
    }
}
