import Foundation

/// `GestureConfig` with every field optional; nil inherits from the profile below.
public struct GestureConfigOverrides: Codable, Equatable, Sendable {
    public var tapMaxDuration: Double?
    public var tapMaxMovement: Double?
    public var doubleTapInterval: Double?
    public var longPressDuration: Double?
    public var classifyMovement: Double?
    public var pinchThreshold: Double?
    public var rotateThreshold: Double?
    public var momentumMinVelocity: Double?
    public var velocityWindow: Double?
    public var momentumDecayPerFrame: Double?
    public var momentumStopVelocity: Double?
    public var swipeDistance: Double?
    public var swipeMaxDuration: Double?
    public var stuckTimeout: Double?

    public init() {}

    /// Overrides every field with the values of `config` (used when migrating a flat schema-1 config).
    public init(full config: GestureConfig) {
        for field in GestureConfigField.all {
            self[keyPath: field.override] = config[keyPath: field.value]
        }
    }

    public var isEmpty: Bool { self == GestureConfigOverrides() }

    /// `base` with every non-nil field replaced, then clamped.
    public func apply(to base: GestureConfig) -> GestureConfig {
        var result = base
        for field in GestureConfigField.all {
            if let value = self[keyPath: field.override] { result[keyPath: field.value] = value }
        }
        return result.clamped()
    }
}

/// One tunable of `GestureConfig`, for settings UIs: label, unit and where the value lives.
public struct GestureConfigField: Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let unit: String
    public let step: Double
    public let value: WritableKeyPath<GestureConfig, Double> & Sendable
    public let override: WritableKeyPath<GestureConfigOverrides, Double?> & Sendable

    public static let all: [GestureConfigField] = [
        GestureConfigField(label: "Tap max duration", unit: "s", step: 0.05, value: \.tapMaxDuration, override: \.tapMaxDuration),
        GestureConfigField(label: "Tap max movement", unit: "pt", step: 1, value: \.tapMaxMovement, override: \.tapMaxMovement),
        GestureConfigField(label: "Double tap interval", unit: "s", step: 0.05, value: \.doubleTapInterval, override: \.doubleTapInterval),
        GestureConfigField(label: "Long press duration", unit: "s", step: 0.05, value: \.longPressDuration, override: \.longPressDuration),
        GestureConfigField(label: "Scroll classification movement", unit: "pt", step: 1, value: \.classifyMovement, override: \.classifyMovement),
        GestureConfigField(label: "Pinch threshold", unit: "pt", step: 1, value: \.pinchThreshold, override: \.pinchThreshold),
        GestureConfigField(label: "Rotate threshold", unit: "°", step: 1, value: \.rotateThreshold, override: \.rotateThreshold),
        GestureConfigField(label: "Momentum minimum velocity", unit: "pt/s", step: 10, value: \.momentumMinVelocity, override: \.momentumMinVelocity),
        GestureConfigField(label: "Velocity window", unit: "s", step: 0.01, value: \.velocityWindow, override: \.velocityWindow),
        GestureConfigField(label: "Momentum decay per frame", unit: "", step: 0.005, value: \.momentumDecayPerFrame, override: \.momentumDecayPerFrame),
        GestureConfigField(label: "Momentum stop velocity", unit: "pt/s", step: 5, value: \.momentumStopVelocity, override: \.momentumStopVelocity),
        GestureConfigField(label: "Swipe distance", unit: "pt", step: 5, value: \.swipeDistance, override: \.swipeDistance),
        GestureConfigField(label: "Swipe max duration", unit: "s", step: 0.05, value: \.swipeMaxDuration, override: \.swipeMaxDuration),
        GestureConfigField(label: "Stuck contact timeout", unit: "s", step: 0.05, value: \.stuckTimeout, override: \.stuckTimeout),
    ]
}

/// The default profile (`bundleID == nil`) or the profile of one application. Only deviations are stored.
public struct GestureProfile: Codable, Equatable, Sendable, Identifiable {
    public static let defaultID = "default"

    public var id: String { bundleID ?? Self.defaultID }
    public var bundleID: String?
    public var displayName: String
    public var bindings: [GestureKind: GestureBinding]
    public var config: GestureConfigOverrides

    public init(bundleID: String? = nil, displayName: String = "Default",
                bindings: [GestureKind: GestureBinding] = [:], config: GestureConfigOverrides = GestureConfigOverrides()) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.bindings = bindings
        self.config = config
    }

    private enum CodingKeys: String, CodingKey { case bundleID, displayName, bindings, config }

    /// Lenient: unknown gesture kinds are dropped (a newer version may have written them), unknown actions
    /// fall back to `passThrough` inside `GestureBinding`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? bundleID ?? "Default"
        let raw = try c.decodeIfPresent([String: GestureBinding].self, forKey: .bindings) ?? [:]
        var bindings: [GestureKind: GestureBinding] = [:]
        for (key, binding) in raw {
            if let kind = GestureKind(rawValue: key) { bindings[kind] = binding }
        }
        self.bindings = bindings
        config = try c.decodeIfPresent(GestureConfigOverrides.self, forKey: .config) ?? GestureConfigOverrides()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(bundleID, forKey: .bundleID)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(bindings, forKey: .bindings)
        try c.encode(config, forKey: .config)
    }
}
