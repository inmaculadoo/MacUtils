import AppKit
import LigeroCore
import SwiftUI

/// System monitor in the menu (SPEC §4.10).
///
/// Sampling happens ONLY while the Monitor submenu is open (1 s timer, the
/// one exception to "no timers" in SPEC §2.1). The optional menu bar reading
/// is off by default and, when on, updates every ≥ 10 s with 50 % tolerance.
@MainActor
final class MonitorModule: LigeroModule, MenuContributing {
    static let id = "monitor"
    static let requiredPermissions: Set<Permission> = []

    static var descriptor: ModuleDescriptor {
        ModuleDescriptor(MonitorModule.self, titleKey: "module.monitor.title", summaryKey: "module.monitor.summary") {
            MonitorModule(context: $0)
        }
    }

    private let settings: MonitorSettings
    private let panel = MonitorPanelController()
    private var reading: MenuBarReading?

    init(context: AppContext) {
        settings = context.settings.load(MonitorSettings.self, module: Self.id)
    }

    func start() {
        if settings.menuBarReading {
            reading = MenuBarReading(interval: settings.clampedInterval)
        }
    }

    func stop() {
        panel.stopSampling()
        reading?.invalidate()
        reading = nil
    }

    func menuItems() -> [NSMenuItem] {
        [panel.makeMenuItem()]
    }
}

/// Values shown in the panel.
@MainActor
final class MonitorModel: ObservableObject {
    @Published var cpu: Double?
    @Published var gpu: GPUStats?
    @Published var memory: MemoryStats?
    @Published var battery: BatteryInfo?
    @Published var down: Double?
    @Published var up: Double?
    @Published var topCPU: [CPUUser] = []
}

/// Builds the Monitor submenu and samples while it is open.
@MainActor
final class MonitorPanelController: NSObject, NSMenuDelegate {
    private let model = MonitorModel()
    private var timer: Timer?
    private var lastCPU: [CPUTicks] = []
    private var lastNet: [String: NetworkCounters] = [:]
    private var lastProcesses: [ProcessCPUSample] = []
    private var lastTime: Date?

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("monitor.menu.title"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = self
        let content = NSMenuItem()
        let host = NSHostingView(rootView: MonitorView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: max(200, host.fittingSize.height))
        content.view = host
        submenu.addItem(content)
        item.submenu = submenu
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        startSampling()
    }

    func menuDidClose(_ menu: NSMenu) {
        stopSampling()
    }

    func startSampling() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        t.tolerance = 0.2
        // .common so it also fires while the menu is tracking.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopSampling() {
        timer?.invalidate()
        timer = nil
        lastCPU = []
        lastNet = [:]
        lastProcesses = []
        lastTime = nil
    }

    private func sample() {
        let now = Date()
        let dt = lastTime.map { now.timeIntervalSince($0) } ?? 0
        let cpu = SystemSampler.cpuTicks()
        let net = SystemSampler.network()
        let processes = SystemSampler.processes()
        if !lastCPU.isEmpty { model.cpu = CPUUsage.between(lastCPU, cpu).total }
        if dt > 0 {
            let rate = NetworkCounters.rate(from: lastNet, to: net, seconds: dt)
            model.down = rate.down
            model.up = rate.up
            model.topCPU = CPURanking.top(lastProcesses, processes, seconds: dt).map { user in
                var u = user
                if let app = NSRunningApplication(processIdentifier: user.pid), let name = app.localizedName { u.name = name }
                return u
            }
        }
        model.gpu = SystemSampler.gpu()
        model.memory = SystemSampler.memory()
        model.battery = SystemSampler.battery()
        lastCPU = cpu
        lastNet = net
        lastProcesses = processes
        lastTime = now
    }
}

struct MonitorView: View {
    @ObservedObject var model: MonitorModel

    /// Rows in the "top apps" list. Always this many, so the panel has the
    /// same height from the first frame (the menu sizes it once, when it
    /// opens; content that grows later was clipped at the top).
    static let topRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(L("monitor.cpu"), model.cpu.map { percent($0) })
            row(L("monitor.gpu"), model.gpu.map { g in
                g.memoryInUse.map { L("monitor.gpuValue", percent(g.utilization), bytes($0)) } ?? percent(g.utilization)
            })
            row(L("monitor.memory"), model.memory.map { L("monitor.memoryValue", bytes($0.used), bytes($0.total)) })
            row(L("monitor.pressure"), model.memory.map { L(pressureKey($0.pressure)) })
            row(L("monitor.network"), model.down.map { d in L("monitor.networkValue", rate(d), rate(model.up ?? 0)) })
            Divider()
            let b = model.battery
            row(L("monitor.battery"), b.map { L("monitor.batteryValue", $0.percent, batteryState($0)) })
            row(L("monitor.power"), b?.watts.map { L("monitor.wattsValue", abs($0)) })
            row(L("monitor.remaining"), b?.minutesRemaining.map { BatteryInfo.hoursMinutes($0) })
            row(L("monitor.health"), b?.health.map { L("monitor.percentValue", $0) })
            row(L("monitor.cycles"), b?.cycleCount.map { L("monitor.countValue", $0) })
            Divider()
            Text(L("monitor.topCPU")).font(.caption.weight(.semibold))
            ForEach(0..<Self.topRows, id: \.self) { i in
                HStack {
                    if i < model.topCPU.count {
                        let u = model.topCPU[i]
                        Text(u.name).lineLimit(1)
                        Spacer()
                        Text(L("monitor.percentValue", Int((u.cores * 100).rounded()))).monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        Text(i == 0 ? L("monitor.measuring") : " ").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 300, alignment: .leading)
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value ?? L("monitor.none")).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func percent(_ f: Double) -> String { L("monitor.percentValue", Int((f * 100).rounded())) }
    private func bytes(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }
    private func rate(_ bps: Double) -> String { L("monitor.rateValue", ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file)) }

    private func pressureKey(_ p: MemoryStats.Pressure) -> String {
        switch p {
        case .normal: return "monitor.pressure.normal"
        case .warning: return "monitor.pressure.warning"
        case .critical: return "monitor.pressure.critical"
        }
    }

    private func batteryState(_ b: BatteryInfo) -> String {
        if b.isCharging { return L("monitor.battery.charging") }
        if b.fullyCharged { return L("monitor.battery.full") }
        if b.externalPower { return L("monitor.battery.plugged") }
        return L("monitor.battery.discharging")
    }
}

/// Optional CPU/RAM text in the menu bar. Its own status item, updated by a
/// tolerant timer of at least 10 s.
@MainActor
final class MenuBarReading {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var lastCPU: [CPUTicks] = []

    init(interval: Double) {
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        update()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        t.tolerance = interval * 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    private func update() {
        let cpu = SystemSampler.cpuTicks()
        let usage = lastCPU.isEmpty ? 0 : CPUUsage.between(lastCPU, cpu).total
        lastCPU = cpu
        let mem = SystemSampler.memory()?.usedFraction ?? 0
        item.button?.title = L("monitor.menuBarValue", Int((usage * 100).rounded()), Int((mem * 100).rounded()))
    }
}
