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
        case multiPending(count: Int, startCentroid: CGPoint, startTime: UInt64)
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
            return continueGesture(touches, timestamp)
        }
        let (actions, enter) = finishGesture(newCount: n, timestamp: timestamp)
        return enter ? actions + self.enter(touches, timestamp) : actions
    }

    public mutating func tick(_ timestamp: UInt64) -> [Action] {
        switch state {
        case .oneFinger(_, _, let last, let startTime):
            if Geometry.seconds(from: startTime, to: timestamp) >= config.longPressDuration {
                state = .consumed
                return [.click(button: .right, at: last, count: 1)]
            }
        case .twoReleasing(_, let startTime):
            if Geometry.seconds(from: startTime, to: timestamp) > config.tapMaxDuration { state = .consumed }
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
        return actions
    }

    // MARK: - Finger-count bookkeeping

    private var expectedCount: Int {
        switch state {
        case .idle: return 0
        case .oneFinger, .dragging, .twoReleasing: return 1
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
        case .consumed:
            state = n == 0 ? .idle : .consumed
            return ([], false)
        }
    }

    // Replaced in Task 8.
    private mutating func finishTwoFinger(newCount n: Int, timestamp: UInt64) -> ([Action], Bool) {
        state = n == 0 ? .idle : .consumed
        return ([], false)
    }

    // Replaced in Task 9.
    private mutating func finishMulti(newCount n: Int) -> ([Action], Bool) {
        state = n == 0 ? .idle : .consumed
        return ([], false)
    }

    private mutating func enter(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        var out: [Action] = []
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

    // Replaced in Task 8.
    private mutating func enterTwoFinger(_ touches: [ActiveTouch], _ timestamp: UInt64) {
        state = .consumed
    }

    // Replaced in Task 9.
    private mutating func enterMulti(_ touches: [ActiveTouch], _ timestamp: UInt64) {
        state = .consumed
    }

    // MARK: - Same finger count

    private mutating func continueGesture(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        switch state {
        case .idle, .consumed, .twoReleasing:
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

    // Replaced in Task 8.
    private mutating func continueTwoFinger(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        []
    }

    // Replaced in Task 9.
    private mutating func continueMulti(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        []
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
