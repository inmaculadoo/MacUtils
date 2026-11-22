import LigeroCore
import SwiftUI

struct ScrollSettingsView: View {
    @ObservedObject var model: SettingsModel

    private var settings: ScrollSettings { model.settings(ScrollSettings.self, module: ScrollModule.id) }

    private enum Flag {
        case invertVertical, invertHorizontal, linear, sideButtons, swapSideButtons
    }

    private func binding(_ flag: Flag) -> Binding<Bool> {
        Binding(
            get: {
                let s = settings
                switch flag {
                case .invertVertical: return s.invertVertical
                case .invertHorizontal: return s.invertHorizontal
                case .linear: return s.linear
                case .sideButtons: return s.sideButtonsNavigate
                case .swapSideButtons: return s.swapSideButtons
                }
            },
            set: { value in
                model.update(ScrollSettings.self, module: ScrollModule.id) { s in
                    switch flag {
                    case .invertVertical: s.invertVertical = value
                    case .invertHorizontal: s.invertHorizontal = value
                    case .linear: s.linear = value
                    case .sideButtons: s.sideButtonsNavigate = value
                    case .swapSideButtons: s.swapSideButtons = value
                    }
                }
            }
        )
    }

    var body: some View {
        Form {
            Section(L("settings.scroll.direction")) {
                Toggle(L("settings.scroll.invertVertical"), isOn: binding(.invertVertical))
                Toggle(L("settings.scroll.invertHorizontal"), isOn: binding(.invertHorizontal))
                Text(L("settings.scroll.directionHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L("settings.scroll.speed")) {
                Toggle(L("settings.scroll.linear"), isOn: binding(.linear))
                Stepper(value: Binding(
                    get: { settings.clampedLines },
                    set: { value in model.update(ScrollSettings.self, module: ScrollModule.id) { $0.linesPerTick = value } }
                ), in: ScrollSettings.linesRange) {
                    Text(L("settings.scroll.linesPerTick", settings.clampedLines))
                }
                .disabled(!settings.linear)
            }

            Section(L("settings.scroll.buttons")) {
                Toggle(L("settings.scroll.sideButtons"), isOn: binding(.sideButtons))
                Toggle(L("settings.scroll.swapSideButtons"), isOn: binding(.swapSideButtons))
                    .disabled(!settings.sideButtonsNavigate)
            }

            Section {
                Text(L("settings.scroll.costHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
