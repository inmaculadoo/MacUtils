import Foundation

/// Settings of the Capture module (SPEC §4.9).
public struct CaptureSettings: ModuleSettings {
    public var regionShortcut: KeyCombo?
    public var textShortcut: KeyCombo?
    public var pinShortcut: KeyCombo?
    public var copyToClipboard: Bool
    public var saveToDesktop: Bool

    public init(regionShortcut: KeyCombo?, textShortcut: KeyCombo?, pinShortcut: KeyCombo?,
                copyToClipboard: Bool, saveToDesktop: Bool) {
        self.regionShortcut = regionShortcut
        self.textShortcut = textShortcut
        self.pinShortcut = pinShortcut
        self.copyToClipboard = copyToClipboard
        self.saveToDesktop = saveToDesktop
    }

    public static let `default` = CaptureSettings(
        regionShortcut: KeyCombo(keyCode: 0x14, modifiers: [.control, .option, .shift]), // ⌃⌥⇧3
        textShortcut: KeyCombo(keyCode: 0x15, modifiers: [.control, .option, .shift]),   // ⌃⌥⇧4
        pinShortcut: KeyCombo(keyCode: 0x17, modifiers: [.control, .option, .shift]),    // ⌃⌥⇧5
        copyToClipboard: true,
        saveToDesktop: false
    )

    enum CodingKeys: String, CodingKey { case regionShortcut, textShortcut, pinShortcut, copyToClipboard, saveToDesktop }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        regionShortcut = c.contains(.regionShortcut) ? c.value(.regionShortcut, or: nil) : d.regionShortcut
        textShortcut = c.contains(.textShortcut) ? c.value(.textShortcut, or: nil) : d.textShortcut
        pinShortcut = c.contains(.pinShortcut) ? c.value(.pinShortcut, or: nil) : d.pinShortcut
        copyToClipboard = c.value(.copyToClipboard, or: d.copyToClipboard)
        saveToDesktop = c.value(.saveToDesktop, or: d.saveToDesktop)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(regionShortcut, forKey: .regionShortcut)
        try c.encode(textShortcut, forKey: .textShortcut)
        try c.encode(pinShortcut, forKey: .pinShortcut)
        try c.encode(copyToClipboard, forKey: .copyToClipboard)
        try c.encode(saveToDesktop, forKey: .saveToDesktop)
    }
}

public enum CaptureGeometry {
    /// Smallest selection accepted; a plain click cancels.
    public static let minimumSide: Double = 4

    /// Rectangle spanned by a drag, whatever its direction. Nil if too small.
    public static func selection(fromX x0: Double, y y0: Double, toX x1: Double, y y1: Double) -> LRect? {
        let r = LRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
        guard r.width >= minimumSide, r.height >= minimumSide else { return nil }
        return r
    }

    /// Converts a selection in global Cocoa coordinates (bottom-left origin)
    /// to the display-local, top-left rectangle ScreenCaptureKit's
    /// `sourceRect` expects, clipped to that display. Nil if they do not
    /// overlap.
    public static func sourceRect(selection: LRect, displayFrame: LRect) -> LRect? {
        let clipped = selection.intersection(displayFrame)
        guard !clipped.isEmpty else { return nil }
        let localX = clipped.x - displayFrame.x
        let localTop = displayFrame.maxY - clipped.maxY
        return LRect(x: localX, y: localTop, width: clipped.width, height: clipped.height)
    }

    /// Output size in pixels for a rect in points.
    public static func pixelSize(of rect: LRect, scale: Double) -> (width: Int, height: Int) {
        (max(1, Int((rect.width * scale).rounded())), max(1, Int((rect.height * scale).rounded())))
    }

    /// Size of a pin window: the capture at 1 pt per point, shrunk to fit
    /// `maxSide` while keeping the aspect ratio.
    public static func pinSize(width: Double, height: Double, maxSide: Double = 640) -> (Double, Double) {
        let longest = max(width, height)
        guard longest > maxSide, longest > 0 else { return (width, height) }
        let k = maxSide / longest
        return ((width * k).rounded(), (height * k).rounded())
    }
}

/// A recognised piece of text with its Vision bounding box (normalised,
/// origin at the bottom-left).
public struct TextBox: Equatable, Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var midY: Double { y + height / 2 }
}

public enum OCRText {
    /// Joins Vision observations into reading order: top to bottom, boxes on
    /// the same line left to right separated by a space, and a blank line
    /// where the vertical gap is large (a new paragraph or block).
    public static func assemble(_ boxes: [TextBox]) -> String {
        let items = boxes.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty else { return "" }
        let sorted = items.sorted { $0.midY > $1.midY }
        var lines: [[TextBox]] = []
        for box in sorted {
            if var last = lines.last, let ref = last.first, sameLine(ref, box) {
                last.append(box)
                lines[lines.count - 1] = last
            } else {
                lines.append([box])
            }
        }
        let heights = items.map(\.height).sorted()
        let typical = heights[heights.count / 2]
        var out = ""
        var previousBottom: Double?
        for line in lines {
            let text = line.sorted { $0.x < $1.x }.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            let top = line.map { $0.y + $0.height }.max() ?? 0
            let bottom = line.map(\.y).min() ?? 0
            if let previousBottom {
                out += (previousBottom - top) > typical * 1.2 ? "\n\n" : "\n"
            }
            out += text
            previousBottom = bottom
        }
        return out
    }

    /// Boxes are on the same line when their vertical centres are within half
    /// of the smaller height.
    static func sameLine(_ a: TextBox, _ b: TextBox) -> Bool {
        abs(a.midY - b.midY) < min(a.height, b.height) / 2
    }
}
