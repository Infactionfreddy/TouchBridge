import Testing
import CoreGraphics
@testable import TouchCore

@Suite struct ActionRouterTests {
    let ctx = RouterContext(frontmostBundleID: "com.apple.Safari")

    func profile(_ bindings: [GestureKind: GestureBinding]) -> EffectiveProfile {
        var e = EffectiveProfile.builtIn
        for (kind, binding) in bindings { e.bindings[kind] = binding }
        return e
    }

    @Test func passThroughReproducesTheDefaultSet() {
        var r = ActionRouter(profile: .builtIn)
        #expect(r.route(.moveCursor(to: pt(1, 2)), context: ctx) == [.moveCursor(pt(1, 2))])
        #expect(r.route(.click(button: .left, at: pt(1, 2), count: 1, source: .tap), context: ctx) == [.click(.left, pt(1, 2), 1)])
        #expect(r.route(.click(button: .left, at: pt(1, 2), count: 2, source: .tap), context: ctx) == [.click(.left, pt(1, 2), 2)])
        #expect(r.route(.click(button: .right, at: pt(1, 2), count: 1, source: .longPress), context: ctx) == [.click(.right, pt(1, 2), 1)])
        #expect(r.route(.click(button: .right, at: pt(1, 2), count: 1, source: .twoFingerTap), context: ctx) == [.click(.right, pt(1, 2), 1)])
        #expect(r.route(.drag(phase: .began, to: pt(3, 4)), context: ctx) == [.drag(.began, pt(3, 4))])
        #expect(r.route(.drag(phase: .changed, to: pt(5, 4)), context: ctx) == [.drag(.changed, pt(5, 4))])
        #expect(r.route(.cancelMomentum, context: ctx) == [.cancelMomentum])
        #expect(r.route(.magnify(phase: .began, delta: 0, at: pt(5, 5)), context: ctx) == [.magnify(.began, 0, pt(5, 5))])
        #expect(r.route(.magnify(phase: .changed, delta: 0.1, at: pt(5, 5)), context: ctx) == [.magnify(.changed, 0.1, pt(5, 5))])
        #expect(r.route(.rotate(phase: .began, degrees: 0, at: pt(5, 5)), context: ctx) == [.rotate(.began, 0, pt(5, 5))])
        #expect(r.route(.rotate(phase: .changed, degrees: -3, at: pt(5, 5)), context: ctx) == [.rotate(.changed, -3, pt(5, 5))])
        #expect(r.route(.swipe(fingers: 3, direction: .up), context: ctx) == [.key(.missionControl)])
        #expect(r.route(.swipe(fingers: 4, direction: .down), context: ctx) == [.key(.appExpose)])
        #expect(r.route(.swipe(fingers: 3, direction: .left), context: ctx) == [.key(.spaceRight)])
        #expect(r.route(.swipe(fingers: 4, direction: .right), context: ctx) == [.key(.spaceLeft)])
        #expect(r.route(.swipe(fingers: 5, direction: .up), context: ctx) == [])   // not recognized: none
    }

