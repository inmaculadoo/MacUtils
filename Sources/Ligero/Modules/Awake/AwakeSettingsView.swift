import AppKit
import LigeroCore
import SwiftUI

struct AwakeSettingsView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var recorder = ShortcutRecorder()

    private var settings: AwakeSettings { model.settings(AwakeSettings.self, module: AwakeModule.id) }

    var body: some View {
        Form {
            Section(L("awake.settings.behaviour")) {
                Toggle(L("awake.menu.keepDisplayOn"), isOn: Binding(
                    get: { settings.keepDisplayOn },
                    set: { v in model.update(AwakeSettings.self, module: AwakeModule.id) { $0.keepDisplayOn = v } }
                ))
                Text(L("awake.settings.displayHint")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(L("awake.settings.shortcut"))
                    Spacer()
                    ShortcutButton(recorder: recorder, id: "awake", combo: settings.shortcut) { combo in
                        model.update(AwakeSettings.self, module: AwakeModule.id) { $0.shortcut = combo }
                    }
                }
            }
            Section(L("awake.menu.whileOpen")) {
                if settings.triggerApps.isEmpty {
                    Text(L("awake.settings.noApps")).foregroundStyle(.secondary)
                }
                ForEach(settings.triggerApps, id: \.self) { id in
                    HStack {
                        Text(name(id))
                        Spacer()
                        Button(L("awake.settings.remove")) {
                            model.update(AwakeSettings.self, module: AwakeModule.id) { $0.toggleTrigger(id) }
                        }
                    }
                }
                Text(L("awake.settings.appsHint")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop() }
    }

    private func name(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
