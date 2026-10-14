import Foundation
import CoreGraphics

/// Produces the per-frame scroll deltas that follow a two-finger lift-off, like a trackpad's inertia.
public struct MomentumGenerator: Sendable {
    public var decayPerFrame: Double
    /// Points per second below which the sequence stops.
    public var stopVelocity: Double
    public var frameRate: Double
    public var maxFrames: Int

    /// Hostile values never trap or grow the sequence: `decayPerFrame` is clamped to 0…0.999 (NaN becomes 0.96),
    /// a `frameRate` that is not positive and finite becomes 60.
    public init(decayPerFrame: Double = 0.96, stopVelocity: Double = 20, frameRate: Double = 60, maxFrames: Int = 600) {
        self.decayPerFrame = decayPerFrame.isNaN ? 0.96 : min(max(decayPerFrame, 0), 0.999)
        self.stopVelocity = stopVelocity
        self.frameRate = frameRate > 0 && frameRate.isFinite ? frameRate : 60
        self.maxFrames = maxFrames
    }

    /// `initialVelocity` in points per second; result in points per frame.
    public func frames(initialVelocity: CGVector) -> [CGVector] {
        var velocity = initialVelocity
        var frames: [CGVector] = []
        while hypot(velocity.dx, velocity.dy) > stopVelocity && frames.count < maxFrames {
            frames.append(CGVector(dx: velocity.dx / frameRate, dy: velocity.dy / frameRate))
            velocity = CGVector(dx: velocity.dx * decayPerFrame, dy: velocity.dy * decayPerFrame)
        }
        return frames
    }
}
