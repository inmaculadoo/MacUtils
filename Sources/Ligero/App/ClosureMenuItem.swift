import AppKit
import LigeroCore

/// NSMenuItem that runs a closure, so modules (plain Swift classes) can add
/// menu entries without being NSObject subclasses. The menu is rebuilt each
/// time it opens, so these items and their closures live only while it shows.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func fire() {
        handler()
    }
}

extension NSMenuItem {
    /// Shows a global shortcut next to the title, the way menus show theirs.
    /// Only for display: the hotkey itself stays registered with Carbon.
    func showShortcut(_ combo: KeyCombo?) {
        guard let combo else { return }
        let special: [UInt32: Int] = [
            KeyCode.leftArrow: NSLeftArrowFunctionKey, KeyCode.rightArrow: NSRightArrowFunctionKey,
            KeyCode.upArrow: NSUpArrowFunctionKey, KeyCode.downArrow: NSDownArrowFunctionKey,
        ]
        let key: String
        if let f = special[combo.keyCode], let scalar = UnicodeScalar(f) {
            key = String(Character(scalar))
        } else if combo.keyCode == KeyCode.returnKey {
            key = "\r"
        } else if combo.keyCode == KeyCode.delete {
            key = "\u{8}"
        } else if combo.keyCode == KeyCode.space {
            key = " "
        } else {
            let name = KeyCode.name(for: combo.keyCode)
            guard name.count == 1 else { return }
            key = name.lowercased()
        }
        var mask: NSEvent.ModifierFlags = []
        if combo.modifiers.contains(.control) { mask.insert(.control) }
        if combo.modifiers.contains(.option) { mask.insert(.option) }
        if combo.modifiers.contains(.shift) { mask.insert(.shift) }
        if combo.modifiers.contains(.command) { mask.insert(.command) }
        keyEquivalent = key
        keyEquivalentModifierMask = mask
    }
}

extension Notification.Name {
    /// Posted (object: the CGWindowID as NSNumber) right before a module
    /// places a window on purpose, so that Ribbon stops tiling it.
    static let ligeroWindowPlaced = Notification.Name("app.allinone.windowPlaced")
}
