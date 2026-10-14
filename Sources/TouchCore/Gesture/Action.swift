import Foundation
import CoreGraphics

public enum GesturePhase: Sendable, Equatable {
    case began, changed, ended, cancelled
}

public enum MouseButton: Sendable, Equatable {
    case left, right
}

public enum SwipeDirection: Sendable, Equatable {
    case up, down, left, right
}

/// What the gesture engine wants to happen. Positions are global screen coordinates.
public enum Action: Equatable, Sendable {
    case moveCursor(to: CGPoint)
    case click(button: MouseButton, at: CGPoint, count: Int)
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
