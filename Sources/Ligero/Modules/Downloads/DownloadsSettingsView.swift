import AppKit
import LigeroCore
import SwiftUI

struct DownloadsSettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var preview: [PlannedMove]?

    private var settings: DownloadsSettings { model.settings(DownloadsSettings.self, module: DownloadsModule.id) }

    var body: some View {
        Form {
            Section(L("downloads.settings.preview")) {
                Text(L("downloads.settings.previewHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let preview {
                    if preview.isEmpty {
                        Text(L("downloads.settings.previewEmpty")).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(preview.prefix(200).enumerated()), id: \.offset) { _, move in
                                    Text(L("downloads.settings.previewRow", move.source, move.destination))
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 140)
                    }
                }
                HStack {
                    Button(L("downloads.settings.refreshPreview")) { refreshPreview() }
                    Spacer()
                    if settings.previewAccepted {
                        Label(L("downloads.settings.active"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                    } else {
                        Button(L("downloads.settings.accept")) { accept() }
                            .buttonStyle(.borderedProminent)
                            .disabled(preview == nil)
                    }
                }
            }

            Section(L("downloads.settings.categories")) {
                ForEach(DownloadCategory.allCases, id: \.self) { category in
                    HStack {
                        Toggle(L(category.titleKey), isOn: Binding(
                            get: { settings.enabledCategories.contains(category) },
                            set: { on in
                                model.update(DownloadsSettings.self, module: DownloadsModule.id) {
                                    if on { $0.enabledCategories.insert(category) } else { $0.enabledCategories.remove(category) }
                                }
                                preview = nil
                            }
                        ))
                        Spacer()
                        FolderNameField(initial: DownloadsModule.folderNames(settings)[category] ?? "") { name in
                            model.update(DownloadsSettings.self, module: DownloadsModule.id) { s in
                                s.folderNames = DownloadsModule.folderNames(s)
                                s.folderNames[category] = name
                            }
                            preview = nil
                        }
                    }
                }
                Text(L("downloads.settings.neverDeletes"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { if preview == nil { refreshPreview() } }
    }

    /// Reads ~/Downloads off the main thread: the first read can wait on
    /// macOS's folder-access prompt, and that must not freeze the app.
    private func refreshPreview() {
        let settings = settings
        let history = model.store.loadValue(UndoHistory.self, key: DownloadsModule.historyKey) ?? UndoHistory()
        Task {
            preview = await Task.detached(priority: .userInitiated) {
                DownloadsModule.plan(for: DownloadsModule.listEntries().map(\.entry), settings: settings, history: history)
            }.value
        }
    }

    /// Freezes the folder names in the current language, turns sorting on and
    /// sorts what the preview showed.
    private func accept() {
        model.update(DownloadsSettings.self, module: DownloadsModule.id) { s in
            s.folderNames = DownloadsModule.folderNames(s)
            s.previewAccepted = true
        }
        if !model.isEnabled(DownloadsModule.id) {
            model.setModule(DownloadsModule.id, enabled: true)
        }
        (model.registry.module(DownloadsModule.id) as? DownloadsModule)?.sortNow()
        refreshPreview()
    }
}

/// Text field that commits a valid folder name on Return or focus loss.
private struct FolderNameField: View {
    let initial: String
    let commit: @MainActor (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField(L("downloads.settings.folderName"), text: $text)
            .labelsHidden()
            .frame(width: 160)
            .onAppear { text = initial }
            .onSubmit(save)
    }

    private func save() {
        let name = text.trimmingCharacters(in: .whitespaces)
        if DownloadsPlanner.isValidFolderName(name), name != initial {
            commit(name)
        } else {
            text = initial
        }
    }
}
