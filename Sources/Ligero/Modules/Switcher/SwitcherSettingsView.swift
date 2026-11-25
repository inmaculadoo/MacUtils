import LigeroCore
import SwiftUI

struct SwitcherSettingsView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var recorder = ShortcutRecorder()

    private var settings: SwitcherSettings { model.settings(SwitcherSettings.self, module: SwitcherModule.id) }

    private func update(_ change: (inout SwitcherSettings) -> Void) {
        model.update(SwitcherSettings.self, module: SwitcherModule.id, change)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    ExperimentalBadge()
                    Text(L("switcher.settings.experimentalHint")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("switcher.settings.shortcuts")) {
                HStack {
                    Text(L("switcher.settings.open"))
                    Spacer()
                    ShortcutButton(recorder: recorder, id: "switcher.open", combo: settings.shortcut) { c in update { $0.shortcut = c } }
                }
                HStack {
                    Text(L("switcher.settings.reverse"))
                    Spacer()
                    ShortcutButton(recorder: recorder, id: "switcher.reverse", combo: settings.reverseShortcut) { c in update { $0.reverseShortcut = c } }
                }
            }
            Section(L("switcher.settings.thumbnails")) {
                Toggle(L("switcher.settings.showThumbnails"), isOn: Binding(
                    get: { settings.showThumbnails }, set: { v in update { $0.showThumbnails = v } }
                ))
                Text(L("switcher.settings.thumbnailsHint"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop() }
    }
}
