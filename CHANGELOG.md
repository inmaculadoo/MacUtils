# Changelog

## [0.1.0] — Fase 0: esqueleto

### Added
- SwiftPM package with `LigeroCore` (pure Swift, builds and tests on Linux), the
  `Ligero` executable (macOS 15+, arm64, only declared when building on macOS) and
  `LigeroCoreTests`. `defaultLocalization: "en"`.
- `scripts/bundle.sh`: release build for arm64, assembles `build/Ligero.app`,
  copies `Resources/*.lproj`, lints the `.strings` and `Info.plist`, and signs with
  `SIGN_ID` (ad-hoc when unset).
- `Resources/Info.plist` with `LSUIElement`, bundle id `app.allinone`, `en`/`es`.
- App skeleton: status item with an `NSMenu` built on open, `ModuleRegistry` and the
  `LigeroModule` protocol (disabled modules are never created; modules missing a
  permission start on their own once it is granted), one Codable settings blob per
  module in `UserDefaults`, Carbon global hotkeys (`HotKeyCenter`, handler installed
  only while a hotkey exists), `PermissionCenter` for Accessibility and Screen
  Recording (explanation alert + button to System Settings; Accessibility changes are
  detected via the `com.apple.accessibility.api` distributed notification, no
  polling) and launch at login with `SMAppService.mainApp`.
- Settings window (SwiftUI, created on open and released on close) with the language
  selector System / Español / English (writes `AppleLanguages` and offers a restart),
  launch at login, module toggles and permission status.
- Localization es/en from day one: `Resources/{en,es}.lproj/Localizable.strings`.
  `LocalizationTests` checks both files have the same keys and format specifiers,
  that every key used in `Sources/Ligero` exists, and that no SwiftUI/AppKit title is
  hard-coded.
- `LigeroCore`: Snap rectangle math (`SnapEngine`: halves with ½→⅔→⅓ cycling,
  quarters, thirds that stack on portrait displays, two-thirds, maximize, maximize
  height, center, next/previous display keeping the relative frame, optional gap),
  `RestoreHistory`, `KeyCombo`, tolerant settings decoding and a `.strings` parser.
- CI: the Linux job runs in the official `swift:6.2-noble` container.

### Notes
- Strings are looked up in `Bundle.main` instead of `Bundle.module`: an SPM resource
  bundle would have to live at the root of the `.app`, which `codesign` rejects.
  `bundle.sh` copies the `.lproj` folders into `Contents/Resources`.
