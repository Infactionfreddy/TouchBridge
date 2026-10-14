import Testing
import CoreGraphics
import TouchCore
@testable import TouchInject

@Suite struct EventBuilderTests {
    let source = CGEventSource(stateID: .hidSystemState)
    let p = CGPoint(x: 3100, y: 400)

    @Test func mouseEventCarriesClickCountLocationAndMarker() throws {
        let e = try #require(EventInjector.mouseEvent(.leftMouseDown, at: p, button: .left, clickCount: 2, source: source))
        #expect(e.type == .leftMouseDown)
        #expect(e.location == p)
        #expect(e.getIntegerValueField(.mouseEventClickState) == 2)
        #expect(e.getIntegerValueField(.eventSourceUserData) == EventInjector.marker)
    }

    @Test func scrollEventFields() throws {
        let e = try #require(EventInjector.scrollEvent(delta: CGVector(dx: 3, dy: -7), at: p, phase: .changed, momentum: nil, source: source))
        #expect(e.type == .scrollWheel)
        #expect(e.location == p)
        #expect(e.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
        #expect(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -7)
        #expect(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 3)
        #expect(e.getIntegerValueField(.scrollWheelEventScrollPhase) == 2)
        #expect(e.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0)
        let m = try #require(EventInjector.scrollEvent(delta: .zero, at: p, phase: nil, momentum: EventInjector.momentumEnd, source: source))
        #expect(m.getIntegerValueField(.scrollWheelEventMomentumPhase) == 3)
        #expect(m.getIntegerValueField(.scrollWheelEventScrollPhase) == 0)
    }

    @Test func scrollPhaseValues() {
        #expect(EventInjector.scrollPhaseValue(.began) == 1)
        #expect(EventInjector.scrollPhaseValue(.changed) == 2)
        #expect(EventInjector.scrollPhaseValue(.ended) == 4)
        #expect(EventInjector.scrollPhaseValue(.cancelled) == 8)
    }

    @Test func gestureEventFields() throws {
        let z = try #require(EventInjector.gestureEvent(hidType: GestureEventFields.hidTypeZoom, phase: .changed, value: 0.25, at: p, source: source))
        #expect(z.getIntegerValueField(GestureEventFields.eventTypeField) == 29)
        #expect(z.getIntegerValueField(GestureEventFields.hidTypeField) == 8)
        #expect(abs(z.getDoubleValueField(GestureEventFields.zoomValueField) - 0.25) < 1e-9)
        #expect(z.getIntegerValueField(GestureEventFields.phaseField) == 2)
        #expect(z.flags.isEmpty)
        #expect(z.location == p)
        let r = try #require(EventInjector.gestureEvent(hidType: GestureEventFields.hidTypeRotation, phase: .ended, value: 0, at: p, source: source))
        #expect(r.getIntegerValueField(GestureEventFields.hidTypeField) == 5)
        #expect(r.getIntegerValueField(GestureEventFields.phaseField) == 4)
    }

    @Test func keyEventsAreDownUpWithFlags() {
        let events = EventInjector.keyEvents(.missionControl, source: source)
        #expect(events.count == 2)
        #expect(events[0].type == .keyDown)
        #expect(events[1].type == .keyUp)
        #expect(events[0].getIntegerValueField(.keyboardEventKeycode) == 126)
        #expect(events[0].flags.contains(.maskControl))
        #expect(!events[0].flags.contains(.maskCommand))
    }

    @Test func fractionalDeltasAccumulate() {
        var remainder = CGVector.zero
        #expect(EventInjector.splitWholePoints(CGVector(dx: 0.4, dy: -0.4), remainder: &remainder) == .zero)
        #expect(EventInjector.splitWholePoints(CGVector(dx: 0.4, dy: -0.4), remainder: &remainder) == .zero)
        #expect(EventInjector.splitWholePoints(CGVector(dx: 0.4, dy: -0.4), remainder: &remainder) == CGVector(dx: 1, dy: -1))
        #expect(abs(remainder.dx - 0.2) < 1e-9)
        #expect(abs(remainder.dy + 0.2) < 1e-9)
    }
}
