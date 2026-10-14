import Foundation
import CoreGraphics

enum Geometry {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(b.x - a.x, b.y - a.y)
    }

    static func centroid(_ touches: [ActiveTouch]) -> CGPoint {
        guard !touches.isEmpty else { return .zero }
        let sum = touches.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.position.x, y: $0.y + $1.position.y) }
        return CGPoint(x: sum.x / Double(touches.count), y: sum.y / Double(touches.count))
    }

    static func pairDistance(_ touches: [ActiveTouch]) -> Double {
        distance(touches[0].position, touches[1].position)
    }

    /// Angle of the vector from touch 0 to touch 1 in degrees, screen coordinates (y down).
    static func pairAngle(_ touches: [ActiveTouch]) -> Double {
        let a = touches[0].position, b = touches[1].position
        return atan2(b.y - a.y, b.x - a.x) * 180 / .pi
    }

    /// Shortest signed difference `to − from`, normalized to (−180, 180].
    static func angleDelta(from: Double, to: Double) -> Double {
        var d = to - from
        while d > 180 { d -= 360 }
        while d <= -180 { d += 360 }
        return d
    }

    /// Seconds between two monotonic nanosecond timestamps; 0 when `to` is not after `from`.
    static func seconds(from: UInt64, to: UInt64) -> Double {
        to > from ? Double(to - from) / 1_000_000_000 : 0
    }
}
