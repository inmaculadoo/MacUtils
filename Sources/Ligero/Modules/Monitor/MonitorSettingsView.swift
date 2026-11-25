import LigeroCore
import SwiftUI

struct MonitorSettingsView: View {
    @ObservedObject var model: SettingsModel

    private var settings: MonitorSettings { model.settings(MonitorSettings.self, module: MonitorModule.id) }

    var body: some View {
        Form {
            Section(L("monitor.settings.panel")) {
                Text(L("monitor.settings.panelHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(L("monitor.settings.menuBar")) {
                Toggle(L("monitor.settings.menuBarReading"), isOn: Binding(
                    get: { settings.menuBarReading },
                    set: { v in model.update(MonitorSettings.self, module: MonitorModule.id) { $0.menuBarReading = v } }
                ))
                Stepper(value: Binding(
                    get: { Int(settings.clampedInterval) },
                    set: { v in model.update(MonitorSettings.self, module: MonitorModule.id) { $0.menuBarInterval = Double(v) } }
                ), in: 10...120, step: 5) {
                    Text(L("monitor.settings.interval", Int(settings.clampedInterval)))
                }
                .disabled(!settings.menuBarReading)
                Text(L("monitor.settings.menuBarHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
