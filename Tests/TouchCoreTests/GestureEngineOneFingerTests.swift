import Testing
import Foundation
import CoreGraphics
@testable import TouchCore

@Suite struct GestureEngineOneFingerTests {
    @Test func tapProducesLeftClick() {
        var e = GestureEngine()
        #expect(e.update(touches: [touch(1, 100, 100, start: ms(0), now: ms(0))], timestamp: ms(0)) == [.moveCursor(to: pt(100, 100))])
        #expect(e.update(touches: [touch(1, 102, 101, start: ms(0), now: ms(60))], timestamp: ms(60)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(120)) == [.click(button: .left, at: pt(102, 101), count: 1)])
        #expect(e.isIdle)
    }

    @Test func doubleTap() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        _ = e.update(touches: [], timestamp: ms(50))
        _ = e.update(touches: [touch(2, 103, 100)], timestamp: ms(200))
        #expect(e.update(touches: [], timestamp: ms(250)) == [.click(button: .left, at: pt(103, 100), count: 2)])
        // a third tap after the interval is a single click again
        _ = e.update(touches: [touch(3, 103, 100)], timestamp: ms(900))
        #expect(e.update(touches: [], timestamp: ms(950)) == [.click(button: .left, at: pt(103, 100), count: 1)])
    }

    @Test func secondTapFarAwayIsSingleClick() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        _ = e.update(touches: [], timestamp: ms(50))
        _ = e.update(touches: [touch(2, 400, 100)], timestamp: ms(150))
        #expect(e.update(touches: [], timestamp: ms(200)) == [.click(button: .left, at: pt(400, 100), count: 1)])
    }

    @Test func dragAfterMovement() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        #expect(e.update(touches: [touch(1, 120, 100)], timestamp: ms(30)) == [.drag(phase: .began, to: pt(100, 100)), .drag(phase: .changed, to: pt(120, 100))])
        #expect(e.update(touches: [touch(1, 140, 110)], timestamp: ms(60)) == [.drag(phase: .changed, to: pt(140, 110))])
        #expect(e.update(touches: [], timestamp: ms(90)) == [.drag(phase: .ended, to: pt(140, 110))])
        #expect(e.isIdle)
    }

    @Test func slowLiftWithoutMovementIsStillAClick() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        _ = e.update(touches: [touch(1, 101, 100)], timestamp: ms(400))
        #expect(e.update(touches: [], timestamp: ms(450)) == [.click(button: .left, at: pt(101, 100), count: 1)])
    }

    @Test func longPressRightClickViaTick() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        #expect(e.tick(ms(500)).isEmpty)
        #expect(e.tick(ms(620)) == [.click(button: .right, at: pt(100, 100), count: 1)])
        #expect(e.update(touches: [touch(1, 130, 100)], timestamp: ms(700)).isEmpty)   // consumed: no drag
        #expect(e.update(touches: [], timestamp: ms(800)).isEmpty)                      // no left click
        #expect(e.isIdle)
    }

    @Test func longPressRightClickViaFrame() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        #expect(e.update(touches: [touch(1, 100, 100)], timestamp: ms(650)) == [.click(button: .right, at: pt(100, 100), count: 1)])
    }

    @Test func reusedIDAfterLiftStartsFreshTap() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(3, 100, 100)], timestamp: ms(0))
        #expect(e.update(touches: [], timestamp: ms(50)) == [.click(button: .left, at: pt(100, 100), count: 1)])
        #expect(e.update(touches: [touch(3, 900, 900, start: ms(60), now: ms(60))], timestamp: ms(60)) == [.moveCursor(to: pt(900, 900))])
        #expect(e.update(touches: [], timestamp: ms(100)) == [.click(button: .left, at: pt(900, 900), count: 1)])
    }

    @Test func resetCancelsDrag() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        _ = e.update(touches: [touch(1, 150, 100)], timestamp: ms(30))
        #expect(e.reset() == [.drag(phase: .cancelled, to: pt(150, 100))])
        #expect(e.isIdle)
    }

    @Test func contactReplacedDuringTapClicksAndRestarts() {
        var e = GestureEngine()
        #expect(e.update(touches: [touch(1, 100, 100)], timestamp: ms(0)) == [.moveCursor(to: pt(100, 100))])
        #expect(e.update(touches: [touch(2, 300, 100, start: ms(50), now: ms(50))], timestamp: ms(50)) == [.click(button: .left, at: pt(100, 100), count: 1), .moveCursor(to: pt(300, 100))])
        #expect(e.update(touches: [], timestamp: ms(100)) == [.click(button: .left, at: pt(300, 100), count: 1)])
    }

    @Test func contactReplacedDuringDragEndsDragAndRestarts() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        _ = e.update(touches: [touch(1, 130, 100)], timestamp: ms(30))
        #expect(e.update(touches: [touch(2, 300, 100, start: ms(60), now: ms(60))], timestamp: ms(60)) == [.drag(phase: .ended, to: pt(130, 100)), .moveCursor(to: pt(300, 100))])
        #expect(!e.isIdle)
    }

    @Test func configIsCodableWithDefaults() throws {
        let decoded = try JSONDecoder().decode(GestureConfig.self, from: Data("{\"tapMaxMovement\": 12}".utf8))
        #expect(decoded.tapMaxMovement == 12)
        #expect(decoded.longPressDuration == 0.6)
        let roundTrip = try JSONDecoder().decode(GestureConfig.self, from: JSONEncoder().encode(GestureConfig()))
        #expect(roundTrip == GestureConfig())
    }
}
