import AppKit
import CoreAudio
import LigeroCore
import SwiftUI

/// Per-app volume (0–150 %) and output device with Core Audio process taps
/// (SPEC §4.11). EXPERIMENTAL.
///
/// Cost model: property listeners only (process list, "is playing" per
/// process, default output) — Core Audio calls them when something changes.
/// A tap exists only for an app that is playing AND is not at 100 % on the
/// default output; with everything neutral there is no tap at all. The tap
/// is destroyed when the app stops playing or quits. The IOProc is real-time
/// and does no allocation, locking or Swift concurrency.
@MainActor
final class AudioModule: LigeroModule, MenuContributing {
    static let id = "audio"
    static let requiredPermissions: Set<Permission> = []

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(AudioModule.self, titleKey: "module.audio.title", summaryKey: "module.audio.summary",
                         experimental: true) { AudioModule(context: $0) }
    }

    private let context: AppContext
    private var settings: AudioSettings
    private var taps: [AudioObjectID: ProcessTap] = [:]
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private let mixer = AudioMixerModel()

    init(context: AppContext) {
        self.context = context
        settings = context.settings.load(AudioSettings.self, module: Self.id)
        mixer.onChange = { [weak self] bundle, setting in self?.set(setting, for: bundle) }
    }

    func start() {
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = CoreAudioHAL.address(selector)
            let block = listenerBlock()
            if AudioObjectAddPropertyListenerBlock(CoreAudioHAL.system, &addr, DispatchQueue.main, block) == OSStatus(noErr) {
                systemListeners.append((addr, block))
            }
        }
        reconcile()
    }

    func stop() {
        for (addr, block) in systemListeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(CoreAudioHAL.system, &a, DispatchQueue.main, block)
        }
        systemListeners.removeAll()
        for (object, block) in processListeners {
            var a = CoreAudioHAL.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(object, &a, DispatchQueue.main, block)
        }
        processListeners.removeAll()
        for tap in taps.values { tap.destroy() }
        taps.removeAll()
    }

    private func listenerBlock() -> AudioObjectPropertyListenerBlock {
        Self.makeListener(WeakRef(self))
    }

    /// Built outside the main actor so the block is not actor-isolated; Core
    /// Audio calls it on the main queue we pass when registering.
    private nonisolated static func makeListener(_ ref: WeakRef<AudioModule>) -> AudioObjectPropertyListenerBlock {
        { _, _ in
            MainActor.assumeIsolated { ref.value?.reconcile() }
        }
    }

    // MARK: Taps

    /// Brings taps and listeners in line with what is playing and the settings.
    private func reconcile() {
        let processes = CoreAudioHAL.processes()
        let live = Set(processes.map(\.object))

        // "Is playing" listeners for every audio client, removed when it goes.
        for object in live where processListeners[object] == nil {
            var addr = CoreAudioHAL.address(kAudioProcessPropertyIsRunningOutput)
            let block = listenerBlock()
            if AudioObjectAddPropertyListenerBlock(object, &addr, DispatchQueue.main, block) == OSStatus(noErr) {
                processListeners[object] = block
            }
        }
        for (object, block) in processListeners where !live.contains(object) {
            var addr = CoreAudioHAL.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(object, &addr, DispatchQueue.main, block)
            processListeners.removeValue(forKey: object)
        }

        let defaultUID = CoreAudioHAL.defaultOutputUID
        var wanted = Set<AudioObjectID>()
        for p in processes {
            let setting = settings.apps[p.bundleID]
            guard let setting, AudioRouting.needsTap(setting, isPlaying: p.isPlaying, defaultOutputUID: defaultUID),
                  let output = AudioRouting.outputUID(for: setting, defaultOutputUID: defaultUID) else { continue }
            wanted.insert(p.object)
            if let tap = taps[p.object], tap.outputUID == output {
                tap.gain.set(AudioRouting.gain(for: setting))
                continue
            }
            taps.removeValue(forKey: p.object)?.destroy()
            if let tap = ProcessTap(process: p.object, bundleID: p.bundleID, outputUID: output,
                                    gain: AudioRouting.gain(for: setting)) {
                taps[p.object] = tap
                Log.modules.info("Audio tap created for \(p.bundleID, privacy: .public)")
            } else {
                Log.modules.error("Audio tap failed for \(p.bundleID, privacy: .public)")
            }
        }
        for (object, tap) in taps where !wanted.contains(object) {
            tap.destroy()
            taps.removeValue(forKey: object)
            Log.modules.info("Audio tap removed for \(tap.bundleID, privacy: .public)")
        }
        if mixer.isVisible { refreshMixer(processes) }
    }

    private func set(_ setting: AppAudioSetting, for bundleID: String) {
        settings.set(setting, for: bundleID)
        context.settings.save(settings, module: Self.id)
        reconcile()
    }

    // MARK: Menu

    func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: L("audio.menu.title"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = mixer
        let processes = CoreAudioHAL.processes()
        refreshMixer(processes)

        let content = NSMenuItem()
        let host = NSHostingView(rootView: AudioMixerView(model: mixer))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: max(60, host.fittingSize.height))
        content.view = host
        submenu.addItem(content)

        // Output device per app, as plain submenus (popups inside a menu are unreliable).
        let devices = CoreAudioHAL.outputDevices()
        if !mixer.rows.isEmpty, !devices.isEmpty {
            submenu.addItem(.separator())
            for row in mixer.rows {
                let output = NSMenuItem(title: L("audio.menu.outputFor", row.name), action: nil, keyEquivalent: "")
                let list = NSMenu()
                let current = settings.apps[row.bundleID]?.outputUID
                let system = ClosureMenuItem(title: L("audio.menu.systemOutput")) { [weak self] in
                    self?.setOutput(nil, for: row.bundleID)
                }
                system.state = current == nil ? .on : .off
                list.addItem(system)
                for d in devices {
                    let entry = ClosureMenuItem(title: d.name) { [weak self] in self?.setOutput(d.uid, for: row.bundleID) }
                    entry.state = current == d.uid ? .on : .off
                    list.addItem(entry)
                }
                output.submenu = list
                submenu.addItem(output)
            }
        }
        submenu.addItem(.separator())
        let note = NSMenuItem(title: L("audio.menu.costNote", taps.count), action: nil, keyEquivalent: "")
        note.isEnabled = false
        submenu.addItem(note)
        item.submenu = submenu
        return [item]
    }

    private func setOutput(_ uid: String?, for bundleID: String) {
        var s = settings.apps[bundleID] ?? .neutral
        s.outputUID = uid
        set(s, for: bundleID)
    }

    private func refreshMixer(_ processes: [CoreAudioHAL.Process]) {
        var rows: [AudioMixerRow] = []
        var seen = Set<String>()
        for p in processes where p.isPlaying || settings.apps[p.bundleID] != nil {
            guard seen.insert(p.bundleID).inserted else { continue }
            let app = NSRunningApplication(processIdentifier: p.pid)
            rows.append(AudioMixerRow(
                bundleID: p.bundleID,
                name: app?.localizedName ?? p.bundleID,
                icon: app?.icon,
                setting: settings.apps[p.bundleID] ?? .neutral,
                playing: p.isPlaying
            ))
        }
        mixer.rows = rows.sorted { $0.playing != $1.playing ? $0.playing : $0.name < $1.name }
    }
}

