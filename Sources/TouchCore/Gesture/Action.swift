import Foundation
import CoreGraphics

public enum GesturePhase: Sendable, Equatable {
    case began, changed, ended, cancelled
}

/// Logical mouse buttons. `middle`, `back` and `forward` map to the "other" mouse events (button numbers 2, 3, 4).
public enum MouseButton: String, Codable, Sendable, Equatable, CaseIterable {
    case left, right, middle, back, forward

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .middle: return "Middle"
        case .back: return "Back"
        case .forward: return "Forward"
        }
    }
}

/// Which gesture produced a click; the router looks up that gesture's binding.
public enum ClickSource: Sendable, Equatable {
    /// One-finger tap (`count` 1) or double tap (`count` 2).
    case tap
    /// One finger resting longer than `longPressDuration`.
    case longPress
    case twoFingerTap
}

public enum SwipeDirection: Sendable, Equatable {
    case up, down, left, right
}

/// What the gesture engine wants to happen. Positions are global screen coordinates.
public enum Action: Equatable, Sendable {
    case moveCursor(to: CGPoint)
    case click(button: MouseButton, at: CGPoint, count: Int, source: ClickSource)
    case drag(phase: GesturePhase, to: CGPoint)
    /// `delta` in points, content-follows-finger direction (natural). Router applies the user setting.
    case scroll(phase: GesturePhase, delta: CGVector, at: CGPoint)
    /// Velocity in points per second at lift-off.
    case scrollMomentum(velocity: CGVector, at: CGPoint)
    case cancelMomentum
    /// `delta` = distance_now / distance_prev − 1 (AppKit magnification semantics).
    case magnify(phase: GesturePhase, delta: Double, at: CGPoint)
    /// Degrees, counter-clockwise positive (AppKit rotation semantics).
    case rotate(phase: GesturePhase, degrees: Double, at: CGPoint)
    case swipe(fingers: Int, direction: SwipeDirection)
}
