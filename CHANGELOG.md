# Changelog

## [0.2.0] — Fase 1: Snap + Scroll

### Added
- **Snap** module: Carbon hotkeys → focused window via AX → size/position/size.
  Rectangle-style defaults (⌃⌥ + arrows/letters, ⌃⌥⌘←/→ between displays,
  ⌃⌥⌫ restore). Restore remembers the frame before the first snap (up to 50
  windows, cleared on stop). Screens are read only when a shortcut is pressed. No
  animation.
- Snap settings tab: shortcut recorder (local key monitor only while recording;
  Carbon hotkeys are suspended meanwhile; duplicates are removed automatically),
  restore defaults, ½→⅔→⅓ cycling toggle and window gap (0–40 pt).
- **Scroll** module: IOHIDManager watches for external mice (built-in, SPI and
  trackpad devices are ignored). The CGEventTap for `scrollWheel` and
  `otherMouseDown/Up` exists only while a mouse is connected, and is not created at
  all if every option is off. Continuous events (trackpad, Magic Mouse) are never
  touched. Options: reverse vertical / horizontal wheel, linear scrolling with 1–10
  lines per notch, side buttons as ⌘[ / ⌘] (optionally swapped). A tap disabled by
  timeout is re-enabled.
- Scroll settings tab.
- `LigeroCore`: `ScrollSettings`, `ScrollTransform`, `MouseButtons`,
  `HIDDeviceInfo` classification and `KeyCombo.Modifiers(cocoaFlags:)`, with tests.

### Not done (on purpose)
- Smooth scrolling (SPEC §4.2 marks it optional and off by default): it needs a
  timer or display link while scrolling, so it is left for later.

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
