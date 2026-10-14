import Foundation
import CoreGraphics

/// Per-device calibration. Orientation is applied to normalized coordinates before scale/offset.
public struct Calibration: Codable, Equatable, Sendable {
    /// 0, 90, 180 or 270 degrees.
    public var orientation: Int
    public var scaleX: Double
    public var scaleY: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(orientation: Int = 0, scaleX: Double = 1, scaleY: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.orientation = orientation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// Hand-edited values are normalised: see `normalisedOrientation`; non-finite scales and offsets take the default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read(_ key: CodingKeys, default fallback: Double) throws -> Double {
            let value = try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
            return value.isFinite ? value : fallback
        }
        orientation = Self.normalisedOrientation(try c.decodeIfPresent(Int.self, forKey: .orientation) ?? 0)
        scaleX = try read(.scaleX, default: 1)
        scaleY = try read(.scaleY, default: 1)
        offsetX = try read(.offsetX, default: 0)
        offsetY = try read(.offsetY, default: 0)
    }

    /// Reduces `degrees` modulo 360 (450 → 90, -90 → 270). A result that is not 0, 90, 180 or 270 becomes 0;
    /// it is not rounded to the nearest quarter turn.
    static func normalisedOrientation(_ degrees: Int) -> Int {
        let reduced = ((degrees % 360) + 360) % 360
        return [0, 90, 180, 270].contains(reduced) ? reduced : 0
    }
}

public struct MappingConfig: Equatable, Sendable {
    public var logicalMaxX: Int
    public var logicalMaxY: Int
    /// Global CoreGraphics display coordinates (origin top-left of the main display).
    public var displayFrame: CGRect
    public var calibration: Calibration

    public init(logicalMaxX: Int, logicalMaxY: Int, displayFrame: CGRect, calibration: Calibration) {
        self.logicalMaxX = logicalMaxX
        self.logicalMaxY = logicalMaxY
        self.displayFrame = displayFrame
        self.calibration = calibration
    }
}

/// A contact in global screen coordinates.
public struct Contact: Equatable, Sendable {
    public var id: Int
    public var position: CGPoint
    public var down: Bool

    public init(id: Int, position: CGPoint, down: Bool) {
        self.id = id
        self.position = position
        self.down = down
    }
}

public struct ScreenFrame: Equatable, Sendable {
    public var timestamp: UInt64
    public var contacts: [Contact]

    public init(timestamp: UInt64, contacts: [Contact]) {
        self.timestamp = timestamp
        self.contacts = contacts
    }
}

public struct DisplayMapper: Sendable {
    public var config: MappingConfig

    public init(config: MappingConfig) {
        self.config = config
    }

    public func map(_ frame: TouchFrame) -> ScreenFrame {
        ScreenFrame(timestamp: frame.timestamp, contacts: frame.contacts.map {
            Contact(id: $0.id, position: map(x: $0.x, y: $0.y), down: $0.down)
        })
    }

    public func map(x: Int, y: Int) -> CGPoint {
        var nx = Double(x) / Double(max(config.logicalMaxX, 1))
        var ny = Double(y) / Double(max(config.logicalMaxY, 1))
        switch config.calibration.orientation {
        case 90: (nx, ny) = (1 - ny, nx)
        case 180: (nx, ny) = (1 - nx, 1 - ny)
        case 270: (nx, ny) = (ny, 1 - nx)
        default: break
        }
        nx = nx * config.calibration.scaleX + config.calibration.offsetX
        ny = ny * config.calibration.scaleY + config.calibration.offsetY
        nx = min(max(nx, 0), 1)
        ny = min(max(ny, 0), 1)
        let f = config.displayFrame
        return CGPoint(x: f.origin.x + nx * f.width, y: f.origin.y + ny * f.height)
    }
}
