import Foundation
import CoreGraphics

/// Deterministic gesture state machine. Time comes only from the `timestamp` arguments.
public struct GestureEngine: Sendable {
    public var config: GestureConfig

    enum State: Equatable {
        case idle
        case oneFinger(id: Int, start: CGPoint, last: CGPoint, startTime: UInt64)
        case dragging(id: Int, last: CGPoint)
        case twoPending(startCentroid: CGPoint, startDistance: Double, startAngle: Double, startTime: UInt64, last: CGPoint)
        case twoReleasing(startCentroid: CGPoint, startTime: UInt64)
        case scrolling(prevCentroid: CGPoint, prevTime: UInt64, velocity: CGVector)
        case pinching(prevDistance: Double, last: CGPoint)
        case rotating(prevAngle: Double, last: CGPoint)
        /// Three or four fingers are down and may still become a swipe. Losing a finger ends it in `.consumed` (see `finishMulti`).
        case multiPending(count: Int, startCentroid: CGPoint, startTime: UInt64)
        /// One finger is still down after a two-finger gesture ended; it is inert (no drag, no tap) until the count changes.
        case oneRemaining
        /// Fingers are down but nothing more will be recognized until all lift.
        case consumed
    }

    struct TapRecord: Equatable {
        var time: UInt64
        var position: CGPoint
    }

    private(set) var state: State = .idle
    private var lastTap: TapRecord?
    private var momentumMayBeRunning = false
    private var trackedIDs: Set<Int> = []

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    public var isIdle: Bool { state == .idle }

    public mutating func update(touches: [ActiveTouch], timestamp: UInt64) -> [Action] {
        let n = touches.count
        if case .consumed = state {
            if n == 0 { state = .idle }
            return []
        }
        if n == expectedCount {
            if n > 0 && Set(touches.map(\.id)) != trackedIDs {
                // Same finger count but a different contact: the old gesture is over, a new one starts.
                let (actions, _) = finishGesture(newCount: 0, timestamp: timestamp)
                return actions + enter(touches, timestamp)
            }
            return continueGesture(touches, timestamp)
        }
        let (actions, enter) = finishGesture(newCount: n, timestamp: timestamp)
        if enter { return actions + self.enter(touches, timestamp) }
        trackedIDs = Set(touches.map(\.id))
        return actions
    }

    public mutating func tick(_ timestamp: UInt64) -> [Action] {
        switch state {
        case .oneFinger(_, _, let last, let startTime):
            if Geometry.seconds(from: startTime, to: timestamp) >= config.longPressDuration {
                state = .consumed
                return [.click(button: .right, at: last, count: 1)]
            }
        case .twoReleasing(_, let startTime):
            if Geometry.seconds(from: startTime, to: timestamp) > config.tapMaxDuration { state = .oneRemaining }
        case .multiPending(_, _, let startTime):
            if Geometry.seconds(from: startTime, to: timestamp) > config.swipeMaxDuration { state = .consumed }
        default:
            break
        }
        return []
    }

    /// Ends any open gesture and returns to idle. Used on device loss, display changes and sleep.
    public mutating func reset() -> [Action] {
        let actions: [Action]
        switch state {
        case .dragging(_, let last): actions = [.drag(phase: .cancelled, to: last)]
        case .scrolling(let prev, _, _): actions = [.scroll(phase: .ended, delta: .zero, at: prev)]
        case .pinching(_, let last): actions = [.magnify(phase: .ended, delta: 0, at: last)]
        case .rotating(_, let last): actions = [.rotate(phase: .ended, degrees: 0, at: last)]
        default: actions = []
        }
        state = .idle
        lastTap = nil
        trackedIDs = []
        momentumMayBeRunning = false
        return actions
    }

    // MARK: - Finger-count bookkeeping

    private var expectedCount: Int {
        switch state {
        case .idle: return 0
        case .oneFinger, .dragging, .twoReleasing, .oneRemaining: return 1
        case .twoPending, .scrolling, .pinching, .rotating: return 2
        case .multiPending(let count, _, _): return count
        case .consumed: return -1
        }
    }

