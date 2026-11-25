# Changelog

## [0.4.0] — All In One

### Changed
- The app is now called **All In One** (menu bar, Settings, Finder, permission
  lists) with a minimal black-and-white "C" logo: a template image in the menu
  bar and an app icon (`scripts/make-icon.swift` → `Resources/AppIcon.icns`).
  The bundle is `All In One.app`; the executable is still `Ligero`.

### Added
- **Awake** module (SPEC §4.13, like Amphetamine): keep the Mac awake for
  30 min / 1 h / 2 h / 5 h or until turned off (⌃⌥⌘A), or while chosen apps
  are open; optionally keep the display on. IOPM assertions; a timed session
  gives its timeout to the system, so there is no timer. Logic in `Awake.swift`
  with tests.
- **Monitor**: GPU usage and GPU memory in use (`IOAccelerator` →
  `PerformanceStatistics`), read only while the panel is open.

### Removed
- **MenuBar** module: not workable on macOS 27 (the separator length is capped
  and laid out away from its slot). Use System Settings → Menu Bar.

## [0.3.6] — Settings no longer opens at launch

### Fixed
- **Downloads**: while its preview was not accepted, it opened Settings at
  every launch. The first SwiftUI window loads framework caches (~25 MB of
  live allocations: symbol images, Swift metadata, AttributeGraph) that stay
  for the life of the process, so Ligero sat at ~49 MB instead of ~24 MB with
  every module on. Settings now opens only when the user switches the module
  on (`EnabledByUser`); the menu keeps "Downloads: show preview…". Opening
  Settings by hand still costs those ~25 MB once (checked: no leak, stable
  over repeated open/close; `malloc_zone_pressure_relief` frees nothing).

## [0.3.5] — Open the shelf from the notch

### Added
- **Shelf**: hovering the notch opens the shelf; it closes when the pointer
  leaves both the notch and the panel (not during a drag, and not when the
  shelf was opened with the shortcut or by a drag). An opaque black window
  sits exactly over each notch (`auxiliaryTopLeftArea` / `TopRightArea`) with
  a tracking area, so the window server reports enter/exit and nothing polls
  the mouse. Rebuilt on display changes. On by default, option in Settings →
  Shelf. Geometry in `NotchHover`, with tests.

## [0.3.4] — Snap by dragging to the screen edges

### Added
- **Snap**: drag a window to a screen edge or corner to snap it, with a
  translucent preview of the target. Left/right edge: half; top: maximise;
  corners: quarter; the bottom middle is left to the Dock. Edges shared with
  another display are not zones. On by default, option in Settings → Snap.
  Idle cost stays zero: the "window moved" AX notifications start the watch,
  and the two mouse monitors and the preview panel exist only until mouse-up.
  Zone logic in `SnapZones`, with tests.
- **Snap**: restore (⌃⌥⌫) after dragging a snapped window to another edge goes
  back to the frame from before the first snap (`RestoreHistory.appliedBeforeDrag`).

## [0.3.3] — Place windows from the menu

### Added
- **Snap**: a "Place <app> Window" submenu in the menu bar menu with every
  placement and its shortcut, acting on the window that was focused when the
  menu opened. Built only when the menu opens.
- **Ribbon**: while the mode is on, the menu lists the strip's columns in order
  (click one to scroll to it and focus it) and an "Active Window" submenu:
  width (¼ … full), move to position n, move left/right, stack, unstack, next
  display, and take out of / put back in the strip.
- **Ribbon**: floating windows (⌃⌥⌘F or the menu). A floating window leaves
  the strip, stays where it is and is not tiled again until put back.

### Fixed
- **Snap + Ribbon**: with the Ribbon mode on, a Snap placement was undone by
  the strip on its next layout. Snap now tells Ribbon (a local notification,
  observed only while the mode is on) and the window floats where Snap put it.
- **Ribbon**: the ⌥ + scroll gesture moved every visible window on each scroll
  event; it now moves them every 24 pt of accumulated scroll.
- **Audio**: the cost note in the menu showed "100 0x0or" (an unescaped `%`).

## [0.3.2] — Ribbon closer to a real scrolling window manager

