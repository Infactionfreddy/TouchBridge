import Foundation
import CoreGraphics

/// Maps gesture actions to commands using the default gesture set.
/// `context.frontmostBundleID` is accepted now so per-application sets can be added without changing callers.
public struct ActionRouter: Sendable {
    public var naturalScrolling: Bool

    public init(naturalScrolling: Bool = true) {
        self.naturalScrolling = naturalScrolling
    }

    public func route(_ action: Action, context: RouterContext) -> [Command] {
        let sign: Double = naturalScrolling ? 1 : -1
        switch action {
        case .moveCursor(let p):
            return [.moveCursor(p)]
        case .click(let button, let p, let count, _):
            return [.click(button, p, count)]
        case .drag(let phase, let p):
            return [.drag(phase, p)]
        case .scroll(let phase, let delta, let p):
            return [.scroll(phase, CGVector(dx: delta.dx * sign, dy: delta.dy * sign), p)]
        case .scrollMomentum(let v, let p):
            return [.scrollMomentum(CGVector(dx: v.dx * sign, dy: v.dy * sign), p)]
        case .cancelMomentum:
            return [.cancelMomentum]
        case .magnify(let phase, let delta, let p):
            return [.magnify(phase, delta, p)]
        case .rotate(let phase, let degrees, let p):
            return [.rotate(phase, degrees, p)]
        case .swipe(_, let direction):
            switch direction {
            case .up: return [.key(.missionControl)]
            case .down: return [.key(.appExpose)]
            case .left: return [.key(.spaceRight)]   // fingers move left → content moves left → next space
            case .right: return [.key(.spaceLeft)]
            }
        }
    }
}
