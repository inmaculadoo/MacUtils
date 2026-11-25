/// Settings of the Scroll module (SPEC §4.2).
public struct ScrollSettings: ModuleSettings {
    /// Reverse the vertical wheel of external mice only.
    public var invertVertical: Bool
    /// Reverse horizontal scrolling (tilt wheel, Shift+wheel) of external mice.
    public var invertHorizontal: Bool
    /// Fixed lines per wheel notch, ignoring macOS acceleration.
    public var linear: Bool
    public var linesPerTick: Int
    /// Side buttons 4 and 5 as Back / Forward.
    public var sideButtonsNavigate: Bool
    public var swapSideButtons: Bool

    public init(invertVertical: Bool, invertHorizontal: Bool, linear: Bool, linesPerTick: Int,
                sideButtonsNavigate: Bool, swapSideButtons: Bool) {
        self.invertVertical = invertVertical
        self.invertHorizontal = invertHorizontal
        self.linear = linear
        self.linesPerTick = linesPerTick
        self.sideButtonsNavigate = sideButtonsNavigate
        self.swapSideButtons = swapSideButtons
    }

    public static let linesRange = 1...10

    public static let `default` = ScrollSettings(
        invertVertical: true, invertHorizontal: false, linear: false, linesPerTick: 3,
        sideButtonsNavigate: true, swapSideButtons: false
    )

    /// With everything off, the event tap would only pass events through, so
    /// the module does not install it at all.
    public var needsEventTap: Bool {
        invertVertical || invertHorizontal || linear || sideButtonsNavigate
    }

    /// Lines per notch, clamped to `linesRange`.
    public var clampedLines: Int {
        min(max(linesPerTick, Self.linesRange.lowerBound), Self.linesRange.upperBound)
    }

    enum CodingKeys: String, CodingKey {
        case invertVertical, invertHorizontal, linear, linesPerTick, sideButtonsNavigate, swapSideButtons
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        invertVertical = c.value(.invertVertical, or: d.invertVertical)
        invertHorizontal = c.value(.invertHorizontal, or: d.invertHorizontal)
        linear = c.value(.linear, or: d.linear)
        linesPerTick = c.value(.linesPerTick, or: d.linesPerTick)
        sideButtonsNavigate = c.value(.sideButtonsNavigate, or: d.sideButtonsNavigate)
        swapSideButtons = c.value(.swapSideButtons, or: d.swapSideButtons)
    }
}

/// The scroll-wheel fields of a CGEvent that Ligero reads and rewrites.
/// Axis 1 is vertical, axis 2 horizontal.
public struct ScrollDeltas: Equatable, Sendable {
    /// `kCGScrollWheelEventDeltaAxis*` (whole lines).
    public var lines1: Int64
    public var lines2: Int64
    /// `kCGScrollWheelEventFixedPtDeltaAxis*` (lines, fractional).
    public var fixed1: Double
    public var fixed2: Double
    /// `kCGScrollWheelEventPointDeltaAxis*` (pixels).
    public var point1: Int64
    public var point2: Int64

    public init(lines1: Int64 = 0, lines2: Int64 = 0, fixed1: Double = 0, fixed2: Double = 0,
                point1: Int64 = 0, point2: Int64 = 0) {
        self.lines1 = lines1
        self.lines2 = lines2
        self.fixed1 = fixed1
        self.fixed2 = fixed2
        self.point1 = point1
        self.point2 = point2
    }
}

public enum ScrollTransform {
    /// Pixels per line macOS uses for a classic wheel notch.
    public static let pixelsPerLine: Int64 = 10

    /// New deltas for a wheel event, or nil to leave the event untouched.
    ///
    /// `isContinuous` is `kCGScrollWheelEventIsContinuous`: trackpads and the
    /// Magic Mouse report continuous (pixel) scrolling and are never changed,
    /// so they keep following the system "natural scrolling" setting.
    public static func transform(_ input: ScrollDeltas, isContinuous: Bool, settings: ScrollSettings) -> ScrollDeltas? {
        guard !isContinuous else { return nil }
        guard settings.invertVertical || settings.invertHorizontal || settings.linear else { return nil }
        var out = input
        if settings.linear {
            let n = Int64(settings.clampedLines)
            out.lines1 = sign(input.lines1, input.fixed1) * n
            out.lines2 = sign(input.lines2, input.fixed2) * n
            out.fixed1 = Double(out.lines1)
            out.fixed2 = Double(out.lines2)
            out.point1 = out.lines1 * pixelsPerLine
            out.point2 = out.lines2 * pixelsPerLine
        }
        if settings.invertVertical {
            out.lines1 = -out.lines1
            out.fixed1 = -out.fixed1
            out.point1 = -out.point1
        }
        if settings.invertHorizontal {
            out.lines2 = -out.lines2
            out.fixed2 = -out.fixed2
            out.point2 = -out.point2
        }
        return out == input ? nil : out
    }

    /// Direction of a delta, using the fractional field when the integer one
    /// rounds to zero (slow wheel movement).
    static func sign(_ lines: Int64, _ fixed: Double) -> Int64 {
        if lines != 0 { return lines > 0 ? 1 : -1 }
        if fixed > 0 { return 1 }
        if fixed < 0 { return -1 }
        return 0
    }
}

public enum NavigationAction: Equatable, Sendable {
    case back, forward
}

public enum MouseButtons {
    /// CGEvent button numbers: 0 left, 1 right, 2 middle, 3 and 4 the side
    /// buttons (usually 3 = back, 4 = forward).
    public static func navigation(forButton button: Int64, settings: ScrollSettings) -> NavigationAction? {
        guard settings.sideButtonsNavigate else { return nil }
        switch button {
        case 3: return settings.swapSideButtons ? .forward : .back
        case 4: return settings.swapSideButtons ? .back : .forward
        default: return nil
        }
    }
}

/// Decides from IOHID properties whether a pointing device is an external
/// mouse with a wheel (the only case where the event tap is installed).
public struct HIDDeviceInfo: Equatable, Sendable {
    public var product: String?
    public var transport: String?
    public var builtIn: Bool
    public var usagePage: Int
    public var usage: Int

    public init(product: String?, transport: String?, builtIn: Bool, usagePage: Int, usage: Int) {
        self.product = product
        self.transport = transport
        self.builtIn = builtIn
        self.usagePage = usagePage
        self.usage = usage
    }

    /// HID Generic Desktop page / Mouse usage.
    public static let genericDesktop = 0x01
    public static let mouseUsage = 0x02

    public var isExternalMouse: Bool {
        guard usagePage == Self.genericDesktop, usage == Self.mouseUsage else { return false }
        guard !builtIn else { return false }
        let name = (product ?? "").lowercased()
        if name.contains("trackpad") { return false }
        // The internal trackpad and keyboard of Apple Silicon laptops use SPI.
        if let t = transport?.lowercased(), t == "spi" || t == "fifo" { return false }
        return true
    }
}
