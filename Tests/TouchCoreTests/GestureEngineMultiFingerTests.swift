import Testing
import CoreGraphics
@testable import TouchCore

@Suite struct GestureEngineMultiFingerTests {
    func three(_ dx: Double, _ dy: Double) -> [ActiveTouch] {
        [touch(1, 100 + dx, 300 + dy), touch(2, 150 + dx, 300 + dy), touch(3, 200 + dx, 300 + dy)]
    }
    func four(_ dx: Double, _ dy: Double) -> [ActiveTouch] {
        three(dx, dy) + [touch(4, 250 + dx, 300 + dy)]
    }

    @Test func threeFingerSwipeUp() {
        var e = GestureEngine()
        #expect(e.update(touches: three(0, 0), timestamp: ms(0)).isEmpty)
        #expect(e.update(touches: three(0, -30), timestamp: ms(50)).isEmpty)
        #expect(e.update(touches: three(0, -70), timestamp: ms(100)) == [.swipe(fingers: 3, direction: .up)])
        #expect(e.update(touches: three(0, -200), timestamp: ms(200)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(300)).isEmpty)
        #expect(e.isIdle)
    }

    @Test func fourFingerSwipeLeftAndDownAndRight() {
        var e = GestureEngine()
        _ = e.update(touches: four(0, 0), timestamp: ms(0))
        #expect(e.update(touches: four(-80, 10), timestamp: ms(100)) == [.swipe(fingers: 4, direction: .left)])
        _ = e.update(touches: [], timestamp: ms(200))
        _ = e.update(touches: four(0, 0), timestamp: ms(300))
        #expect(e.update(touches: four(5, 90), timestamp: ms(400)) == [.swipe(fingers: 4, direction: .down)])
        _ = e.update(touches: [], timestamp: ms(500))
        _ = e.update(touches: four(0, 0), timestamp: ms(600))
        #expect(e.update(touches: four(61, 0), timestamp: ms(700)) == [.swipe(fingers: 4, direction: .right)])
    }

    @Test func slowSwipeIsIgnored() {
        var e = GestureEngine()
        _ = e.update(touches: three(0, 0), timestamp: ms(0))
        #expect(e.update(touches: three(0, -70), timestamp: ms(600)).isEmpty)
        #expect(e.update(touches: three(0, -140), timestamp: ms(700)).isEmpty)
    }

    @Test func slowSwipeExpiresViaTick() {
        var e = GestureEngine()
        _ = e.update(touches: three(0, 0), timestamp: ms(0))
        _ = e.tick(ms(600))
        #expect(e.update(touches: three(0, -70), timestamp: ms(620)).isEmpty)
    }

    @Test func liftingOneOfThreeConsumesTheRest() {
        var e = GestureEngine()
        _ = e.update(touches: three(0, 0), timestamp: ms(0))
        #expect(e.update(touches: Array(three(0, 0).prefix(2)), timestamp: ms(50)).isEmpty)
        #expect(e.update(touches: Array(three(0, -100).prefix(2)), timestamp: ms(100)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(150)).isEmpty)
        #expect(e.isIdle)
    }

    @Test func thirdFingerDuringTwoPendingStartsMulti() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 300), touch(2, 150, 300)], timestamp: ms(0))
        #expect(e.update(touches: three(0, 0), timestamp: ms(30)).isEmpty)
        #expect(e.update(touches: three(0, -70), timestamp: ms(100)) == [.swipe(fingers: 3, direction: .up)])
    }

    @Test func fourthFingerDuringThreePendingRestartsAsFour() {
        var e = GestureEngine()
        _ = e.update(touches: three(0, 0), timestamp: ms(0))
        _ = e.update(touches: four(0, 0), timestamp: ms(30))
        #expect(e.update(touches: four(0, -70), timestamp: ms(100)) == [.swipe(fingers: 4, direction: .up)])
    }

    @Test func thirdFingerDuringScrollEndsScroll() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 300), touch(2, 150, 300)], timestamp: ms(0))
        _ = e.update(touches: [touch(1, 100, 315), touch(2, 150, 315)], timestamp: ms(30))
        let out = e.update(touches: three(0, 15), timestamp: ms(60))
        #expect(out[0] == .scroll(phase: .ended, delta: .zero, at: pt(125, 315)))
        #expect(e.update(touches: three(0, -60), timestamp: ms(120)) == [.swipe(fingers: 3, direction: .up)])
    }

    @Test func fiveFingersDoNothing() {
        var e = GestureEngine()
        let five = four(0, 0) + [touch(5, 300, 300)]
        #expect(e.update(touches: five, timestamp: ms(0)).isEmpty)
        #expect(e.update(touches: five.map { touch($0.id, $0.position.x, $0.position.y - 100) }, timestamp: ms(100)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(200)).isEmpty)
        #expect(e.isIdle)
    }
}
