import AppKit
import LigeroCore
import SwiftUI

/// Records a new shortcut with a local key monitor that exists only while
/// recording. Carbon hotkeys are suspended meanwhile so an existing combo
/// reaches the recorder instead of moving a window.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var recording: SnapAction?
    private var monitor: Any?
    private var completion: (@MainActor (SnapAction, KeyCombo?) -> Void)?

    func start(_ action: SnapAction, completion: @escaping @MainActor (SnapAction, KeyCombo?) -> Void) {
        stop()
        recording = action
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
        guard let action = recording else { return }
        let modifiers = KeyCombo.Modifiers(cocoaFlags: flags)
        if keyCode == KeyCode.escape && modifiers.isEmpty {
            stop()
            return
        }
        if (keyCode == KeyCode.delete || keyCode == KeyCode.forwardDelete) && modifiers.isEmpty {
            finish(action, nil)
            return
        }
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        guard combo.isValidGlobalShortcut else {
            NSSound.beep()
            return
        }
        finish(action, combo)
    }

    private func finish(_ action: SnapAction, _ combo: KeyCombo?) {
        let completion = self.completion
        stop()
        completion?(action, combo)
    }
}

struct SnapSettingsView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var recorder = ShortcutRecorder()

    private var settings: SnapSettings { model.settings(SnapSettings.self, module: SnapModule.id) }

    var body: some View {
        Form {
            Section(L("settings.snap.shortcuts")) {
                Text(L("settings.snap.shortcutsHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(SnapAction.allCases, id: \.self) { action in
                    HStack {
                        Text(L(action.localizationKey))
                        Spacer()
                        Button(buttonTitle(for: action)) {
                            if recorder.recording == action {
                                recorder.stop()
                            } else {
                                recorder.start(action) { action, combo in
                                    model.update(SnapSettings.self, module: SnapModule.id) { $0.assign(combo, to: action) }
                                }
                            }
                        }
                        .frame(minWidth: 130)
                    }
                }
                Button(L("settings.snap.resetShortcuts")) {
                    recorder.stop()
                    model.update(SnapSettings.self, module: SnapModule.id) { $0.shortcuts = SnapSettings.defaultShortcuts }
                }
            }

            Section(L("settings.snap.behaviour")) {
                Toggle(L("settings.snap.cycleHalves"), isOn: Binding(
                    get: { settings.cycleHalves },
                    set: { value in model.update(SnapSettings.self, module: SnapModule.id) { $0.cycleHalves = value } }
                ))
                HStack {
                    Text(L("settings.snap.gap"))
                    Slider(value: Binding(
                        get: { settings.gap },
                        set: { value in model.update(SnapSettings.self, module: SnapModule.id) { $0.gap = value.rounded() } }
                    ), in: 0...SnapSettings.maxGap, step: 2)
                    Text(L("settings.snap.gapValue", Int(settings.gap)))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        // Also runs when the window closes, so the key monitor never outlives it.
        .onDisappear { recorder.stop() }
    }

    private func buttonTitle(for action: SnapAction) -> String {
        if recorder.recording == action { return L("settings.shortcut.recording") }
        return settings.shortcuts[action]?.description ?? L("settings.shortcut.none")
    }
}
