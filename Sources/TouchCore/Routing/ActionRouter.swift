import Foundation
import CoreGraphics

/// Maps engine actions to commands through the effective profile of the frontmost application.
/// Continuous gestures remember the decision made at `began` until their next `began`, so a drag or scroll
/// never switches halfway between pass-through and suppressed — also when the profile changes mid-gesture
/// (`init(profile:continuing:)`).
public struct ActionRouter: Sendable {
    public var profile: EffectiveProfile
    /// Continuous kinds whose last `began` was not passed through. Magnify and rotate are tracked under
    /// `.spread` and `.rotateLeft` respectively, because their direction is only known from `changed` on.
    private(set) var suppressed: Set<GestureKind> = []
    /// Last cursor position seen; mouse clicks bound to swipes happen here.
    private var cursor: CGPoint = .zero

    public init(profile: EffectiveProfile) {
        self.profile = profile
    }

    /// A router for a new profile that keeps the gesture state of `previous`.
    public init(profile: EffectiveProfile, continuing previous: ActionRouter) {
        self.profile = profile
        self.suppressed = previous.suppressed
        self.cursor = previous.cursor
    }

    public mutating func route(_ action: Action, context: RouterContext) -> [Command] {
        switch action {
        case .moveCursor(let p):
            cursor = p
            return [.moveCursor(p)]
        case .click(let button, let p, let count, let source):
            cursor = p
            let kind: GestureKind
            switch source {
            case .tap: kind = count >= 2 ? .doubleTap : .tap
            case .longPress: kind = .press
            case .twoFingerTap: kind = .twoFingerTap
            }
            return discrete(kind, passThrough: [.click(button, p, count)], at: p)
        case .drag(let phase, let p):
            cursor = p
            return continuous(.drag, phase: phase, at: p) { [.drag(phase, p)] }
        case .scroll(let phase, let delta, let p):
            let sign = scrollSign
            return continuous(.twoFingerDrag, phase: phase, at: p) {
                [.scroll(phase, CGVector(dx: delta.dx * sign, dy: delta.dy * sign), p)]
            }
        case .scrollMomentum(let v, let p):
            let binding = profile.binding(.twoFingerDrag)
            guard !suppressed.contains(.twoFingerDrag), binding.enabled, binding.action == .passThrough, binding.momentum ?? true else { return [] }
            let sign = scrollSign
            return [.scrollMomentum(CGVector(dx: v.dx * sign, dy: v.dy * sign), p)]
        case .cancelMomentum:
            return [.cancelMomentum]
        case .magnify(let phase, let delta, let p):
            return twoWay(key: .spread, phase: phase, value: delta, positive: .spread, negative: .pinch) { [.magnify(phase, delta, p)] }
        case .rotate(let phase, let degrees, let p):
            return twoWay(key: .rotateLeft, phase: phase, value: degrees, positive: .rotateLeft, negative: .rotateRight) { [.rotate(phase, degrees, p)] }
        case .swipe(let fingers, let direction):
            guard let kind = GestureKind.swipe(fingers: fingers, direction: direction) else { return [] }
            return discrete(kind, passThrough: [], at: cursor)   // swipes have no native behaviour
        }
    }

    private var scrollSign: Double {
        (profile.binding(.twoFingerDrag).naturalScrolling ?? true) ? 1 : -1
    }

    private func discrete(_ kind: GestureKind, passThrough: [Command], at p: CGPoint) -> [Command] {
        let binding = profile.binding(kind)
        guard binding.enabled else { return [] }
        return commands(for: binding.action, passThrough: passThrough, at: p)
    }

    private func commands(for action: GestureAction, passThrough: [Command], at p: CGPoint) -> [Command] {
        switch action {
        case .none: return []
        case .passThrough: return passThrough
        case .mouseClick(let button, let count): return [.click(button, p, count)]
        case .keystroke(let key): return [.key(key)]
        case .systemAction(let system): return [.key(system.keyCommand)]
        case .openFile(let path): return [.openFile(path)]
        }
    }

    /// `began` decides: pass-through passes every phase, none/disabled drops every phase, a discrete action
    /// fires once and drops the rest.
    private mutating func continuous(_ kind: GestureKind, phase: GesturePhase, at p: CGPoint, passThrough: () -> [Command]) -> [Command] {
        if phase == .began {
            let binding = profile.binding(kind)
            if binding.enabled, binding.action == .passThrough {
                suppressed.remove(kind)
                return passThrough()
            }
            suppressed.insert(kind)
            guard binding.enabled else { return [] }
            return commands(for: binding.action, passThrough: [], at: p)
        }
        return suppressed.contains(kind) ? [] : passThrough()
    }

    /// Magnify and rotate: `began` and `ended` pass when either direction is pass-through; each `changed`
    /// passes only when its own direction is. In Part A only pass-through and none are effective for these kinds.
    private mutating func twoWay(key: GestureKind, phase: GesturePhase, value: Double, positive: GestureKind, negative: GestureKind,
                                 passThrough: () -> [Command]) -> [Command] {
        let pos = profile.binding(positive)
        let neg = profile.binding(negative)
        let positivePasses = pos.enabled && pos.action == .passThrough
        let negativePasses = neg.enabled && neg.action == .passThrough
        switch phase {
        case .began:
            if positivePasses || negativePasses { suppressed.remove(key) } else { suppressed.insert(key) }
            return suppressed.contains(key) ? [] : passThrough()
        case .changed:
            guard !suppressed.contains(key) else { return [] }
            return (value >= 0 ? positivePasses : negativePasses) ? passThrough() : []
        case .ended, .cancelled:
            return suppressed.contains(key) ? [] : passThrough()
        }
    }
}