### Fixed
- **Ribbon**: windows that missed "window created" (their app had just launched
  and did not answer AX yet) never joined the strip; two Safari windows stayed
  out of it. When an app gets focus, its visible windows that are not tiled
  are added.
- **Ribbon**: activating an app makes AppKit pull its parked windows back on
  screen, so they piled up over the visible columns. Parked windows moved by
  their app are put back at the edge (at most 3 times in a row, so an app that
  keeps fighting can't start a loop).

### Added
- **Ribbon**: mouse editing. Dragging a tiled window's edge keeps that width for
  its column (until a width shortcut); dropping a window reorders the strip by
  its centre, and dragging one out of a stack gives it its own column. The
  change is read once, on mouse-up, from a monitor that exists only between the
  drag and the mouse-up. Logic in `RibbonStrip.userEdit` / `apply`, with tests.
- **Ribbon**: ⌥ + two-finger horizontal scroll is on by default (the event tap
  still exists only while the mode is on).

### Notes
- macOS's own tiling can grab a window dropped while Ribbon is on and keep
  re-tiling it. Turn off System Settings → Desktop & Dock → "Drag windows to
  screen edges to tile" while using Ribbon.

## [0.3.1] — First run on the Mac (Apple Silicon, macOS 27.2, Xcode 27.2)

### Fixed
- **Snap**: windows with a minimum size (Safari ~574 pt, Discord 940×500) ended
  up partly off screen on the right/bottom layouts; they are now settled inside
  the screen, keeping the edge the layout touches (`SnapEngine.settle`).
- **Snap**: apps that round their size to a grid (Terminal) never matched a snap
  frame, so the ½ → ⅔ → ⅓ cycle never advanced and restore lost the original
  frame. The history now keeps the requested and the real frame
  (`RestoreHistory.lastTarget`).
- **Downloads**: the Settings preview read ~/Downloads on the main thread; the
  first read waits on macOS's folder-access prompt and froze the whole app
  (menu, Settings, hotkeys) until it was answered. Now read off the main thread.
- **Uninstall**: the "app is running" check ran only when the app was loaded, so
  an app opened afterwards could be moved to the Trash while running. Re-checked
  when the window becomes key and right before trashing.
- **Monitor**: `ri_billed_energy` is always 0 on macOS 27, so "Top energy now"
  showed 0.00 W for everything; uses `ri_energy_nj` (`rusage_info_v6`). Battery
  capacities now live only inside `BatteryData`, which hid the health row; read
  there too, preferring the nominal capacity (closest to System Settings).

- **Dock Previews**: with an auto-hiding Dock the preview stayed on screen
  after leaving the Dock (the Dock does not always report it). While visible,
  mouse-move monitors hide it once the pointer is outside the panel and the
  Dock (`DockPreviewHover`); they exist only while the preview shows.
- **Audio**: Ligero itself showed up in the mixer (it becomes an audio client
  after playing a sound or hosting a tap); its pid is excluded.
- **WindowService** (Ribbon, Switcher, Dock): apps launched while the service
  was active were observed before they answered AX, so their window cache was
  never invalidated and their windows were missing (Ribbon ignored them).
  Observers are kept only if they registered; unobserved apps are read fresh.
  Ribbon reads fresh frames when the mode starts.

### Not viable
- **MenuBar** on macOS 27: a status item's length is capped (10 000 → 5 002 pt)
  and the oversized separator is laid out away from its slot, so icons on its
  left are not pushed off screen. Left off; macOS 26+ has a native setting
  (System Settings → Menu Bar) to choose which apps show icons.

### Notes
- Audio boost above 100 % is only audible for quiet sources: most music is
  already near full scale, and +50 % (≈ +3.5 dB) clips at the peaks.
- Ribbon has no animations on purpose (they need a timer or display link
  while moving, against the battery rules).
- Rectangle registers the same ⌃⌥ shortcuts; whichever app registered first gets
  them. Quit Rectangle (or change its shortcuts) to use Snap.
- The first value of the optional menu bar CPU reading is 0 % until the second
  sample (one interval later).

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
