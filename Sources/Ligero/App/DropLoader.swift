import AppKit
import LigeroCore
import UniformTypeIdentifiers

/// Reads dropped files, URLs and text from NSItemProviders (Shelf, Uninstall).
@MainActor
enum DropLoader {
    /// Reads files, URLs and text from drop providers.
    static func load(_ providers: [NSItemProvider], into handler: @escaping @MainActor ([ShelfItem]) -> Void) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url = DropLoader.url(from: item)
                    Task { @MainActor in if let url { handler([.file(path: url.path)]) } }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    let url = DropLoader.url(from: item)
                    Task { @MainActor in if let url { handler([.url(url.absoluteString)]) } }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    let text: String?
                    if let s = item as? String { text = s } else if let d = item as? Data { text = String(data: d, encoding: .utf8) } else { text = nil }
                    Task { @MainActor in if let text { handler([.text(text)]) } }
                }
            }
        }
    }

    nonisolated static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let s = item as? String { return URL(string: s) }
        return nil
    }
}
