import LigeroCore
import SwiftUI

struct CaptureSettingsView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var recorder = ShortcutRecorder()

    private var settings: CaptureSettings { model.settings(CaptureSettings.self, module: CaptureModule.id) }

    private func update(_ change: (inout CaptureSettings) -> Void) {
        model.update(CaptureSettings.self, module: CaptureModule.id, change)
    }

    var body: some View {
        Form {
            Section(L("capture.settings.shortcuts")) {
                row("capture.menu.region", id: "capture.region", combo: settings.regionShortcut) { c in update { $0.regionShortcut = c } }
                row("capture.menu.text", id: "capture.text", combo: settings.textShortcut) { c in update { $0.textShortcut = c } }
                row("capture.menu.pin", id: "capture.pin", combo: settings.pinShortcut) { c in update { $0.pinShortcut = c } }
            }
            Section(L("capture.settings.output")) {
                Toggle(L("capture.settings.clipboard"), isOn: Binding(
                    get: { settings.copyToClipboard }, set: { v in update { $0.copyToClipboard = v } }
                ))
                Toggle(L("capture.settings.desktop"), isOn: Binding(
                    get: { settings.saveToDesktop }, set: { v in update { $0.saveToDesktop = v } }
                ))
                Text(L("capture.settings.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop() }
    }

    private func row(_ key: String, id: String, combo: KeyCombo?, onChange: @escaping @MainActor (KeyCombo?) -> Void) -> some View {
        HStack {
            Text(L(key))
            Spacer()
            ShortcutButton(recorder: recorder, id: id, combo: combo, onChange: onChange)
        }
    }
}
