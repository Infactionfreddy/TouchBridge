import Foundation

/// Gesture thresholds. Durations in seconds, distances in points, velocities in points per second.
public struct GestureConfig: Codable, Equatable, Sendable {
    public var tapMaxDuration: Double = 0.25
    public var tapMaxMovement: Double = 8
    public var doubleTapInterval: Double = 0.30
    public var longPressDuration: Double = 0.60
    /// Two-finger movement that classifies a scroll. 4 pt instead of the spec's 10 pt: with the reference panel
    /// (125 Hz, 0.65 px per digitizer step) 10 pt meant 33–60 ms of dead time followed by an 11–15 px jump.
    public var classifyMovement: Double = 4
    public var pinchThreshold: Double = 12
    public var rotateThreshold: Double = 8
    public var momentumMinVelocity: Double = 50
    /// Time window (seconds) over which the lift-off velocity for momentum is measured. A single report
    /// interval underestimates it because the fingers slow down just before they leave the panel.
    public var velocityWindow: Double = 0.05
    public var momentumDecayPerFrame: Double = 0.96
    public var momentumStopVelocity: Double = 20
    public var swipeDistance: Double = 60
    public var swipeMaxDuration: Double = 0.5
    public var stuckTimeout: Double = 0.5

    public init() {}

    /// Missing values take the default; every value is then clamped (see `clamped()`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureConfig()
        func read(_ key: CodingKeys, _ fallback: Double) throws -> Double {
            try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
        }
        tapMaxDuration = try read(.tapMaxDuration, d.tapMaxDuration)
        tapMaxMovement = try read(.tapMaxMovement, d.tapMaxMovement)
        doubleTapInterval = try read(.doubleTapInterval, d.doubleTapInterval)
        longPressDuration = try read(.longPressDuration, d.longPressDuration)
        classifyMovement = try read(.classifyMovement, d.classifyMovement)
        pinchThreshold = try read(.pinchThreshold, d.pinchThreshold)
        rotateThreshold = try read(.rotateThreshold, d.rotateThreshold)
        momentumMinVelocity = try read(.momentumMinVelocity, d.momentumMinVelocity)
        velocityWindow = try read(.velocityWindow, d.velocityWindow)
        momentumDecayPerFrame = try read(.momentumDecayPerFrame, d.momentumDecayPerFrame)
        momentumStopVelocity = try read(.momentumStopVelocity, d.momentumStopVelocity)
        swipeDistance = try read(.swipeDistance, d.swipeDistance)
        swipeMaxDuration = try read(.swipeMaxDuration, d.swipeMaxDuration)
        stuckTimeout = try read(.stuckTimeout, d.stuckTimeout)
        self = clamped()
    }

    /// Every field limited to its range; non-finite values take the default. Applied on decode and to profile
    /// overrides, so a hand-edited settings file can never crash the pipeline: durations 0…10 s,
    /// `momentumDecayPerFrame` 0…0.999, `velocityWindow` 0.008…1 s, `rotateThreshold` 0…180°, the rest ≥ 0.
    public func clamped() -> GestureConfig {
        let d = GestureConfig()
        let seconds = 0.0...10.0
        let nonNegative = 0.0...Double.greatestFiniteMagnitude
        var c = self
        c.tapMaxDuration = Self.clamp(tapMaxDuration, seconds, default: d.tapMaxDuration)
        c.tapMaxMovement = Self.clamp(tapMaxMovement, nonNegative, default: d.tapMaxMovement)
        c.doubleTapInterval = Self.clamp(doubleTapInterval, seconds, default: d.doubleTapInterval)
        c.longPressDuration = Self.clamp(longPressDuration, seconds, default: d.longPressDuration)
        c.classifyMovement = Self.clamp(classifyMovement, nonNegative, default: d.classifyMovement)
        c.pinchThreshold = Self.clamp(pinchThreshold, nonNegative, default: d.pinchThreshold)
        c.rotateThreshold = Self.clamp(rotateThreshold, 0...180, default: d.rotateThreshold)
        c.momentumMinVelocity = Self.clamp(momentumMinVelocity, nonNegative, default: d.momentumMinVelocity)
        c.velocityWindow = Self.clamp(velocityWindow, 0.008...1.0, default: d.velocityWindow)
        c.momentumDecayPerFrame = Self.clamp(momentumDecayPerFrame, 0...0.999, default: d.momentumDecayPerFrame)
        c.momentumStopVelocity = Self.clamp(momentumStopVelocity, nonNegative, default: d.momentumStopVelocity)
        c.swipeDistance = Self.clamp(swipeDistance, nonNegative, default: d.swipeDistance)
        c.swipeMaxDuration = Self.clamp(swipeMaxDuration, seconds, default: d.swipeMaxDuration)
        c.stuckTimeout = Self.clamp(stuckTimeout, seconds, default: d.stuckTimeout)
        return c
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
