import Foundation

// Every visible string goes through L(...) (SPEC §2.7).
// The .lproj folders are copied by scripts/bundle.sh into
// Ligero.app/Contents/Resources, so the lookup uses Bundle.main: an SPM
// resource bundle (Bundle.module) would have to sit at the root of the .app,
// where codesign rejects it. Keys must be string literals so that
// LocalizationTests can find them in the sources.

/// Localized string for `key`.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// Localized format string for `key`, filled with `args`.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: args)
}
