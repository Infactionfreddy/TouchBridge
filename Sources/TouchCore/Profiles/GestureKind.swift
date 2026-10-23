import Foundation

/// Section of the settings window a gesture belongs to.
public enum FingerGroup: String, Codable, Sendable, CaseIterable {
    case oneFinger = "One finger"
    case twoFingers = "Two fingers"
    case threeFingers = "Three fingers"
    case fourFingers = "Four fingers"
    case fiveFingers = "Five fingers"
    case edges = "Edges"
}

/// Every gesture TouchBridge knows, following the UPDD gesture catalogue. The raw values are the JSON keys
/// of `GestureProfile.bindings` and must never change. Case order is display order.
public enum GestureKind: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case tap, doubleTap, press, pressAndTap, drag
    case twoFingerTap, twoFingerDoubleTap, twoFingerDrag
    case twoFingerSwipeUp, twoFingerSwipeDown, twoFingerSwipeLeft, twoFingerSwipeRight
    case pinch, spread, rotateLeft, rotateRight
    case threeFingerTap, threeFingerDoubleTap, threeFingerDrag
    case threeFingerSwipeUp, threeFingerSwipeDown, threeFingerSwipeLeft, threeFingerSwipeRight
    case fourFingerTap, fourFingerDoubleTap, fourFingerDrag
    case fourFingerSwipeUp, fourFingerSwipeDown, fourFingerSwipeLeft, fourFingerSwipeRight
    case fourFingerSqueeze, fourFingerSplay
    case fiveFingerTap, fiveFingerDoubleTap, fiveFingerDrag
    case fiveFingerSwipeUp, fiveFingerSwipeDown, fiveFingerSwipeLeft, fiveFingerSwipeRight
    case fiveFingerSqueeze, fiveFingerSplay
    case oneFingerEdgeSwipeFromLeft, oneFingerEdgeSwipeFromRight
    case twoFingerEdgeSwipeFromLeft, twoFingerEdgeSwipeFromRight

    /// Gestures the engine recognizes today (Part A).
    public static let recognized: Set<GestureKind> = [
        .tap, .doubleTap, .press, .drag, .twoFingerTap, .twoFingerDrag, .pinch, .spread, .rotateLeft, .rotateRight,
        .threeFingerSwipeUp, .threeFingerSwipeDown, .threeFingerSwipeLeft, .threeFingerSwipeRight,
        .fourFingerSwipeUp, .fourFingerSwipeDown, .fourFingerSwipeLeft, .fourFingerSwipeRight,
    ]

    public var isRecognized: Bool { Self.recognized.contains(self) }

    /// Phase gestures: the binding decision made at `began` holds for the whole gesture.
    public var isContinuous: Bool {
        switch self {
        case .drag, .twoFingerDrag, .threeFingerDrag, .fourFingerDrag, .fiveFingerDrag,
             .pinch, .spread, .rotateLeft, .rotateRight,
             .fourFingerSqueeze, .fourFingerSplay, .fiveFingerSqueeze, .fiveFingerSplay:
            return true
        default:
            return false
        }
    }

    public var group: FingerGroup {
        let raw = rawValue
        if raw.contains("EdgeSwipe") { return .edges }
        if raw.hasPrefix("twoFinger") || self == .pinch || self == .spread || self == .rotateLeft || self == .rotateRight { return .twoFingers }
        if raw.hasPrefix("threeFinger") { return .threeFingers }
        if raw.hasPrefix("fourFinger") { return .fourFingers }
        if raw.hasPrefix("fiveFinger") { return .fiveFingers }
        return .oneFinger
    }

    /// "twoFingerSwipeUp" → "Two finger swipe up".
    public var displayName: String {
        var words: [String] = []
        var current = ""
        for character in rawValue {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character.lowercased())
        }
        words.append(current)
        return words.enumerated().map { $0.offset == 0 ? $0.element.capitalized : $0.element }.joined(separator: " ")
    }

    /// The swipe kind for an engine swipe action; nil for finger counts without a swipe gesture.
    public static func swipe(fingers: Int, direction: SwipeDirection) -> GestureKind? {
        let prefix: String
        switch fingers {
        case 2: prefix = "twoFinger"
        case 3: prefix = "threeFinger"
        case 4: prefix = "fourFinger"
        case 5: prefix = "fiveFinger"
        default: return nil
        }
        let suffix: String
        switch direction {
        case .up: suffix = "Up"
        case .down: suffix = "Down"
        case .left: suffix = "Left"
        case .right: suffix = "Right"
        }
        return GestureKind(rawValue: prefix + "Swipe" + suffix)
    }
}
