import Foundation

/// Gesture thresholds. Durations in seconds, distances in points, velocities in points per second.
public struct GestureConfig: Codable, Equatable, Sendable {
    public var tapMaxDuration: Double = 0.25
    public var tapMaxMovement: Double = 8
    public var doubleTapInterval: Double = 0.30
    public var longPressDuration: Double = 0.60
    public var classifyMovement: Double = 10
    public var pinchThreshold: Double = 12
    public var rotateThreshold: Double = 8
    public var momentumMinVelocity: Double = 50
    public var momentumDecayPerFrame: Double = 0.96
    public var momentumStopVelocity: Double = 20
    public var swipeDistance: Double = 60
    public var swipeMaxDuration: Double = 0.5
    public var stuckTimeout: Double = 0.5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureConfig()
        tapMaxDuration = try c.decodeIfPresent(Double.self, forKey: .tapMaxDuration) ?? d.tapMaxDuration
        tapMaxMovement = try c.decodeIfPresent(Double.self, forKey: .tapMaxMovement) ?? d.tapMaxMovement
        doubleTapInterval = try c.decodeIfPresent(Double.self, forKey: .doubleTapInterval) ?? d.doubleTapInterval
        longPressDuration = try c.decodeIfPresent(Double.self, forKey: .longPressDuration) ?? d.longPressDuration
        classifyMovement = try c.decodeIfPresent(Double.self, forKey: .classifyMovement) ?? d.classifyMovement
        pinchThreshold = try c.decodeIfPresent(Double.self, forKey: .pinchThreshold) ?? d.pinchThreshold
        rotateThreshold = try c.decodeIfPresent(Double.self, forKey: .rotateThreshold) ?? d.rotateThreshold
        momentumMinVelocity = try c.decodeIfPresent(Double.self, forKey: .momentumMinVelocity) ?? d.momentumMinVelocity
        momentumDecayPerFrame = try c.decodeIfPresent(Double.self, forKey: .momentumDecayPerFrame) ?? d.momentumDecayPerFrame
        momentumStopVelocity = try c.decodeIfPresent(Double.self, forKey: .momentumStopVelocity) ?? d.momentumStopVelocity
        swipeDistance = try c.decodeIfPresent(Double.self, forKey: .swipeDistance) ?? d.swipeDistance
        swipeMaxDuration = try c.decodeIfPresent(Double.self, forKey: .swipeMaxDuration) ?? d.swipeMaxDuration
        stuckTimeout = try c.decodeIfPresent(Double.self, forKey: .stuckTimeout) ?? d.stuckTimeout
    }
}
