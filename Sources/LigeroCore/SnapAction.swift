/// Every window placement the Snap module offers (SPEC §4.1).
public enum SnapAction: String, CaseIterable, Codable, Hashable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird
    case firstTwoThirds, lastTwoThirds
    case maximize, maximizeHeight, center
    case nextDisplay, previousDisplay
    case restore

    public var localizationKey: String { "snap.action.\(rawValue)" }
}
