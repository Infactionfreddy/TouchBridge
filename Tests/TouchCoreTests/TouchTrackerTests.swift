import Testing
@testable import TouchCore

@Suite struct TouchTrackerTests {
    @Test func beganMovedEnded() {
        var tracker = TouchTracker(stuckTimeout: ms(500))
        #expect(tracker.process(frame(ms(0), [(1, 10, 10, true)])) == [TouchEvent(id: 1, phase: .began, position: pt(10, 10), timestamp: ms(0))])
        #expect(tracker.process(frame(ms(10), [(1, 12, 10, true)])) == [TouchEvent(id: 1, phase: .moved, position: pt(12, 10), timestamp: ms(10))])
        #expect(tracker.touches.count == 1)
        #expect(tracker.touches[0].startPosition == pt(10, 10))
        #expect(tracker.touches[0].position == pt(12, 10))
        #expect(tracker.process(frame(ms(20), [(1, 12, 10, false)])) == [TouchEvent(id: 1, phase: .ended, position: pt(12, 10), timestamp: ms(20))])
        #expect(tracker.touches.isEmpty)
    }

    @Test func absentContactEnds() {
        var tracker = TouchTracker(stuckTimeout: ms(500))
        _ = tracker.process(frame(ms(0), [(1, 10, 10, true), (2, 50, 50, true)]))
        let events = tracker.process(frame(ms(10), [(2, 51, 50, true)]))
        #expect(events == [
            TouchEvent(id: 2, phase: .moved, position: pt(51, 50), timestamp: ms(10)),
            TouchEvent(id: 1, phase: .ended, position: pt(10, 10), timestamp: ms(10)),
        ])
        #expect(tracker.touches.map(\.id) == [2])
    }

    @Test func emptyFrameEndsEverything() {
        var tracker = TouchTracker(stuckTimeout: ms(500))
        _ = tracker.process(frame(ms(0), [(1, 10, 10, true), (2, 50, 50, true)]))
        let events = tracker.process(frame(ms(10), []))
        #expect(events.map(\.phase) == [.ended, .ended])
        #expect(tracker.touches.isEmpty)
    }

    @Test func reusedIDIsNewTouch() {
        var tracker = TouchTracker(stuckTimeout: ms(500))
        _ = tracker.process(frame(ms(0), [(3, 10, 10, true)]))
        _ = tracker.process(frame(ms(10), [(3, 10, 10, false)]))
        let events = tracker.process(frame(ms(20), [(3, 500, 500, true)]))
        #expect(events == [TouchEvent(id: 3, phase: .began, position: pt(500, 500), timestamp: ms(20))])
        #expect(tracker.touches[0].startPosition == pt(500, 500))
        #expect(tracker.touches[0].startTime == ms(20))
    }

    @Test func stuckTouchEndsViaTick() {
        var tracker = TouchTracker(stuckTimeout: ms(500))
        _ = tracker.process(frame(ms(0), [(1, 10, 10, true)]))
        #expect(tracker.tick(ms(400)).isEmpty)
        #expect(tracker.tick(ms(600)) == [TouchEvent(id: 1, phase: .ended, position: pt(10, 10), timestamp: ms(600))])
        #expect(tracker.touches.isEmpty)
    }

    @Test func olderTimestampDoesNotExpireTouch() {
        var tracker = TouchTracker(stuckTimeout: ms(500))
        _ = tracker.process(frame(ms(1000), [(1, 10, 10, true)]))
        #expect(tracker.tick(ms(200)).isEmpty)
        #expect(tracker.touches.count == 1)
    }

    @Test func olderFrameDoesNotRegressLastUpdate() {
        var tracker = TouchTracker(stuckTimeout: ms(500))
        _ = tracker.process(frame(ms(1000), [(1, 10, 10, true)]))
        _ = tracker.process(frame(ms(200), [(1, 11, 10, true)]))
        #expect(tracker.tick(ms(800)).isEmpty)
        #expect(tracker.touches.count == 1)
        #expect(tracker.touches[0].lastUpdate == ms(1000))
    }

    @Test func touchesKeepArrivalOrder() {
        var tracker = TouchTracker(stuckTimeout: ms(500))
        _ = tracker.process(frame(ms(0), [(7, 10, 10, true)]))
        _ = tracker.process(frame(ms(5), [(2, 20, 20, true), (7, 10, 10, true)]))
        #expect(tracker.touches.map(\.id) == [7, 2])
    }
}
