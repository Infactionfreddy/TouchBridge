import Foundation
import Testing
@testable import TouchCore

@Suite struct GestureKindTests {
    @Test func catalogueIsCompleteAndStable() {
        #expect(GestureKind.allCases.count == 45)
        // Raw values are JSON keys; this list pins them.
        let expected = [
            "tap", "doubleTap", "press", "pressAndTap", "drag",
            "twoFingerTap", "twoFingerDoubleTap", "twoFingerDrag",
            "twoFingerSwipeUp", "twoFingerSwipeDown", "twoFingerSwipeLeft", "twoFingerSwipeRight",
            "pinch", "spread", "rotateLeft", "rotateRight",
            "threeFingerTap", "threeFingerDoubleTap", "threeFingerDrag",
            "threeFingerSwipeUp", "threeFingerSwipeDown", "threeFingerSwipeLeft", "threeFingerSwipeRight",
            "fourFingerTap", "fourFingerDoubleTap", "fourFingerDrag",
            "fourFingerSwipeUp", "fourFingerSwipeDown", "fourFingerSwipeLeft", "fourFingerSwipeRight",
            "fourFingerSqueeze", "fourFingerSplay",
            "fiveFingerTap", "fiveFingerDoubleTap", "fiveFingerDrag",
            "fiveFingerSwipeUp", "fiveFingerSwipeDown", "fiveFingerSwipeLeft", "fiveFingerSwipeRight",
            "fiveFingerSqueeze", "fiveFingerSplay",
            "oneFingerEdgeSwipeFromLeft", "oneFingerEdgeSwipeFromRight",
            "twoFingerEdgeSwipeFromLeft", "twoFingerEdgeSwipeFromRight",
        ]
        #expect(GestureKind.allCases.map(\.rawValue) == expected)
    }

    @Test func recognizedKindsAreTheEighteenFromPartA() {
        let recognized = GestureKind.allCases.filter(\.isRecognized)
        #expect(recognized.count == 18)
        #expect(Set(recognized) == [
            .tap, .doubleTap, .press, .drag, .twoFingerTap, .twoFingerDrag, .pinch, .spread, .rotateLeft, .rotateRight,
            .threeFingerSwipeUp, .threeFingerSwipeDown, .threeFingerSwipeLeft, .threeFingerSwipeRight,
            .fourFingerSwipeUp, .fourFingerSwipeDown, .fourFingerSwipeLeft, .fourFingerSwipeRight,
        ])
        #expect(!GestureKind.pressAndTap.isRecognized)
    }

    @Test func groupsAndNames() {
        #expect(GestureKind.tap.group == .oneFinger)
        #expect(GestureKind.pinch.group == .twoFingers)
        #expect(GestureKind.twoFingerSwipeLeft.group == .twoFingers)
        #expect(GestureKind.threeFingerDrag.group == .threeFingers)
        #expect(GestureKind.fourFingerSplay.group == .fourFingers)
        #expect(GestureKind.fiveFingerTap.group == .fiveFingers)
        #expect(GestureKind.twoFingerEdgeSwipeFromLeft.group == .edges)
        #expect(GestureKind.tap.displayName == "Tap")
        #expect(GestureKind.twoFingerSwipeUp.displayName == "Two finger swipe up")
        #expect(GestureKind.oneFingerEdgeSwipeFromRight.displayName == "One finger edge swipe from right")
        #expect(GestureKind.pressAndTap.displayName == "Press and tap")
        #expect(FingerGroup.allCases.map(\.rawValue) == ["One finger", "Two fingers", "Three fingers", "Four fingers", "Five fingers", "Edges"])
    }

    @Test func continuousKindsAndSwipeLookup() {
        #expect(GestureKind.drag.isContinuous)
        #expect(GestureKind.twoFingerDrag.isContinuous)
        #expect(GestureKind.pinch.isContinuous && GestureKind.rotateRight.isContinuous)
        #expect(!GestureKind.tap.isContinuous && !GestureKind.threeFingerSwipeUp.isContinuous)
        #expect(GestureKind.swipe(fingers: 3, direction: .up) == .threeFingerSwipeUp)
        #expect(GestureKind.swipe(fingers: 4, direction: .left) == .fourFingerSwipeLeft)
        #expect(GestureKind.swipe(fingers: 2, direction: .down) == .twoFingerSwipeDown)
        #expect(GestureKind.swipe(fingers: 5, direction: .right) == .fiveFingerSwipeRight)
        #expect(GestureKind.swipe(fingers: 6, direction: .up) == nil)
    }

    @Test func codableUsesRawValues() throws {
        let data = try JSONEncoder().encode([GestureKind.twoFingerDrag, .fiveFingerSplay])
        #expect(String(decoding: data, as: UTF8.self) == "[\"twoFingerDrag\",\"fiveFingerSplay\"]")
        let dict = try JSONDecoder().decode([GestureKind: Int].self, from: Data("{\"tap\": 1, \"press\": 2}".utf8))
        #expect(dict == [.tap: 1, .press: 2])
    }
}
