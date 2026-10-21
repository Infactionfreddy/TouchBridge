import Foundation
import CoreGraphics
import os
import TouchCore

/// Turns `Command`s into CGEvents posted at the HID event tap. All methods must be called on `queue`.
public final class EventInjector: @unchecked Sendable {
    /// Written to `eventSourceUserData` of every posted event ("TBRG"), so an event tap can recognise our own events.
    public static let marker: Int64 = 0x5442_5247

    static let momentumBegin: Int64 = 1
    static let momentumContinue: Int64 = 2
    static let momentumEnd: Int64 = 3

    public var momentum: MomentumGenerator

    private let queue: DispatchQueue
    private let source: CGEventSource?
    private let logger = Logger(subsystem: "org.touchbridge", category: "inject")
    private var momentumTimer: DispatchSourceTimer?
    private var momentumFrames: [CGVector] = []
    private var momentumIndex = 0
    private var momentumLocation = CGPoint.zero
    private var scrollRemainder = CGVector.zero
    private var leftButtonDown = false

    public init(queue: DispatchQueue, momentum: MomentumGenerator = MomentumGenerator()) {
        self.queue = queue
        self.momentum = momentum
        self.source = CGEventSource(stateID: .hidSystemState)
    }

    public func perform(_ command: Command) {
        switch command {
        case .moveCursor(let p):
            post(Self.mouseEvent(.mouseMoved, at: p, button: .left, clickCount: 0, source: source))
        case .click(let button, let p, let count):
            let down: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
            let up: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
            let cgButton: CGMouseButton = button == .left ? .left : .right
            post(Self.mouseEvent(.mouseMoved, at: p, button: .left, clickCount: 0, source: source))
            post(Self.mouseEvent(down, at: p, button: cgButton, clickCount: count, source: source))
            post(Self.mouseEvent(up, at: p, button: cgButton, clickCount: count, source: source))
        case .drag(let phase, let p):
            switch phase {
            case .began:
                post(Self.mouseEvent(.mouseMoved, at: p, button: .left, clickCount: 0, source: source))
                post(Self.mouseEvent(.leftMouseDown, at: p, button: .left, clickCount: 1, source: source))
                leftButtonDown = true
            case .changed:
                post(Self.mouseEvent(.leftMouseDragged, at: p, button: .left, clickCount: 1, source: source))
            case .ended, .cancelled:
                post(Self.mouseEvent(.leftMouseUp, at: p, button: .left, clickCount: 1, source: source))
                leftButtonDown = false
            }
        case .scroll(let phase, let delta, let p):
            if phase == .began {
                stopMomentum(sendEnd: true)
                scrollRemainder = .zero
            }
            let whole = Self.splitWholePoints(delta, remainder: &scrollRemainder)
            post(Self.scrollEvent(delta: delta, pointDelta: whole, at: p, phase: phase, momentum: nil, source: source))
        case .scrollMomentum(let velocity, let p):
            startMomentum(velocity: velocity, at: p)
        case .cancelMomentum:
            stopMomentum(sendEnd: true)
        case .magnify(let phase, let delta, let p):
            post(Self.gestureEvent(hidType: GestureEventFields.hidTypeZoom, phase: phase, value: delta, at: p, source: source))
        case .rotate(let phase, let degrees, let p):
            post(Self.gestureEvent(hidType: GestureEventFields.hidTypeRotation, phase: phase, value: degrees, at: p, source: source))
        case .key(let key):
            for event in Self.keyEvents(key, source: source) { post(event) }
        }
    }

    /// Releases a held mouse button and stops momentum. Used on device loss, sleep and shutdown.
    public func releaseAll() {
        stopMomentum(sendEnd: true)
        if leftButtonDown {
            let location = CGEvent(source: nil)?.location ?? .zero
            post(Self.mouseEvent(.leftMouseUp, at: location, button: .left, clickCount: 1, source: source))
            leftButtonDown = false
        }
    }

    // MARK: - Momentum

