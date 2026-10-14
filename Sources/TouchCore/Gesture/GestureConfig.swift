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

    /// Values are clamped so a hand-edited settings file can never crash the pipeline:
    /// durations to 0…10 s, `momentumDecayPerFrame` to 0…0.999, distances and velocities to ≥ 0,
    /// `rotateThreshold` to 0…180 degrees. Missing or non-finite values take the default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureConfig()
        func read(_ key: CodingKeys) throws -> Double? { try c.decodeIfPresent(Double.self, forKey: key) }
        let seconds = 0.0...10.0
        let nonNegative = 0.0...Double.greatestFiniteMagnitude
        tapMaxDuration = Self.clamp(try read(.tapMaxDuration), seconds, default: d.tapMaxDuration)
        tapMaxMovement = Self.clamp(try read(.tapMaxMovement), nonNegative, default: d.tapMaxMovement)
        doubleTapInterval = Self.clamp(try read(.doubleTapInterval), seconds, default: d.doubleTapInterval)
        longPressDuration = Self.clamp(try read(.longPressDuration), seconds, default: d.longPressDuration)
        classifyMovement = Self.clamp(try read(.classifyMovement), nonNegative, default: d.classifyMovement)
        pinchThreshold = Self.clamp(try read(.pinchThreshold), nonNegative, default: d.pinchThreshold)
        rotateThreshold = Self.clamp(try read(.rotateThreshold), 0...180, default: d.rotateThreshold)
        momentumMinVelocity = Self.clamp(try read(.momentumMinVelocity), nonNegative, default: d.momentumMinVelocity)
        momentumDecayPerFrame = Self.clamp(try read(.momentumDecayPerFrame), 0...0.999, default: d.momentumDecayPerFrame)
        momentumStopVelocity = Self.clamp(try read(.momentumStopVelocity), nonNegative, default: d.momentumStopVelocity)
        swipeDistance = Self.clamp(try read(.swipeDistance), nonNegative, default: d.swipeDistance)
        swipeMaxDuration = Self.clamp(try read(.swipeMaxDuration), seconds, default: d.swipeMaxDuration)
        stuckTimeout = Self.clamp(try read(.stuckTimeout), seconds, default: d.stuckTimeout)
    }

    /// `value` limited to `range`; `fallback` when it is missing or not finite.
    private static func clamp(_ value: Double?, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