    /// Finishes the current gesture for a changed finger count. Returns the actions and whether `enter` should run.
    private mutating func finishGesture(newCount n: Int, timestamp: UInt64) -> ([Action], Bool) {
        switch state {
        case .idle:
            return ([], true)
        case .oneFinger(_, _, let last, let startTime):
            if n == 0 {
                state = .idle
                return (tapActions(at: last, touchStart: startTime, timestamp: timestamp), false)
            }
            return ([], true)
        case .dragging(_, let last):
            state = .idle
            return ([.drag(phase: .ended, to: last)], n > 0)
        case .twoPending, .twoReleasing, .scrolling, .pinching, .rotating:
            return finishTwoFinger(newCount: n, timestamp: timestamp)
        case .multiPending:
            return finishMulti(newCount: n)
        case .oneRemaining:
            state = .idle
            return ([], n >= 2)
        case .consumed:
            state = n == 0 ? .idle : .consumed
            return ([], false)
        }
    }

    private mutating func finishTwoFinger(newCount n: Int, timestamp: UInt64) -> ([Action], Bool) {
        switch state {
        case .twoPending(let c, _, _, let startTime, _):
            if n == 0 {
                state = .idle
                let isTap = Geometry.seconds(from: startTime, to: timestamp) <= config.tapMaxDuration
                return (isTap ? [.click(button: .right, at: c, count: 1)] : [], false)
            }
            if n == 1 {
                state = .twoReleasing(startCentroid: c, startTime: startTime)
                return ([], false)
            }
            state = .idle
            return ([], true)
        case .twoReleasing(let c, let startTime):
            if n == 0 {
                state = .idle
                let isTap = Geometry.seconds(from: startTime, to: timestamp) <= config.tapMaxDuration
                return (isTap ? [.click(button: .right, at: c, count: 1)] : [], false)
            }
            state = .idle
            return ([], true)
        case .scrolling(let prev, _, let v):
            var out: [Action] = [.scroll(phase: .ended, delta: .zero, at: prev)]
            if hypot(v.dx, v.dy) >= config.momentumMinVelocity {
                out.append(.scrollMomentum(velocity: v, at: prev))
                momentumMayBeRunning = true
            }
            return settle(after: n, out)
        case .pinching(_, let last):
            return settle(after: n, [.magnify(phase: .ended, delta: 0, at: last)])
        case .rotating(_, let last):
            return settle(after: n, [.rotate(phase: .ended, degrees: 0, at: last)])
        default:
            state = n == 0 ? .idle : .consumed
            return ([], false)
        }
    }

    /// After a two-finger gesture ended with `n` fingers remaining: none → idle, one → consumed, three or more → re-enter.
    private mutating func settle(after n: Int, _ actions: [Action]) -> ([Action], Bool) {
        if n == 0 { state = .idle; return (actions, false) }
        if n == 1 { state = .oneRemaining; return (actions, false) }
        state = .idle
        return (actions, true)
    }

    /// Ends a pending three/four-finger gesture. Fewer fingers (also 3 → 2) go to `.consumed` by design:
    /// lifting one finger of a swipe must not start a scroll or pinch with the remaining two.
    private mutating func finishMulti(newCount n: Int) -> ([Action], Bool) {
        guard case .multiPending(let count, _, _) = state else { return ([], false) }
        if n == 0 { state = .idle; return ([], false) }
        if n > count { state = .idle; return ([], true) }   // re-enter with more fingers (or consumed for 5+)
        state = .consumed
        return ([], false)
    }

    private mutating func enter(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        var out: [Action] = []
        trackedIDs = Set(touches.map(\.id))
        if momentumMayBeRunning && !touches.isEmpty {
            out.append(.cancelMomentum)
            momentumMayBeRunning = false
        }
        switch touches.count {
        case 0:
            state = .idle
        case 1:
            let t = touches[0]
            state = .oneFinger(id: t.id, start: t.position, last: t.position, startTime: timestamp)
            out.append(.moveCursor(to: t.position))
        case 2:
            enterTwoFinger(touches, timestamp)
        case 3, 4:
            enterMulti(touches, timestamp)
        default:
            state = .consumed
        }
        return out
    }

    private mutating func enterTwoFinger(_ touches: [ActiveTouch], _ timestamp: UInt64) {
        let c = Geometry.centroid(touches)
        state = .twoPending(startCentroid: c,
                            startDistance: Geometry.pairDistance(touches),
                            startAngle: Geometry.pairAngle(touches),
                            startTime: timestamp,
                            last: c)
    }

    private mutating func enterMulti(_ touches: [ActiveTouch], _ timestamp: UInt64) {
        state = .multiPending(count: touches.count, startCentroid: Geometry.centroid(touches), startTime: timestamp)
    }

    // MARK: - Same finger count

