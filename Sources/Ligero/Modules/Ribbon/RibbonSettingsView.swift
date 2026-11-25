import AppKit
import LigeroCore
import SwiftUI

struct RibbonSettingsView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var recorder = ShortcutRecorder()

    private var settings: RibbonSettings { model.settings(RibbonSettings.self, module: RibbonModule.id) }

    private func update(_ change: (inout RibbonSettings) -> Void) {
        model.update(RibbonSettings.self, module: RibbonModule.id, change)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    ExperimentalBadge()
                    Text(L("ribbon.settings.experimentalHint")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section(L("ribbon.settings.shortcuts")) {
                ForEach(RibbonAction.allCases, id: \.self) { action in
                    HStack {
                        Text(L(action.localizationKey))
                        Spacer()
                        ShortcutButton(recorder: recorder, id: "ribbon." + action.rawValue, combo: settings.shortcuts[action]) { c in
                            update { $0.assign(c, to: action) }
                        }
                    }
                }
            }
            Section(L("ribbon.settings.layout")) {
                Picker(L("ribbon.settings.defaultWidth"), selection: Binding(
                    get: { settings.defaultWidth }, set: { v in update { $0.defaultWidth = v } }
                )) {
                    ForEach(ColumnWidth.allCases, id: \.self) { w in
                        Text(L(w.titleKey)).tag(w)
                    }
                }
                HStack {
                    Text(L("ribbon.settings.gap"))
                    Slider(value: Binding(get: { settings.gap }, set: { v in update { $0.gap = v.rounded() } }), in: 0...40, step: 2)
                    Text(L("settings.snap.gapValue", Int(settings.gap))).monospacedDigit().frame(width: 50, alignment: .trailing)
                }
                Toggle(L("ribbon.settings.gesture"), isOn: Binding(
                    get: { settings.gestureScroll }, set: { v in update { $0.gestureScroll = v } }
                ))
            }
            Section(L("ribbon.settings.excluded")) {
                if settings.excludedApps.isEmpty {
                    Text(L("ribbon.settings.excludedEmpty")).foregroundStyle(.secondary)
                }
                ForEach(settings.excludedApps, id: \.self) { bundle in
                    HStack {
                        Text(bundle).font(.caption.monospaced())
                        Spacer()
                        Button(L("shelf.settings.unpin")) { update { s in s.excludedApps.removeAll { $0 == bundle } } }
                    }
                }
                Button(L("ribbon.settings.addExcluded")) { addExcluded() }
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop() }
    }

    private func addExcluded() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        update { s in
            for id in ids where !s.excludedApps.contains(id) { s.excludedApps.append(id) }
        }
    }
}
