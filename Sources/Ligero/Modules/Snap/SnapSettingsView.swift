import LigeroCore
import SwiftUI

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
                        ShortcutButton(recorder: recorder, id: action.rawValue, combo: settings.shortcuts[action]) { combo in
                            model.update(SnapSettings.self, module: SnapModule.id) { $0.assign(combo, to: action) }
                        }
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
}