    private mutating func continueGesture(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        switch state {
        case .idle, .consumed, .twoReleasing, .oneRemaining:
            return []
        case .oneFinger(let id, let start, _, let startTime):
            let p = touches[0].position
            if Geometry.distance(p, start) > config.tapMaxMovement {
                state = .dragging(id: id, last: p)
                return [.drag(phase: .began, to: start), .drag(phase: .changed, to: p)]
            }
            if Geometry.seconds(from: startTime, to: timestamp) >= config.longPressDuration {
                state = .consumed
                return [.click(button: .right, at: p, count: 1)]
            }
            state = .oneFinger(id: id, start: start, last: p, startTime: startTime)
            return []
        case .dragging(let id, _):
            let p = touches[0].position
            state = .dragging(id: id, last: p)
            return [.drag(phase: .changed, to: p)]
        case .twoPending, .scrolling, .pinching, .rotating:
            return continueTwoFinger(touches, timestamp)
        case .multiPending:
            return continueMulti(touches, timestamp)
        }
    }

    private mutating func continueTwoFinger(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        let c = Geometry.centroid(touches)
        let d = Geometry.pairDistance(touches)
        let a = Geometry.pairAngle(touches)
        switch state {
        case .twoPending(let c0, let d0, let a0, let startTime, _):
            if abs(d - d0) >= config.pinchThreshold {
                state = .pinching(prevDistance: d, last: c)
                return [.magnify(phase: .began, delta: 0, at: c),
                        .magnify(phase: .changed, delta: d0 > 0 ? d / d0 - 1 : 0, at: c)]
            }
            let da = Geometry.angleDelta(from: a0, to: a)
            if abs(da) >= config.rotateThreshold {
                state = .rotating(prevAngle: a, last: c)
                return [.rotate(phase: .began, degrees: 0, at: c),
                        .rotate(phase: .changed, degrees: -da, at: c)]
            }
            let move = CGVector(dx: c.x - c0.x, dy: c.y - c0.y)
            if hypot(move.dx, move.dy) >= config.classifyMovement {
                let dt = Geometry.seconds(from: startTime, to: timestamp)
                let v = dt > 0 ? CGVector(dx: move.dx / dt, dy: move.dy / dt) : .zero
                state = .scrolling(prevCentroid: c, prevTime: timestamp, velocity: v)
                return [.scroll(phase: .began, delta: .zero, at: c),
                        .scroll(phase: .changed, delta: move, at: c)]
            }
            state = .twoPending(startCentroid: c0, startDistance: d0, startAngle: a0, startTime: startTime, last: c)
            return []
        case .scrolling(let prev, let prevTime, let v0):
            let delta = CGVector(dx: c.x - prev.x, dy: c.y - prev.y)
            let dt = Geometry.seconds(from: prevTime, to: timestamp)
            let v = dt > 0 ? CGVector(dx: delta.dx / dt, dy: delta.dy / dt) : v0
            state = .scrolling(prevCentroid: c, prevTime: dt > 0 ? timestamp : prevTime, velocity: v)
            return [.scroll(phase: .changed, delta: delta, at: c)]
        case .pinching(let d0, _):
            state = .pinching(prevDistance: d, last: c)
            return [.magnify(phase: .changed, delta: d0 > 0 ? d / d0 - 1 : 0, at: c)]
        case .rotating(let a0, _):
            state = .rotating(prevAngle: a, last: c)
            return [.rotate(phase: .changed, degrees: -Geometry.angleDelta(from: a0, to: a), at: c)]
        default:
            return []
        }
    }

    private mutating func continueMulti(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        guard case .multiPending(let count, let c0, let startTime) = state else { return [] }
        if Geometry.seconds(from: startTime, to: timestamp) > config.swipeMaxDuration {
            state = .consumed
            return []
        }
        let c = Geometry.centroid(touches)
        let dx = c.x - c0.x
        let dy = c.y - c0.y
        guard hypot(dx, dy) >= config.swipeDistance else { return [] }
        state = .consumed
        let direction: SwipeDirection
        if abs(dx) >= abs(dy) {
            direction = dx > 0 ? .right : .left
        } else {
            direction = dy > 0 ? .down : .up
        }
        return [.swipe(fingers: count, direction: direction)]
    }

    // MARK: - Taps

    private mutating func tapActions(at position: CGPoint, touchStart: UInt64, timestamp: UInt64) -> [Action] {
        var count = 1
        if let previous = lastTap,
           Geometry.seconds(from: previous.time, to: touchStart) <= config.doubleTapInterval,
           Geometry.distance(previous.position, position) <= config.tapMaxMovement {
            count = 2
            lastTap = nil
        } else {
            lastTap = TapRecord(time: timestamp, position: position)
        }
        return [.click(button: .left, at: position, count: count)]
    }
}
