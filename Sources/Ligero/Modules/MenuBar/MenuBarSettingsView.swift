import LigeroCore
import SwiftUI

struct MenuBarSettingsView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var recorder = ShortcutRecorder()

    private var settings: MenuBarSettings { model.settings(MenuBarSettings.self, module: MenuBarModule.id) }

    private func update(_ change: (inout MenuBarSettings) -> Void) {
        model.update(MenuBarSettings.self, module: MenuBarModule.id, change)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    ExperimentalBadge()
                    Text(L("menubar.settings.experimentalHint")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section(L("menubar.settings.howTo")) {
                Text(L("menubar.settings.howToText"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(L("menubar.settings.behaviour")) {
                HStack {
                    Text(L("menubar.settings.shortcut"))
                    Spacer()
                    ShortcutButton(recorder: recorder, id: "menubar", combo: settings.shortcut) { c in update { $0.shortcut = c } }
                }
                Toggle(L("menubar.settings.autoHide"), isOn: Binding(
                    get: { settings.autoHide }, set: { v in update { $0.autoHide = v } }
                ))
                Toggle(L("menubar.settings.alwaysHidden"), isOn: Binding(
                    get: { settings.alwaysHiddenSection }, set: { v in update { $0.alwaysHiddenSection = v } }
                ))
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop() }
    }
}
