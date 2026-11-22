import CoreGraphics
import LigeroCore

extension LRect {
    init(_ r: CGRect) {
        self.init(x: Double(r.origin.x), y: Double(r.origin.y), width: Double(r.width), height: Double(r.height))
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
