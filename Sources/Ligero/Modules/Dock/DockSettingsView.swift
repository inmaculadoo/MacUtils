import LigeroCore
import SwiftUI

struct DockSettingsView: View {
    @ObservedObject var model: SettingsModel

    private var settings: DockSettings { model.settings(DockSettings.self, module: DockModule.id) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    ExperimentalBadge()
                    Text(L("dock.settings.experimentalHint")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("dock.settings.previews")) {
                Toggle(L("dock.settings.showPreviews"), isOn: Binding(
                    get: { settings.showPreviews },
                    set: { v in model.update(DockSettings.self, module: DockModule.id) { $0.showPreviews = v } }
                ))
            }
            Section(L("dock.settings.click")) {
                Picker(L("dock.settings.clickAction"), selection: Binding(
                    get: { settings.clickAction },
                    set: { v in model.update(DockSettings.self, module: DockModule.id) { $0.clickAction = v } }
                )) {
                    ForEach(DockSettings.ClickAction.allCases, id: \.self) { a in
                        Text(L(a.titleKey)).tag(a)
                    }
                }
                Text(L("dock.settings.clickHint"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
