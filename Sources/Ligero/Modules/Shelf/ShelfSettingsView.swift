import AppKit
import LigeroCore
import SwiftUI

struct ShelfSettingsView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var recorder = ShortcutRecorder()

    private var settings: ShelfSettings { model.settings(ShelfSettings.self, module: ShelfModule.id) }

    var body: some View {
        Form {
            Section(L("shelf.settings.behaviour")) {
                Toggle(L("shelf.settings.showOnDrag"), isOn: Binding(
                    get: { settings.showOnDrag },
                    set: { v in model.update(ShelfSettings.self, module: ShelfModule.id) { $0.showOnDrag = v } }
                ))
                Toggle(L("shelf.settings.showOnNotchHover"), isOn: Binding(
                    get: { settings.showOnNotchHover },
                    set: { v in model.update(ShelfSettings.self, module: ShelfModule.id) { $0.showOnNotchHover = v } }
                ))
                HStack {
                    Text(L("shelf.settings.shortcut"))
                    Spacer()
                    ShortcutButton(recorder: recorder, id: "shelf", combo: settings.shortcut) { combo in
                        model.update(ShelfSettings.self, module: ShelfModule.id) { $0.shortcut = combo }
                    }
                }
            }
            Section(L("shelf.settings.pinned")) {
                if settings.pinnedFolders.isEmpty {
                    Text(L("shelf.settings.pinnedEmpty")).foregroundStyle(.secondary)
                }
                ForEach(settings.pinnedFolders, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 18, height: 18)
                        Text(path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(L("shelf.settings.unpin")) {
                            model.update(ShelfSettings.self, module: ShelfModule.id) { s in s.pinnedFolders.removeAll { $0 == path } }
                        }
                    }
                }
                Button(L("shelf.settings.addFolder")) { addFolder() }
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop() }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("shelf.settings.addFolderPrompt")
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map(\.path)
        model.update(ShelfSettings.self, module: ShelfModule.id) { s in
            for p in paths { s.pin(p) }
        }
    }
}
