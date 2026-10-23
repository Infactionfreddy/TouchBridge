import Testing
import Foundation
@testable import TouchCore

@Suite struct GestureActionTests {
    func roundTrip(_ action: GestureAction) throws -> GestureAction {
        try JSONDecoder().decode(GestureAction.self, from: JSONEncoder().encode(action))
    }

    @Test func actionsRoundTripThroughJSON() throws {
        let actions: [GestureAction] = [
            .none, .passThrough,
            .mouseClick(button: .middle, count: 1), .mouseClick(button: .forward, count: 2),
            .keystroke(key: KeyCommand(keyCode: 33, command: true)),
            .systemAction(action: .showDesktop),
            .openFile(path: "/Applications/Safari.app"),
        ]
        for action in actions {
            #expect(try roundTrip(action) == action)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(GestureAction.mouseClick(button: .back, count: 1)), as: UTF8.self)
        #expect(json == "{\"mouseClick\":{\"button\":\"back\",\"count\":1}}")
    }

    @Test func unknownActionDecodesAsPassThrough() throws {
        let decoded = try JSONDecoder().decode(GestureAction.self, from: Data("{\"teleport\":{\"to\":\"moon\"}}".utf8))
        #expect(decoded == .passThrough)
        let binding = try JSONDecoder().decode(GestureBinding.self, from: Data("{\"enabled\":false,\"action\":{\"warp\":{}}}".utf8))
        #expect(binding == GestureBinding(enabled: false, action: .passThrough))
    }

    @Test func systemActionsHaveTheDefaultShortcuts() {
        #expect(SystemAction.missionControl.keyCommand == KeyCommand(keyCode: 126, control: true))
        #expect(SystemAction.appExpose.keyCommand == KeyCommand(keyCode: 125, control: true))
        #expect(SystemAction.spaceLeft.keyCommand == KeyCommand(keyCode: 123, control: true))
        #expect(SystemAction.spaceRight.keyCommand == KeyCommand(keyCode: 124, control: true))
        #expect(SystemAction.showDesktop.keyCommand == KeyCommand(keyCode: 103))
        #expect(SystemAction.allCases.map(\.displayName) == ["Mission Control", "App Exposé", "Space left", "Space right", "Show desktop"])
    }

    @Test func builtInBindingsReproduceTheDefaultSet() {
        for kind in [GestureKind.tap, .doubleTap, .press, .drag, .twoFingerTap, .pinch, .spread, .rotateLeft, .rotateRight] {
            #expect(GestureBinding.builtIn(for: kind) == GestureBinding(action: .passThrough), "\(kind)")
        }
        #expect(GestureBinding.builtIn(for: .twoFingerDrag) == GestureBinding(action: .passThrough, naturalScrolling: true, momentum: true))
        for fingers in [GestureKind.threeFingerSwipeUp, .fourFingerSwipeUp] { #expect(GestureBinding.builtIn(for: fingers).action == .systemAction(action: .missionControl)) }
        for fingers in [GestureKind.threeFingerSwipeDown, .fourFingerSwipeDown] { #expect(GestureBinding.builtIn(for: fingers).action == .systemAction(action: .appExpose)) }
        for fingers in [GestureKind.threeFingerSwipeLeft, .fourFingerSwipeLeft] { #expect(GestureBinding.builtIn(for: fingers).action == .systemAction(action: .spaceRight)) }
        for fingers in [GestureKind.threeFingerSwipeRight, .fourFingerSwipeRight] { #expect(GestureBinding.builtIn(for: fingers).action == .systemAction(action: .spaceLeft)) }
        for kind in GestureKind.allCases where !kind.isRecognized {
            #expect(GestureBinding.builtIn(for: kind) == GestureBinding(action: .none), "\(kind)")
        }
    }

    @Test func bindingOmitsNilOptionsInJSON() throws {
        let json = String(decoding: try JSONEncoder().encode(GestureBinding(action: .none)), as: UTF8.self)
        #expect(json.contains("\"enabled\":true"))
        #expect(!json.contains("naturalScrolling"))
        #expect(!json.contains("momentum"))
    }
}
