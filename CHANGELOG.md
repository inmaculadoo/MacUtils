# Changelog

## [0.3.0] — Fases 2–6: el resto del SPEC

### Added — stable (Block A)
- **Downloads** (§4.3): FSEvents on ~/Downloads (2 s latency, top level only),
  categories by extension with a UTType fallback, partial downloads/hidden
  files/folders/packages ignored, "stable for 2 s" via one delayed re-check
  started by the event (no periodic timer), collision-free names, moves only
  (never deletes), undo of any of the last 50 moves from the menu (undone files
  are not re-sorted), preview in Settings before the first activation. Off by
  default.
- **Shelf** (§4.4): global `leftMouseDragged`/`leftMouseUp` monitor, drag
  pasteboard read once per gesture, non-activating panel under the notch created
  once, drag files/URLs/text in and out, pinned folders as copy targets, hotkey
  ⌃⌥⌘S. Off by default.
- **Uninstall** (§4.8): leftovers by bundle id in every ~/Library folder of the
  SPEC (delimited matching, names only where apps use them, generic names never),
  Apple/system apps refused, sizes off the main thread, quit-if-running, everything
  to the Trash with `FileManager.trashItem`. On by default (zero idle cost).
- **Capture** (§4.9): ⌃⌥⇧3 region → PNG (clipboard and/or Desktop), ⌃⌥⇧4 region →
  text (Vision, es-ES + en-US, offline), ⌃⌥⇧5 capture and pin. `SCScreenshotManager`
  one-shot only, never `SCStream`. Off by default (needs Screen Recording).
- **Monitor** (§4.10): CPU, memory used and pressure, battery (%, state, watts,
  time remaining, health, cycles), network up/down and top energy users, sampled
  once per second only while the submenu is open. Optional menu bar reading, off
  by default, ≥ 10 s with 50 % tolerance. On by default.
- **Ribbon model** in LigeroCore (§4.12) with 27 tests.

### Added — experimental (Block B, all off by default, "Experimental" badge)
- **Switcher** (§4.5): ⌥Tab / ⌥⇧Tab, MRU order, current Space, search by typing,
  ⌘W/⌘M/⌘Q, thumbnails with Screen Recording (icons without it).
- **Dock Previews** (§4.6): AXObserver on the Dock list
  (`kAXSelectedChildrenChangedNotification`), previews from the shared cache,
  optional click-to-minimise/hide (its click tap exists only while on).
- **MenuBar** (§4.7): Ice-style 10 000 pt separator, chevron toggle, optional
  always-hidden section, hotkey ⌃⌥⌘B, re-hide on app switch. Tahoe risk documented
  in `MenuBarModule.swift`.
- **Audio** (§4.11): process taps + private aggregate + IOProc only for apps that
  play and are not at 100 % on the default output; Atomic gain, allocation-free
  DSP; mixer and per-app output in the menu.
- **Ribbon** (§4.12): mode toggled with ⌃⌥⌘Space, strips per display, shortcuts,
  parking away from shared display edges, only changed windows moved, original
  frames restored when the mode is turned off.
- Shared **WindowService** (reference-counted AXObservers, MRU, thumbnail LRU).

### Battery audit (point 11)
Reviewed in every file under `Sources/Ligero`:
- **Timers / loops**: only the Monitor panel timer (1 s, between `menuWillOpen`
  and `menuDidClose`) and the optional Monitor menu bar reading (≥ 10 s, 50 %
  tolerance, off by default). One-shot delays only follow an event: Downloads
  re-check, Shelf hide-after-drop, Accessibility re-check, Uninstall after quit.
  The two `while` loops iterate lists (getifaddrs, directory enumerator); nothing
  waits.
- **Observers removed in `stop()`**: Carbon hotkeys (Snap, Shelf, Capture, Switcher,
  MenuBar, Ribbon), FSEvents stream (Downloads), IOHIDManager callbacks and the
  scroll tap (Scroll), global/local NSEvent monitors (Shelf, Switcher, recorder),
  AXObservers (WindowService on last release, Dock), NSWorkspace observers
  (WindowService, Dock, MenuBar), Core Audio property listeners and taps (Audio),
  event taps (Scroll, Dock click, Ribbon gesture), status items (MenuBar, Monitor
  reading), panels and windows (Shelf, Switcher, Dock, Capture pins/overlay).
- **Event taps** exist only while needed: Scroll with an external mouse connected,
  Dock click option on, Ribbon mode on with the gesture option.
- **Closures**: every stored closure and C-callback context captures `self`
  weakly or unretained with a lifetime bounded by `stop()`; short one-shot Tasks
  may hold `self` strongly until they finish.
- **Main thread at idle**: nothing runs. Fixed in this audit: AX calls now have a
  messaging timeout (0.25–0.5 s) so a hung app cannot block the main thread for
  6 s; thumbnail cache reduced to 30 × 320 px (≈ 8 MB) to respect the 60 MB budget;
  Capture gives focus back to the previous app after selecting.

### Not done, or done differently (and why)
- **Smooth scrolling** (§4.2): needs a timer or display link while scrolling; left
  out to keep the module at zero cost.
- **Temperatures via SMC** (§4.10): private SMC keys differ per Apple Silicon chip
  and change between macOS releases; it is off by default in the SPEC, so it is
  not implemented rather than shipped unverified.
- **Per-core CPU** in Monitor: whole-machine `HOST_CPU_LOAD_INFO` avoids the
  per-sample allocation and `vm_deallocate` of `host_processor_info`.
- **Dropping an .app on the menu bar icon** (§4.8): the status bar button cannot be
  made a drag destination without subclassing it; the Uninstall window has a drop
  zone and the menu opens it.
- **Ribbon gesture** (§4.12): uses its own tap instead of the Scroll module's tap,
  because Scroll's tap only exists while a wheel mouse is connected and the gesture
  is a trackpad gesture. Same rule: it exists only while the mode is on and the
  option is enabled.
- **Shelf pinned folders** copy instead of move, so a drop can never lose a file.
- **Downloads folder names** are fixed in the current language when sorting is
  turned on, so switching the app language does not create new folders.
- **Private API**: `_AXUIElementGetWindow` (WindowService) maps AX windows to
  window ids, as AltTab and others do. No other private API is used.


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
