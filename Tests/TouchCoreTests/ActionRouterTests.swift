import Testing
import CoreGraphics
@testable import TouchCore

@Suite struct ActionRouterTests {
    let ctx = RouterContext(frontmostBundleID: "com.apple.Safari")

    @Test func mouseActionsPassThrough() {
        let r = ActionRouter(naturalScrolling: true)
        #expect(r.route(.moveCursor(to: pt(1, 2)), context: ctx) == [.moveCursor(pt(1, 2))])
        #expect(r.route(.click(button: .right, at: pt(1, 2), count: 1), context: ctx) == [.click(.right, pt(1, 2), 1)])
        #expect(r.route(.drag(phase: .changed, to: pt(3, 4)), context: ctx) == [.drag(.changed, pt(3, 4))])
        #expect(r.route(.cancelMomentum, context: ctx) == [.cancelMomentum])
    }

    @Test func gesturesPassThrough() {
        let r = ActionRouter(naturalScrolling: true)
        #expect(r.route(.magnify(phase: .changed, delta: 0.1, at: pt(5, 5)), context: ctx) == [.magnify(.changed, 0.1, pt(5, 5))])
        #expect(r.route(.rotate(phase: .began, degrees: 0, at: pt(5, 5)), context: ctx) == [.rotate(.began, 0, pt(5, 5))])
    }

    @Test func naturalScrollingKeepsSign() {
        let r = ActionRouter(naturalScrolling: true)
        #expect(r.route(.scroll(phase: .changed, delta: CGVector(dx: 3, dy: -7), at: pt(0, 0)), context: ctx)
                == [.scroll(.changed, CGVector(dx: 3, dy: -7), pt(0, 0))])
        #expect(r.route(.scrollMomentum(velocity: CGVector(dx: 0, dy: 300), at: pt(0, 0)), context: ctx)
                == [.scrollMomentum(CGVector(dx: 0, dy: 300), pt(0, 0))])
    }

    @Test func classicScrollingInvertsSign() {
        let r = ActionRouter(naturalScrolling: false)
        #expect(r.route(.scroll(phase: .changed, delta: CGVector(dx: 3, dy: -7), at: pt(0, 0)), context: ctx)
                == [.scroll(.changed, CGVector(dx: -3, dy: 7), pt(0, 0))])
        #expect(r.route(.scrollMomentum(velocity: CGVector(dx: 0, dy: 300), at: pt(0, 0)), context: ctx)
                == [.scrollMomentum(CGVector(dx: 0, dy: -300), pt(0, 0))])
    }

    @Test func swipesMapToSystemShortcuts() {
        let r = ActionRouter(naturalScrolling: true)
        #expect(r.route(.swipe(fingers: 3, direction: .up), context: ctx) == [.key(.missionControl)])
        #expect(r.route(.swipe(fingers: 4, direction: .down), context: ctx) == [.key(.appExpose)])
        #expect(r.route(.swipe(fingers: 3, direction: .left), context: ctx) == [.key(.spaceRight)])
        #expect(r.route(.swipe(fingers: 4, direction: .right), context: ctx) == [.key(.spaceLeft)])
        #expect(KeyCommand.missionControl == KeyCommand(keyCode: 126, control: true))
    }
}