    @Test func naturalScrollingKeepsSignAndClassicInverts() {
        var natural = ActionRouter(profile: .builtIn)
        _ = natural.route(.scroll(phase: .began, delta: .zero, at: pt(0, 0)), context: ctx)
        #expect(natural.route(.scroll(phase: .changed, delta: CGVector(dx: 3, dy: -7), at: pt(0, 0)), context: ctx)
                == [.scroll(.changed, CGVector(dx: 3, dy: -7), pt(0, 0))])
        #expect(natural.route(.scrollMomentum(velocity: CGVector(dx: 0, dy: 300), at: pt(0, 0)), context: ctx)
                == [.scrollMomentum(CGVector(dx: 0, dy: 300), pt(0, 0))])
        var classic = ActionRouter(profile: profile([.twoFingerDrag: GestureBinding(action: .passThrough, naturalScrolling: false, momentum: true)]))
        #expect(classic.route(.scroll(phase: .began, delta: .zero, at: pt(0, 0)), context: ctx) == [.scroll(.began, .zero, pt(0, 0))])
        #expect(classic.route(.scroll(phase: .changed, delta: CGVector(dx: 3, dy: -7), at: pt(0, 0)), context: ctx)
                == [.scroll(.changed, CGVector(dx: -3, dy: 7), pt(0, 0))])
        #expect(classic.route(.scroll(phase: .ended, delta: .zero, at: pt(0, 0)), context: ctx) == [.scroll(.ended, .zero, pt(0, 0))])
        #expect(classic.route(.scrollMomentum(velocity: CGVector(dx: 0, dy: 300), at: pt(0, 0)), context: ctx)
                == [.scrollMomentum(CGVector(dx: 0, dy: -300), pt(0, 0))])
    }

    @Test func momentumOffKeepsScrollButDropsMomentum() {
        var r = ActionRouter(profile: profile([.twoFingerDrag: GestureBinding(action: .passThrough, naturalScrolling: true, momentum: false)]))
        _ = r.route(.scroll(phase: .began, delta: .zero, at: pt(0, 0)), context: ctx)
        #expect(r.route(.scroll(phase: .changed, delta: CGVector(dx: 0, dy: 5), at: pt(0, 0)), context: ctx).count == 1)
        #expect(r.route(.scroll(phase: .ended, delta: .zero, at: pt(0, 0)), context: ctx).count == 1)
        #expect(r.route(.scrollMomentum(velocity: CGVector(dx: 0, dy: 300), at: pt(0, 0)), context: ctx) == [])
        #expect(r.route(.cancelMomentum, context: ctx) == [.cancelMomentum])
    }

    @Test func disabledOrNoneDropsTheWholeContinuousGesture() {
        var r = ActionRouter(profile: profile([.drag: GestureBinding(enabled: false), .twoFingerDrag: GestureBinding(action: .none)]))
        #expect(r.route(.drag(phase: .began, to: pt(1, 1)), context: ctx) == [])
        #expect(r.route(.drag(phase: .changed, to: pt(2, 1)), context: ctx) == [])
        #expect(r.route(.drag(phase: .ended, to: pt(2, 1)), context: ctx) == [])
        #expect(r.route(.scroll(phase: .began, delta: .zero, at: pt(0, 0)), context: ctx) == [])
        #expect(r.route(.scroll(phase: .changed, delta: CGVector(dx: 0, dy: 5), at: pt(0, 0)), context: ctx) == [])
        #expect(r.route(.scroll(phase: .ended, delta: .zero, at: pt(0, 0)), context: ctx) == [])
        #expect(r.route(.scrollMomentum(velocity: CGVector(dx: 0, dy: 300), at: pt(0, 0)), context: ctx) == [])
        // the cursor still follows the finger
        #expect(r.route(.moveCursor(to: pt(9, 9)), context: ctx) == [.moveCursor(pt(9, 9))])
    }

    @Test func discreteActionOnAContinuousGestureFiresOnceAtBegan() {
        let key = KeyCommand(keyCode: 49)   // space
        var r = ActionRouter(profile: profile([.drag: GestureBinding(action: .keystroke(key: key))]))
        #expect(r.route(.drag(phase: .began, to: pt(1, 1)), context: ctx) == [.key(key)])
        #expect(r.route(.drag(phase: .changed, to: pt(2, 1)), context: ctx) == [])
        #expect(r.route(.drag(phase: .ended, to: pt(2, 1)), context: ctx) == [])
        // the next drag decides again
        #expect(r.route(.drag(phase: .began, to: pt(1, 1)), context: ctx) == [.key(key)])
    }

    @Test func clicksUseTheirOwnKindsBindings() {
        var r = ActionRouter(profile: profile([
            .twoFingerTap: GestureBinding(action: .mouseClick(button: .middle, count: 1)),
            .press: GestureBinding(action: .none),
            .doubleTap: GestureBinding(action: .systemAction(action: .showDesktop)),
        ]))
        #expect(r.route(.click(button: .right, at: pt(1, 2), count: 1, source: .twoFingerTap), context: ctx) == [.click(.middle, pt(1, 2), 1)])
        #expect(r.route(.click(button: .right, at: pt(1, 2), count: 1, source: .longPress), context: ctx) == [])
        #expect(r.route(.click(button: .left, at: pt(1, 2), count: 1, source: .tap), context: ctx) == [.click(.left, pt(1, 2), 1)])
        #expect(r.route(.click(button: .left, at: pt(1, 2), count: 2, source: .tap), context: ctx) == [.key(.showDesktop)])
    }

    @Test func doubleTapUsesItsOwnBinding() {
        // Tap bound to a keystroke, double tap left as pass-through: first tap → key, second tap → click count 2.
        let key = KeyCommand(keyCode: 36)   // return
        var r = ActionRouter(profile: profile([.tap: GestureBinding(action: .keystroke(key: key))]))
        #expect(r.route(.click(button: .left, at: pt(1, 2), count: 1, source: .tap), context: ctx) == [.key(key)])
        #expect(r.route(.click(button: .left, at: pt(1, 2), count: 2, source: .tap), context: ctx) == [.click(.left, pt(1, 2), 2)])
    }

    @Test func swipesTakeKeystrokesFilesAndClicksAtTheCursor() {
        var r = ActionRouter(profile: profile([
            .threeFingerSwipeLeft: GestureBinding(action: .keystroke(key: KeyCommand(keyCode: 33, command: true))),
            .fourFingerSwipeUp: GestureBinding(action: .openFile(path: "/Applications/Safari.app")),
            .threeFingerSwipeDown: GestureBinding(action: .mouseClick(button: .back, count: 1)),
            .fourFingerSwipeDown: GestureBinding(action: .passThrough),   // no native swipe: same as none
        ]))
        _ = r.route(.moveCursor(to: pt(400, 300)), context: ctx)
        #expect(r.route(.swipe(fingers: 3, direction: .left), context: ctx) == [.key(KeyCommand(keyCode: 33, command: true))])
        #expect(r.route(.swipe(fingers: 4, direction: .up), context: ctx) == [.openFile("/Applications/Safari.app")])
        #expect(r.route(.swipe(fingers: 3, direction: .down), context: ctx) == [.click(.back, pt(400, 300), 1)])
        #expect(r.route(.swipe(fingers: 4, direction: .down), context: ctx) == [])
    }

    @Test func magnifyAndRotateHonourPerDirectionPassThrough() {
        var r = ActionRouter(profile: profile([.pinch: GestureBinding(action: .none), .rotateLeft: GestureBinding(enabled: false), .rotateRight: GestureBinding(action: .none)]))
        #expect(r.route(.magnify(phase: .began, delta: 0, at: pt(5, 5)), context: ctx) == [.magnify(.began, 0, pt(5, 5))])
        #expect(r.route(.magnify(phase: .changed, delta: 0.1, at: pt(5, 5)), context: ctx) == [.magnify(.changed, 0.1, pt(5, 5))])    // spread passes
        #expect(r.route(.magnify(phase: .changed, delta: -0.1, at: pt(5, 5)), context: ctx) == [])                                   // pinch dropped
        #expect(r.route(.magnify(phase: .ended, delta: 0, at: pt(5, 5)), context: ctx) == [.magnify(.ended, 0, pt(5, 5))])
        #expect(r.route(.rotate(phase: .began, degrees: 0, at: pt(5, 5)), context: ctx) == [])
        #expect(r.route(.rotate(phase: .changed, degrees: 4, at: pt(5, 5)), context: ctx) == [])
        #expect(r.route(.rotate(phase: .ended, degrees: 0, at: pt(5, 5)), context: ctx) == [])
    }

    @Test func continuingRouterKeepsSuppressedGestures() {
        var old = ActionRouter(profile: profile([.twoFingerDrag: GestureBinding(action: .none)]))
        #expect(old.route(.scroll(phase: .began, delta: .zero, at: pt(0, 0)), context: ctx) == [])
        // Frontmost app changes mid-scroll to one where scrolling passes through: the running scroll stays dropped.
        var new = ActionRouter(profile: .builtIn, continuing: old)
        #expect(new.route(.scroll(phase: .changed, delta: CGVector(dx: 0, dy: 5), at: pt(0, 0)), context: ctx) == [])
        #expect(new.route(.scroll(phase: .ended, delta: .zero, at: pt(0, 0)), context: ctx) == [])
        #expect(new.route(.scrollMomentum(velocity: CGVector(dx: 0, dy: 300), at: pt(0, 0)), context: ctx) == [])
        // the next scroll uses the new profile
        #expect(new.route(.scroll(phase: .began, delta: .zero, at: pt(0, 0)), context: ctx) == [.scroll(.began, .zero, pt(0, 0))])
    }
}
