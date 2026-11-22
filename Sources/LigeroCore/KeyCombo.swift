/// A global keyboard shortcut as Carbon's `RegisterEventHotKey` wants it:
/// a virtual key code plus Carbon modifier flags.
public struct KeyCombo: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Carbon modifier masks (`cmdKey`, `shiftKey`, … in Carbon/HIToolbox),
    /// repeated here so that LigeroCore does not depend on Carbon.
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 8)   // cmdKey   = 256
        public static let shift = Modifiers(rawValue: 1 << 9)     // shiftKey = 512
        public static let option = Modifiers(rawValue: 1 << 11)   // optionKey = 2048
        public static let control = Modifiers(rawValue: 1 << 12)  // controlKey = 4096

        public static let all: Modifiers = [.command, .shift, .option, .control]

        /// From `NSEvent.ModifierFlags.rawValue` (device-independent bits).
        public init(cocoaFlags: UInt) {
            var m: Modifiers = []
            if cocoaFlags & (1 << 17) != 0 { m.insert(.shift) }
            if cocoaFlags & (1 << 18) != 0 { m.insert(.control) }
            if cocoaFlags & (1 << 19) != 0 { m.insert(.option) }
            if cocoaFlags & (1 << 20) != 0 { m.insert(.command) }
            self = m
        }
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.all)
    }

    /// A global shortcut needs at least one of ⌘ ⌥ ⌃, or it would steal
    /// plain typing. Function keys are the exception.
    public var isValidGlobalShortcut: Bool {
        if KeyCode.isFunctionKey(keyCode) { return true }
        return !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    /// "⌃⌥←" in the order macOS menus use: ⌃ ⌥ ⇧ ⌘.
    public var description: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + KeyCode.name(for: keyCode)
    }
}

/// macOS virtual key codes (Carbon `kVK_*`, ANSI layout).
public enum KeyCode {
    public static let a: UInt32 = 0x00, s: UInt32 = 0x01, d: UInt32 = 0x02, f: UInt32 = 0x03
    public static let h: UInt32 = 0x04, g: UInt32 = 0x05, z: UInt32 = 0x06, x: UInt32 = 0x07
    public static let c: UInt32 = 0x08, v: UInt32 = 0x09, b: UInt32 = 0x0B, q: UInt32 = 0x0C
    public static let w: UInt32 = 0x0D, e: UInt32 = 0x0E, r: UInt32 = 0x0F, y: UInt32 = 0x10
    public static let t: UInt32 = 0x11, o: UInt32 = 0x1F, u: UInt32 = 0x20, i: UInt32 = 0x22
    public static let p: UInt32 = 0x23, l: UInt32 = 0x25, j: UInt32 = 0x26, k: UInt32 = 0x28
    public static let n: UInt32 = 0x2D, m: UInt32 = 0x2E
    public static let leftBracket: UInt32 = 0x21, rightBracket: UInt32 = 0x1E
    public static let returnKey: UInt32 = 0x24, tab: UInt32 = 0x30, space: UInt32 = 0x31
    public static let delete: UInt32 = 0x33, escape: UInt32 = 0x35, forwardDelete: UInt32 = 0x75
    public static let leftArrow: UInt32 = 0x7B, rightArrow: UInt32 = 0x7C
    public static let downArrow: UInt32 = 0x7D, upArrow: UInt32 = 0x7E

    static let names: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
        0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
        0x24: "↩", 0x30: "⇥", 0x31: "␣", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]

    static let functionKeys: Set<UInt32> = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]

    public static func name(for keyCode: UInt32) -> String {
        names[keyCode] ?? "#\(keyCode)"
    }

    public static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeys.contains(keyCode)
    }
}
