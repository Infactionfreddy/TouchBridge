import Testing
import CoreGraphics
@testable import TouchCore

@Suite struct GestureEngineTwoFingerTests {
    func pair(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> [ActiveTouch] {
        [touch(1, ax, ay), touch(2, bx, by)]
    }

    @Test func twoFingerTapIsRightClick() {
        var e = GestureEngine()
        #expect(e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(100)) == [.click(button: .right, at: pt(120, 100), count: 1)])
        #expect(e.isIdle)
    }

    @Test func staggeredTwoFingerTapIsRightClick() {
        var e = GestureEngine()
        #expect(e.update(touches: [touch(1, 100, 100)], timestamp: ms(0)) == [.moveCursor(to: pt(100, 100))])
        #expect(e.update(touches: pair(100, 100, 140, 100), timestamp: ms(40)).isEmpty)
        #expect(e.update(touches: [touch(2, 140, 100)], timestamp: ms(120)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(150)) == [.click(button: .right, at: pt(120, 100), count: 1)])
    }

    @Test func twoFingerHoldThenLiftIsNothing() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(300))
        #expect(e.update(touches: [], timestamp: ms(500)).isEmpty)
    }

    @Test func twoReleasingExpiresViaTick() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: [touch(2, 140, 100)], timestamp: ms(100))
        _ = e.tick(ms(400))
        #expect(e.update(touches: [], timestamp: ms(450)).isEmpty)
    }

    @Test func smallMovementClassifiesScrollWithoutDeadZone() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        #expect(e.update(touches: pair(100, 103, 140, 103), timestamp: ms(8)).isEmpty)          // 3 pt: still pending
        #expect(e.update(touches: pair(100, 105, 140, 105), timestamp: ms(16)) == [          // 5 pt: scroll, small first delta
            .scroll(phase: .began, delta: .zero, at: pt(120, 105)),
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 5), at: pt(120, 105)),
        ])
    }

    @Test func scrollClassificationAndMomentum() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        #expect(e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30)) == [
            .scroll(phase: .began, delta: .zero, at: pt(120, 115)),
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 15), at: pt(120, 115)),
        ])
        #expect(e.update(touches: pair(100, 125, 140, 125), timestamp: ms(60)) == [
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 10), at: pt(120, 125)),
        ])
        let lift = e.update(touches: [], timestamp: ms(90))
        #expect(lift.count == 2)
        #expect(lift[0] == .scroll(phase: .ended, delta: .zero, at: pt(120, 125)))
        guard case .scrollMomentum(let v, let at) = lift[1] else { Issue.record("expected momentum"); return }
        #expect(abs(v.dy - 333.33) < 0.5)
        #expect(v.dx == 0)
        #expect(at == pt(120, 125))
        #expect(e.isIdle)
    }

    @Test func slowScrollHasNoMomentum() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 112, 140, 112), timestamp: ms(500))
        _ = e.update(touches: pair(100, 113, 140, 113), timestamp: ms(1000))   // 2 pt/s
        #expect(e.update(touches: [], timestamp: ms(1100)) == [.scroll(phase: .ended, delta: .zero, at: pt(120, 113))])
    }

    @Test func duplicateTimestampGivesFiniteVelocity() throws {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        _ = e.update(touches: pair(100, 125, 140, 125), timestamp: ms(60))
        #expect(e.update(touches: pair(100, 130, 140, 130), timestamp: ms(60)) == [
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 5), at: pt(120, 130)),
        ])
        let lift = e.update(touches: [], timestamp: ms(50))   // earlier than before: still no crash
        try #require(lift.count == 2)
        guard case .scrollMomentum(let v, _) = lift[1] else { Issue.record("expected momentum"); return }
        // Window of 50 ms before the last sample (t = 60): samples at 30, 60, 60 → 15 pt in 30 ms.
        #expect(v.dy.isFinite)
        #expect(abs(v.dy - 500) < 0.5)
    }

    @Test func liftVelocityUsesRecentWindowNotLastFrame() throws {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))     // classified
        _ = e.update(touches: pair(100, 130, 140, 130), timestamp: ms(60))
        _ = e.update(touches: pair(100, 145, 140, 145), timestamp: ms(90))     // 500 pt/s
        _ = e.update(touches: pair(100, 146, 140, 146), timestamp: ms(98))     // fingers slow down before lifting
        let lift = e.update(touches: [], timestamp: ms(106))
        try #require(lift.count == 2)
        guard case .scrollMomentum(let v, _) = lift[1] else { Issue.record("expected momentum"); return }
        // Last frame alone would give 1 pt / 8 ms = 125 pt/s; the 50 ms window (60…98 ms) gives 16 pt / 38 ms.
        #expect(abs(v.dy - 421.05) < 0.5)
        #expect(v.dx == 0)
    }

    @Test func newTouchCancelsMomentum() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        _ = e.update(touches: [], timestamp: ms(60))
        #expect(e.update(touches: [touch(5, 300, 300)], timestamp: ms(200)) == [.cancelMomentum, .moveCursor(to: pt(300, 300))])
        _ = e.update(touches: [], timestamp: ms(250))
        #expect(e.update(touches: [touch(6, 300, 300)], timestamp: ms(400)) == [.moveCursor(to: pt(300, 300))])
    }

    @Test func pinchClassification() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))          // distance 40
        let first = e.update(touches: pair(90, 100, 160, 100), timestamp: ms(30))  // distance 70
        #expect(first.count == 2)
        #expect(first[0] == .magnify(phase: .began, delta: 0, at: pt(125, 100)))
        guard case .magnify(.changed, let d1, let at1) = first[1] else { Issue.record("expected magnify"); return }
        #expect(abs(d1 - 0.75) < 1e-9)
        #expect(at1 == pt(125, 100))
        let second = e.update(touches: pair(80, 100, 170, 100), timestamp: ms(60)) // distance 90
        guard case .magnify(.changed, let d2, _) = second[0] else { Issue.record("expected magnify"); return }
        #expect(abs(d2 - (90.0 / 70.0 - 1)) < 1e-9)
        #expect(e.update(touches: [], timestamp: ms(90)) == [.magnify(phase: .ended, delta: 0, at: pt(125, 100))])
    }

    @Test func pinchInIsNegative() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 200, 100), timestamp: ms(0))
        let out = e.update(touches: pair(120, 100, 180, 100), timestamp: ms(30))
        guard case .magnify(.changed, let d, _) = out[1] else { Issue.record("expected magnify"); return }
        #expect(d < 0)
    }

    @Test func rotateClassificationCounterClockwisePositive() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 200, 100), timestamp: ms(0))
        let first = e.update(touches: pair(100, 100, 200, 80), timestamp: ms(30))   // finger 2 moves up on screen
        #expect(first[0] == .rotate(phase: .began, degrees: 0, at: pt(150, 90)))
        guard case .rotate(.changed, let deg1, _) = first[1] else { Issue.record("expected rotate"); return }
        #expect(abs(deg1 - 11.31) < 0.05)
        let second = e.update(touches: pair(100, 100, 200, 60), timestamp: ms(60))
        guard case .rotate(.changed, let deg2, _) = second[0] else { Issue.record("expected rotate"); return }
        #expect(abs(deg2 - 10.49) < 0.05)
        #expect(e.update(touches: [], timestamp: ms(90)) == [.rotate(phase: .ended, degrees: 0, at: pt(150, 80))])
    }

    @Test func pinchWinsWhenBothThresholdsExceeded() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        let out = e.update(touches: pair(80, 120, 160, 120), timestamp: ms(30))   // spread 40 and moved 20
        guard case .magnify = out[0] else { Issue.record("expected magnify first"); return }
    }

    @Test func secondFingerDuringDragEndsDrag() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        _ = e.update(touches: [touch(1, 130, 100)], timestamp: ms(30))
        #expect(e.update(touches: pair(130, 100, 170, 100), timestamp: ms(60)) == [.drag(phase: .ended, to: pt(130, 100))])
        _ = e.update(touches: pair(130, 120, 170, 120), timestamp: ms(90))
        #expect(e.update(touches: pair(130, 130, 170, 130), timestamp: ms(120)) == [
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 10), at: pt(150, 130)),
        ])
    }

    @Test func liftingOneFingerDuringScrollConsumesTheOther() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        let out = e.update(touches: [touch(2, 140, 115)], timestamp: ms(60))
        #expect(out[0] == .scroll(phase: .ended, delta: .zero, at: pt(120, 115)))
        #expect(e.update(touches: [touch(2, 140, 300)], timestamp: ms(90)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(120)).isEmpty)
        #expect(e.isIdle)
    }

    @Test func resetEndsScrollWithoutMomentum() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        #expect(e.reset() == [.scroll(phase: .ended, delta: .zero, at: pt(120, 115))])
    }

    @Test func staggeredTwoFingerTapWithIntermediateFrames() {
        var e = GestureEngine()
        #expect(e.update(touches: [touch(1, 100, 100)], timestamp: ms(0)) == [.moveCursor(to: pt(100, 100))])
        #expect(e.update(touches: pair(100, 100, 140, 100), timestamp: ms(40)).isEmpty)
        #expect(e.update(touches: [touch(2, 140, 100)], timestamp: ms(120)).isEmpty)
        #expect(e.update(touches: [touch(2, 140, 100)], timestamp: ms(128)).isEmpty)
        #expect(e.update(touches: [touch(2, 140, 100)], timestamp: ms(136)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(150)) == [.click(button: .right, at: pt(120, 100), count: 1)])
        #expect(e.isIdle)
    }

    @Test func resetClearsMomentumFlag() throws {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        let lift = e.update(touches: [], timestamp: ms(60))
        try #require(lift.count == 2)
        #expect(e.reset().isEmpty)
        #expect(e.update(touches: [touch(5, 300, 300)], timestamp: ms(200)) == [.moveCursor(to: pt(300, 300))])
    }

    @Test func pinchThenScrollAfterReplacingOneFinger() throws {
        var e = GestureEngine()
        #expect(e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0)).isEmpty)
        let pinch = e.update(touches: pair(90, 100, 160, 100), timestamp: ms(30))
        try #require(pinch.count == 2)
        #expect(pinch[0] == .magnify(phase: .began, delta: 0, at: pt(125, 100)))
        #expect(e.update(touches: [touch(2, 160, 100)], timestamp: ms(60)) == [.magnify(phase: .ended, delta: 0, at: pt(125, 100))])
        #expect(e.update(touches: [touch(2, 160, 100)], timestamp: ms(80)).isEmpty)
        #expect(e.update(touches: [touch(2, 160, 100), touch(3, 200, 100)], timestamp: ms(100)).isEmpty)
        #expect(e.update(touches: [touch(2, 160, 115), touch(3, 200, 115)], timestamp: ms(130)) == [
            .scroll(phase: .began, delta: .zero, at: pt(180, 115)),
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 15), at: pt(180, 115)),
        ])
    }

    @Test func newFingerAfterScrollLiftCancelsMomentum() throws {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        let out = e.update(touches: [touch(2, 140, 115)], timestamp: ms(60))
        try #require(out.count == 2)
        #expect(out[0] == .scroll(phase: .ended, delta: .zero, at: pt(120, 115)))
        #expect(e.update(touches: [touch(2, 140, 115), touch(7, 180, 115)], timestamp: ms(90)) == [.cancelMomentum])
    }
}