    private func startMomentum(velocity: CGVector, at p: CGPoint) {
        stopMomentum(sendEnd: false)
        momentumFrames = momentum.frames(initialVelocity: velocity)
        guard !momentumFrames.isEmpty else { return }
        momentumIndex = 0
        momentumLocation = p
        scrollRemainder = .zero
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / momentum.frameRate, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.momentumTick() }
        momentumTimer = timer
        timer.resume()
    }

    private func momentumTick() {
        guard momentumIndex < momentumFrames.count else {
            stopMomentum(sendEnd: true)
            return
        }
        let phase = momentumIndex == 0 ? Self.momentumBegin : Self.momentumContinue
        let frame = momentumFrames[momentumIndex]
        let whole = Self.splitWholePoints(frame, remainder: &scrollRemainder)
        post(Self.scrollEvent(delta: frame, pointDelta: whole, at: momentumLocation, phase: nil, momentum: phase, source: source))
        momentumIndex += 1
    }

    private func stopMomentum(sendEnd: Bool) {
        guard let timer = momentumTimer else { return }
        timer.cancel()
        momentumTimer = nil
        momentumFrames = []
        if sendEnd {
            post(Self.scrollEvent(delta: .zero, at: momentumLocation, phase: nil, momentum: Self.momentumEnd, source: source))
        }
    }

    // MARK: - Builders (static for testability)

    static func mouseEvent(_ type: CGEventType, at p: CGPoint, button: CGMouseButton, clickCount: Int, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return nil }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        return event
    }

    /// `delta` is the exact movement in points; it goes into the fixed-point fields that precise-scrolling
    /// consumers read (`NSEvent.scrollingDeltaX/Y`), so fractional deltas are not lost to rounding.
    /// `pointDelta` is the whole-point part for the integer fields that legacy consumers read; callers carry
    /// the remainder across events. When nil, `delta` truncated toward zero is used.
    static func scrollEvent(delta: CGVector, pointDelta: CGVector? = nil, at p: CGPoint, phase: GesturePhase?, momentum: Int64?, source: CGEventSource?) -> CGEvent? {
        let points = pointDelta ?? CGVector(dx: delta.dx.rounded(.towardZero), dy: delta.dy.rounded(.towardZero))
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: clampedInt32(points.dy), wheel2: clampedInt32(points.dx), wheel3: 0) else { return nil }
        event.location = p
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: clampedFixedPoint(delta.dy))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: clampedFixedPoint(delta.dx))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if let phase { event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhaseValue(phase)) }
        if let momentum { event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum) }
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        return event
    }

    /// A wheel delta as `Int32`, truncated toward zero and saturated at the type's bounds instead of trapping; NaN becomes 0.
    static func clampedInt32(_ x: Double) -> Int32 {
        guard !x.isNaN else { return 0 }
        return Int32(min(max(x, Double(Int32.min)), Double(Int32.max)))
    }

    /// The fixed-point scroll fields hold 16.16 values; keep the magnitude well inside that range.
    static func clampedFixedPoint(_ x: Double) -> Double {
        guard !x.isNaN else { return 0 }
        return min(max(x, -30_000), 30_000)
    }

    static func scrollPhaseValue(_ phase: GesturePhase) -> Int64 {
        switch phase {
        case .began: return 1
        case .changed: return 2
        case .ended: return 4
        case .cancelled: return 8
        }
    }

    static func gesturePhaseValue(_ phase: GesturePhase) -> Int64 {
        switch phase {
        case .began: return GestureEventFields.phaseBegan
        case .changed: return GestureEventFields.phaseChanged
        case .ended: return GestureEventFields.phaseEnded
        case .cancelled: return GestureEventFields.phaseCancelled
        }
    }

    static func gestureEvent(hidType: Int64, phase: GesturePhase, value: Double, at p: CGPoint, source: CGEventSource?) -> CGEvent? {
        // A mouse event supplies a valid timestamp and location; the fields below turn it into a gesture event.
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left) else { return nil }
        event.flags = []
        event.setIntegerValueField(GestureEventFields.eventTypeField, value: GestureEventFields.gestureEventType)
        event.setIntegerValueField(GestureEventFields.subtypeField, value: GestureEventFields.subtypeValue)
        event.setIntegerValueField(GestureEventFields.field101, value: GestureEventFields.field101Value)
        event.setIntegerValueField(GestureEventFields.hidTypeField, value: hidType)
        if hidType == GestureEventFields.hidTypeZoom {
            event.setDoubleValueField(GestureEventFields.zoomValueField, value: value)
        } else {
            event.setDoubleValueField(GestureEventFields.rotationValueField, value: value)
        }
        event.setIntegerValueField(GestureEventFields.phaseField, value: gesturePhaseValue(phase))
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        return event
    }

    static func keyEvents(_ key: KeyCommand, source: CGEventSource?) -> [CGEvent] {
        var flags: CGEventFlags = []
        if key.control { flags.insert(.maskControl) }
        if key.option { flags.insert(.maskAlternate) }
        if key.shift { flags.insert(.maskShift) }
        if key.command { flags.insert(.maskCommand) }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: false) else { return [] }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: marker)
        up.setIntegerValueField(.eventSourceUserData, value: marker)
        return [down, up]
    }

    /// Returns the whole-point part of `delta` plus the carried remainder; keeps the fraction for the next call.
    static func splitWholePoints(_ delta: CGVector, remainder: inout CGVector) -> CGVector {
        let total = CGVector(dx: delta.dx + remainder.dx, dy: delta.dy + remainder.dy)
        let whole = CGVector(dx: total.dx.rounded(.towardZero), dy: total.dy.rounded(.towardZero))
        remainder = CGVector(dx: total.dx - whole.dx, dy: total.dy - whole.dy)
        return whole
    }

    private func post(_ event: CGEvent?) {
        guard let event else {
            logger.error("could not create event")
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