struct AudioMixerRow: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage?
    var setting: AppAudioSetting
    let playing: Bool
}

@MainActor
final class AudioMixerModel: NSObject, ObservableObject, NSMenuDelegate {
    @Published var rows: [AudioMixerRow] = []
    private(set) var isVisible = false
    var onChange: @MainActor (String, AppAudioSetting) -> Void = { _, _ in }

    func menuWillOpen(_ menu: NSMenu) { isVisible = true }
    func menuDidClose(_ menu: NSMenu) { isVisible = false }

    func update(_ bundleID: String, _ change: (inout AppAudioSetting) -> Void) {
        guard let i = rows.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        change(&rows[i].setting)
        onChange(bundleID, rows[i].setting)
    }
}

struct AudioMixerView: View {
    @ObservedObject var model: AudioMixerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.rows.isEmpty {
                Text(L("audio.nothingPlaying")).foregroundStyle(.secondary)
            }
            ForEach(model.rows) { row in
                HStack(spacing: 8) {
                    if let icon = row.icon {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.caption).lineLimit(1)
                        Slider(value: Binding(
                            get: { row.setting.volume },
                            set: { v in model.update(row.bundleID) { $0.volume = (v * 20).rounded() / 20 } }
                        ), in: 0...AppAudioSetting.maxVolume)
                        .disabled(row.setting.muted)
                    }
                    Text(L("audio.percent", Int((row.setting.volume * 100).rounded())))
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                    Button {
                        model.update(row.bundleID) { $0.muted.toggle() }
                    } label: {
                        Image(systemName: row.setting.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(L("audio.mute"))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 320, alignment: .leading)
    }
}
