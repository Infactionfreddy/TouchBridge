import Foundation
import CoreGraphics

/// A keyboard shortcut. `keyCode` is a macOS virtual key code (kVK_*).
public struct KeyCommand: Equatable, Sendable, Codable {
    public var keyCode: UInt16
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var command: Bool

    public init(keyCode: UInt16, control: Bool = false, option: Bool = false, shift: Bool = false, command: Bool = false) {
        self.keyCode = keyCode
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
    }

    public static let missionControl = KeyCommand(keyCode: 126, control: true) // ⌃↑
    public static let appExpose = KeyCommand(keyCode: 125, control: true)      // ⌃↓
    public static let spaceLeft = KeyCommand(keyCode: 123, control: true)      // ⌃←
    public static let spaceRight = KeyCommand(keyCode: 124, control: true)     // ⌃→
    public static let showDesktop = KeyCommand(keyCode: 103)                 // F11
}

/// What the injector executes. Produced by `ActionRouter`.
public enum Command: Equatable, Sendable {
    case moveCursor(CGPoint)
    case click(MouseButton, CGPoint, Int)
    case drag(GesturePhase, CGPoint)
    case scroll(GesturePhase, CGVector, CGPoint)
    case scrollMomentum(CGVector, CGPoint)
    case cancelMomentum
    case magnify(GesturePhase, Double, CGPoint)
    case rotate(GesturePhase, Double, CGPoint)
    case key(KeyCommand)
    /// Opens a file or application; executed by the app layer, not the injector.
    case openFile(String)
}

public struct RouterContext: Equatable, Sendable {
    public var frontmostBundleID: String?

    public init(frontmostBundleID: String? = nil) {
        self.frontmostBundleID = frontmostBundleID
    }
}
