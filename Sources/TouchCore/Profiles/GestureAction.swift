import Foundation

/// Named system shortcuts, posted as their default key combinations.
public enum SystemAction: String, Codable, Sendable, CaseIterable {
    case missionControl, appExpose, spaceLeft, spaceRight, showDesktop

    public var displayName: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .spaceLeft: return "Space left"
        case .spaceRight: return "Space right"
        case .showDesktop: return "Show desktop"
        }
    }

    public var keyCommand: KeyCommand {
        switch self {
        case .missionControl: return .missionControl
        case .appExpose: return .appExpose
        case .spaceLeft: return .spaceLeft
        case .spaceRight: return .spaceRight
        case .showDesktop: return .showDesktop
        }
    }
}

/// What a gesture does. JSON shape: `{"mouseClick":{"button":"middle","count":1}}`, `{"none":{}}`, …
/// Unknown actions (written by a newer version) decode as `passThrough`.
public enum GestureAction: Codable, Equatable, Sendable {
    /// The gesture is swallowed.
    case none
    /// The built-in behaviour: cursor, click, drag, scroll, magnify, rotate. For swipes there is no native
    /// behaviour, so `passThrough` on a swipe is the same as `none`.
    case passThrough
    case mouseClick(button: MouseButton, count: Int)
    case keystroke(key: KeyCommand)
    case systemAction(action: SystemAction)
    case openFile(path: String)

    private enum CodingKeys: String, CodingKey {
        case none, passThrough, mouseClick, keystroke, systemAction, openFile
    }

    private struct Empty: Codable {}
    private struct Click: Codable { var button: MouseButton; var count: Int }
    private struct Keystroke: Codable { var key: KeyCommand }
    private struct System: Codable { var action: SystemAction }
    private struct File: Codable { var path: String }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = container.allKeys.first else {
            self = .passThrough
            return
        }
        do {
            switch key {
            case .none: self = .none
            case .passThrough: self = .passThrough
            case .mouseClick:
                let c = try container.decode(Click.self, forKey: .mouseClick)
                self = .mouseClick(button: c.button, count: min(max(c.count, 1), 3))
            case .keystroke: self = .keystroke(key: try container.decode(Keystroke.self, forKey: .keystroke).key)
            case .systemAction: self = .systemAction(action: try container.decode(System.self, forKey: .systemAction).action)
            case .openFile: self = .openFile(path: try container.decode(File.self, forKey: .openFile).path)
            }
        } catch {
            self = .passThrough
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none: try container.encode(Empty(), forKey: .none)
        case .passThrough: try container.encode(Empty(), forKey: .passThrough)
        case .mouseClick(let button, let count): try container.encode(Click(button: button, count: count), forKey: .mouseClick)
        case .keystroke(let key): try container.encode(Keystroke(key: key), forKey: .keystroke)
        case .systemAction(let action): try container.encode(System(action: action), forKey: .systemAction)
        case .openFile(let path): try container.encode(File(path: path), forKey: .openFile)
        }
    }
}

/// How one gesture behaves in a profile.
public struct GestureBinding: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var action: GestureAction
    /// Scroll direction for `twoFingerDrag`; ignored by other kinds.
    public var naturalScrolling: Bool?
    /// Momentum after lift-off for `twoFingerDrag`; ignored by other kinds.
    public var momentum: Bool?

    public init(enabled: Bool = true, action: GestureAction = .passThrough, naturalScrolling: Bool? = nil, momentum: Bool? = nil) {
        self.enabled = enabled
        self.action = action
        self.naturalScrolling = naturalScrolling
        self.momentum = momentum
    }

    private enum CodingKeys: String, CodingKey { case enabled, action, naturalScrolling, momentum }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        action = (try? c.decodeIfPresent(GestureAction.self, forKey: .action)) ?? .passThrough
        naturalScrolling = try c.decodeIfPresent(Bool.self, forKey: .naturalScrolling)
        momentum = try c.decodeIfPresent(Bool.self, forKey: .momentum)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(action, forKey: .action)
        try c.encodeIfPresent(naturalScrolling, forKey: .naturalScrolling)
        try c.encodeIfPresent(momentum, forKey: .momentum)
    }

    /// The milestone 1/2 default set.
    public static func builtIn(for kind: GestureKind) -> GestureBinding {
        switch kind {
        case .twoFingerDrag:
            return GestureBinding(action: .passThrough, naturalScrolling: true, momentum: true)
        case .threeFingerSwipeUp, .fourFingerSwipeUp:
            return GestureBinding(action: .systemAction(action: .missionControl))
        case .threeFingerSwipeDown, .fourFingerSwipeDown:
            return GestureBinding(action: .systemAction(action: .appExpose))
        case .threeFingerSwipeLeft, .fourFingerSwipeLeft:
            return GestureBinding(action: .systemAction(action: .spaceRight))    // fingers left → next space
        case .threeFingerSwipeRight, .fourFingerSwipeRight:
            return GestureBinding(action: .systemAction(action: .spaceLeft))
        default:
            return GestureBinding(action: kind.isRecognized ? .passThrough : .none)
        }
    }
}
