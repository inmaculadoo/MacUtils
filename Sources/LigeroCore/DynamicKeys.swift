/// Localization keys that the app builds at run time from LigeroCore types and
/// that a source scan cannot see. LocalizationTests checks they all exist.
public enum DynamicKeys {
    public static var all: [String] {
        var keys: [String] = []
        keys += DownloadCategory.allCases.flatMap { [$0.folderKey, $0.titleKey] }
        return keys
    }
}
