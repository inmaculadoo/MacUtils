import Foundation

/// Finds the files an app leaves in ~/Library (SPEC §4.8). Pure logic: the
/// caller provides directory listings, so it is tested without touching disk.
public enum LeftoverFinder {
    /// ~/Library subfolders that are searched, relative to the home folder.
    public static let libraryFolders = [
        "Library/Application Support", "Library/Caches", "Library/Preferences", "Library/Containers",
        "Library/Group Containers", "Library/Saved Application State", "Library/LaunchAgents",
        "Library/Logs", "Library/HTTPStorages", "Library/WebKit", "Library/Cookies",
        "Library/Application Scripts", "Library/Preferences/ByHost",
    ]

    public struct App: Equatable, Sendable {
        public var bundleID: String
        /// CFBundleName / display name / .app file name without extension.
        public var names: [String]
        public var path: String

        public init(bundleID: String, names: [String], path: String) {
            self.bundleID = bundleID
            self.names = names
            self.path = path
        }
    }

    public enum Refusal: Equatable, Sendable {
        /// Apple apps and system locations are never uninstalled.
        case systemApp
        case missingBundleID
    }

    public static func refusal(for app: App) -> Refusal? {
        let id = app.bundleID.trimmingCharacters(in: .whitespaces)
        if id.isEmpty { return .missingBundleID }
        if id.lowercased().hasPrefix("com.apple.") { return .systemApp }
        if app.path.hasPrefix("/System/") { return .systemApp }
        return nil
    }

    /// Absolute paths of leftovers, sorted. `list(dir)` returns the entry names
    /// of an absolute directory (empty if it does not exist).
    public static func find(_ app: App, home: String, list: (String) -> [String]) -> [String] {
        guard refusal(for: app) == nil else { return [] }
        var found = Set<String>()
        for folder in libraryFolders {
            let dir = home + "/" + folder
            for entry in list(dir) where matches(entry, app: app, folder: folder) {
                found.insert(dir + "/" + entry)
            }
        }
        return found.sorted()
    }

    /// Whether a ~/Library entry belongs to the app.
    ///
    /// Bundle id matches are delimited so that "com.foo.Bar" does not claim
    /// "com.foo.BarHelperPro": the id must be the whole name, or be followed by
    /// "." (plist, savedState, helpers) or preceded by "." or a team prefix
    /// ("ABCDE12345.com.foo.Bar", "group.com.foo.Bar").
    /// App names are matched exactly (case-insensitive) and only in folders
    /// where apps use their name (Application Support, Caches, Logs…), and only
    /// if the name is not too generic.
    public static func matches(_ entry: String, app: App, folder: String) -> Bool {
        let e = entry.lowercased()
        let id = app.bundleID.lowercased()
        if e == id || e.hasPrefix(id + ".") || e.hasPrefix(id + "_") { return true }
        if e.hasSuffix("." + id) || e.contains("." + id + ".") { return true }
        // Group containers: "ABCDE12345.com.foo.Bar.shared" / "group.com.foo.Bar"
        if folder.hasSuffix("Group Containers"), let r = e.range(of: id) {
            let before = e[..<r.lowerBound]
            let after = e[r.upperBound...]
            if (before.isEmpty || before.hasSuffix(".")) && (after.isEmpty || after.hasPrefix(".")) { return true }
        }
        let nameFolders = ["Application Support", "Caches", "Logs", "WebKit", "HTTPStorages", "Saved Application State"]
        guard nameFolders.contains(where: { folder.hasSuffix($0) }) else { return false }
        for name in app.names {
            let n = name.lowercased().trimmingCharacters(in: .whitespaces)
            guard n.count >= 3, !genericNames.contains(n) else { continue }
            if e == n { return true }
        }
        return false
    }

    /// Folder names shared by many apps that must never match by name.
    static let genericNames: Set<String> = [
        "app", "apps", "data", "cache", "caches", "logs", "helper", "helpers", "plugins", "support",
        "apple", "google", "microsoft", "adobe", "mozilla", "crashreporter", "temp", "tmp", "updates",
    ]
}

/// One row of the uninstall list.
public struct UninstallItem: Equatable, Sendable, Identifiable {
    public var path: String
    public var size: Int64
    public var selected: Bool
    public var isApp: Bool

    public var id: String { path }

    public init(path: String, size: Int64, selected: Bool = true, isApp: Bool = false) {
        self.path = path
        self.size = size
        self.selected = selected
        self.isApp = isApp
    }
}

public enum UninstallPlan {
    /// The app bundle first, then leftovers, all selected.
    public static func items(app: String, appSize: Int64, leftovers: [(String, Int64)]) -> [UninstallItem] {
        [UninstallItem(path: app, size: appSize, isApp: true)]
            + leftovers.map { UninstallItem(path: $0.0, size: $0.1) }
    }

    public static func totalSelected(_ items: [UninstallItem]) -> Int64 {
        items.filter(\.selected).reduce(0) { $0 + $1.size }
    }

    /// Paths to send to the Trash: selected ones, never anything outside the
    /// app bundle or the user's Library (defence in depth).
    public static func trashList(_ items: [UninstallItem], home: String) -> [String] {
        items.filter(\.selected).map(\.path).filter { p in
            p.hasSuffix(".app") || p.hasPrefix(home + "/Library/")
        }
    }
}
