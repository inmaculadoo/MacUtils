import AppKit
import ApplicationServices
import CoreGraphics
import LigeroCore

/// Tracks the TCC permissions of SPEC §6 and explains them before sending
/// the user to System Settings.
///
/// No polling: Accessibility changes arrive as the distributed notification
/// `com.apple.accessibility.api`. Screen Recording has no notification, so it
/// is re-checked only when the menu or the Settings window opens.
@MainActor
final class PermissionCenter {
    /// Called when any permission changes state.
    var onChange: (@MainActor () -> Void)?

    private var state: [Permission: Bool] = [:]
    private var explainedThisLaunch: Set<Permission> = []
    // Written once in init, read in deinit (which is nonisolated).
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        state = snapshot()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // TCC writes its database right after posting; check once a moment later.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.refresh()
            }
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted()
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        }
    }

    func missing(_ required: Set<Permission>) -> [Permission] {
        Permission.allCases.filter { required.contains($0) && !isGranted($0) }
    }

    /// Re-reads every permission and calls `onChange` if one changed.
    func refresh() {
        let now = snapshot()
        guard now != state else { return }
        state = now
        Log.permissions.info("Permissions changed: \(now.description, privacy: .public)")
        onChange?()
    }

    /// Registers Ligero in the system list (the system may show its own
    /// prompt) and opens the matching pane of System Settings.
    func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            // String literal instead of kAXTrustedCheckOptionPrompt, which is
            // imported as a mutable global and is not concurrency-safe.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        openSystemSettings(for: permission)
    }

    func openSystemSettings(for permission: Permission) {
        let anchor: String
        switch permission {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows the explanation for `permission` once per launch, listing the
    /// modules that need it, with a button that opens System Settings.
    func explain(_ permission: Permission, neededBy modules: [String]) {
        guard !explainedThisLaunch.contains(permission) else { return }
        explainedThisLaunch.insert(permission)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("permission.alert.title", L(permission.titleKey))
        alert.informativeText = L(permission.explanationKey) + "\n\n"
            + L("permission.alert.neededBy", modules.joined(separator: ", "))
        alert.addButton(withTitle: L("permission.alert.open"))
        alert.addButton(withTitle: L("permission.alert.later"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            request(permission)
        }
    }

    private func snapshot() -> [Permission: Bool] {
        var s: [Permission: Bool] = [:]
        for p in Permission.allCases { s[p] = isGranted(p) }
        return s
    }
}
