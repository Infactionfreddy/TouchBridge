# TouchBridge Gesture Profiles and Settings Window (Part A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-application gesture profiles (bindings and tuning overriding a default profile, resolved by the frontmost app) with a settings window, following the UPDD model.

**Architecture:** TouchCore gains a complete gesture catalogue (`GestureKind`), an action model (`GestureAction`), profiles with partial overrides and a pure `ProfileResolver`; `Settings` moves to schema 2 with migration. The `GestureEngine` stays unchanged except for a `ClickSource` on click actions; the `ActionRouter` maps engine actions to commands through the effective profile. The app observes the frontmost application, swaps router and engine config per pipeline, and offers a SwiftUI settings window (sidebar of profiles, Gestures and Tuning tabs, shortcut recorder).

**Tech Stack:** Swift 6 language mode, Swift Package Manager, Swift Testing, SwiftUI (`NavigationSplitView`, `List`, `Form`), AppKit (`NSWorkspace`, `NSOpenPanel`, `NSEvent`), CoreGraphics `CGEvent`, Carbon `UCKeyTranslate` for key names.

**Spec:** `docs/superpowers/specs/2026-10-21-touchbridge-profiles-settings-design.md` (German). Baseline: `docs/superpowers/specs/2026-10-12-touchbridge-design.md`.

## Global Constraints

- Swift tools version 6.0, language mode 6; every type in TouchCore is `Sendable`; no global mutable state; TouchCore imports only Foundation and CoreGraphics geometry; TouchCore never reads system clocks.
- Minimum macOS 14; built on macOS 26.6.2 / Swift 6.4. Build and test with `--scratch-path /private/tmp/claude-501/tb-build` (Finder attributes under ~/Documents break codesign in `.build`).
- UI language English. Code, comments, docs in English.
- `GestureKind` raw values are JSON keys and must never change once shipped. `isRecognized` is true for exactly these eighteen kinds: `tap`, `doubleTap`, `press`, `drag`, `twoFingerTap`, `twoFingerDrag`, `pinch`, `spread`, `rotateLeft`, `rotateRight`, `threeFingerSwipeUp/Down/Left/Right`, `fourFingerSwipeUp/Down/Left/Right`.
- Built-in default bindings reproduce the milestone 1/2 default set exactly: `passThrough` for the recognized one- and two-finger gestures; `systemAction(missionControl)` for 3/4-finger swipe up, `appExpose` for down, `spaceRight` for left, `spaceLeft` for right; `twoFingerDrag` has `naturalScrolling = true`, `momentum = true`; all unrecognized kinds `none`.
- System action shortcuts: Mission Control ⌃↑ (126), App Exposé ⌃↓ (125), Space left ⌃← (123), Space right ⌃→ (124), Show desktop F11 (103, no modifiers).
- Mouse buttons: `left`, `right`, `middle`, `back`, `forward`; `middle`, `back`, `forward` post `otherMouseDown/Up` with button numbers 2, 3, 4.
- `Settings` schema 2: `schemaVersion`, `enabled`, `displaySelection`, `calibrations`, `launchAtLogin`, `defaultProfile`, `appProfiles`. Schema 1 files are migrated on load, the original copied to `settings.json.v1`, the result saved immediately.
- Inheritance: built-in defaults ⟵ default profile ⟵ app profile; bindings per gesture kind, config field by field; every applied config is clamped with the same limits `GestureConfig.init(from:)` uses.
- Continuous gestures (`drag`, `twoFingerDrag`, `pinch`/`spread`, `rotateLeft`/`rotateRight`): the binding decision made at the `began` phase holds for the whole gesture. `passThrough` passes every phase; `none` or disabled drops every phase; a discrete action (mouse click, keystroke, system action, open file) fires once at `began` and drops the rest.
- TouchBridge's own bundle id (`org.touchbridge.TouchBridge`) and an unknown frontmost app always use the default profile.
- Logging: `os.Logger` subsystem `org.touchbridge`; `openFile` failures logged in category `pipeline`.
- Commit messages: conventional prefixes, no attribution trailers.

## Review Focus

Inputs the spec implies but did not list; each has a pinned test in the owning task:

1. **Settings file with a binding for an unknown gesture kind or an unknown action** (a profile written by a newer version): the kind is dropped, the action falls back to `passThrough`, nothing else in the file is lost. → Task 5 (`GestureProfileTests.unknownKindsAreDroppedAndUnknownActionsFallBack`).
2. **Frontmost app changes while a drag or scroll is in progress**: the running gesture keeps the decision made at `began`; the new profile applies to the next gesture. → Task 7 (`ActionRouterTests.continuingRouterKeepsSuppressedGestures`), wired in Task 8.
3. **App profile override outside the allowed range** (hand-edited `stuckTimeout: -1`): clamped exactly like a decoded default config, never a crash. → Task 5 (`ProfileResolverTests.overridesAreClamped`).
4. **Two app profiles with the same bundle id in the file**: the first is kept, the duplicate dropped on load, and a save writes one. → Task 6 (`SettingsStoreTests.duplicateProfilesCollapse`).
5. **Tap bound to a keystroke while double tap stays pass-through**: the first tap fires the keystroke, the second tap passes a click with count 2 — each kind's binding is independent and the sequence is deterministic. → Task 7 (`ActionRouterTests.doubleTapUsesItsOwnBinding`).

---

## File Structure

```
Sources/TouchCore/Gesture/Action.swift            MouseButton gains middle/back/forward + Codable; ClickSource; Action.click(source:)
Sources/TouchCore/Gesture/GestureEngine.swift     sets ClickSource at the five click sites (no other change)
Sources/TouchCore/Gesture/GestureConfig.swift     clamped(); init(from:) uses it
Sources/TouchCore/Profiles/GestureKind.swift      FingerGroup, GestureKind catalogue, displayName, isRecognized, isContinuous, swipe(fingers:direction:)
Sources/TouchCore/Profiles/GestureAction.swift    SystemAction, GestureAction, GestureBinding (+ builtIn defaults, lenient Codable)
Sources/TouchCore/Profiles/GestureProfile.swift   GestureConfigOverrides, GestureProfile (lenient bindings decoding)
Sources/TouchCore/Profiles/ProfileResolver.swift  EffectiveProfile, ProfileResolver
Sources/TouchCore/Routing/Command.swift           KeyCommand Codable + showDesktop; Command.openFile
Sources/TouchCore/Routing/ActionRouter.swift      profile-driven routing with continuous-gesture state
Sources/TouchCore/Settings/Settings.swift         schema 2, legacy migration in init(from:), conveniences
Sources/TouchCore/Settings/SettingsStore.swift    .v1 copy + save after migration, duplicate profile collapse
Sources/TouchInject/EventInjector.swift           mouseEventTypes(for:) for all buttons
Sources/TouchBridge/FrontmostAppObserver.swift    NSWorkspace activation → bundle id
Sources/TouchBridge/DevicePipeline.swift          apply(profile:enabled:), onOpenFile, router continuity
Sources/TouchBridge/PipelineController.swift      frontmost observer, profile resolution, openFile execution
Sources/TouchBridge/AppState.swift                profile editing API, settings window, active profile header data
Sources/TouchBridge/Views/MenuContent.swift       "Settings…" replaces "Open settings file"
Sources/TouchBridge/Views/Settings/SettingsView.swift        split view, header, tabs
Sources/TouchBridge/Views/Settings/ProfileSidebar.swift      Default + app profiles, add/remove
Sources/TouchBridge/Views/Settings/GesturesTab.swift         grouped gesture rows, action menu, options
Sources/TouchBridge/Views/Settings/TuningTab.swift           all GestureConfig fields, override checkboxes
Sources/TouchBridge/Views/Settings/ShortcutRecorder.swift    NSViewRepresentable key recorder + key names
Sources/TouchBridge/Views/Settings/AppInfo.swift             icon and name for a bundle id
Tests/TouchCoreTests/GestureKindTests.swift
Tests/TouchCoreTests/GestureActionTests.swift
Tests/TouchCoreTests/GestureProfileTests.swift
Tests/TouchCoreTests/ProfileResolverTests.swift
Tests/TouchCoreTests/ActionRouterTests.swift       rewritten
Tests/TouchCoreTests/SettingsStoreTests.swift      updated + migration tests
Tests/TouchCoreTests/GestureEngine*Tests.swift     click expectations gain source:
Tests/TouchInjectTests/EventBuilderTests.swift     other mouse buttons
```

Test commands: `swift build --scratch-path /private/tmp/claude-501/tb-build`, `swift test --scratch-path /private/tmp/claude-501/tb-build [--filter <Suite>]`. Baseline before Task 1: 99 TouchCore tests + 13 TouchInject tests pass.

---

### Task 1: ClickSource and the extended MouseButton

**Files:**
- Modify: `Sources/TouchCore/Gesture/Action.swift`
- Modify: `Sources/TouchCore/Gesture/GestureEngine.swift` (five `.click(` sites)
- Modify: `Sources/TouchCore/Routing/ActionRouter.swift` (one pattern)
- Modify: `Tests/TouchCoreTests/GestureEngineOneFingerTests.swift`, `Tests/TouchCoreTests/GestureEngineTwoFingerTests.swift`, `Tests/TouchCoreTests/ActionRouterTests.swift`

**Interfaces:**
- Produces: `MouseButton` (`String`, `Codable`, `CaseIterable`: `left, right, middle, back, forward`), `ClickSource` (`tap, longPress, twoFingerTap`), `Action.click(button:at:count:source:)`. Used by Tasks 2, 4, 7.

- [ ] **Step 1: Change Action.swift**

Replace the `MouseButton` enum and the `click` case:

```swift
/// Logical mouse buttons. `middle`, `back` and `forward` map to the "other" mouse events (button numbers 2, 3, 4).
public enum MouseButton: String, Codable, Sendable, Equatable, CaseIterable {
    case left, right, middle, back, forward

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .middle: return "Middle"
        case .back: return "Back"
        case .forward: return "Forward"
        }
    }
}

/// Which gesture produced a click; the router looks up that gesture's binding.
public enum ClickSource: Sendable, Equatable {
    /// One-finger tap (`count` 1) or double tap (`count` 2).
    case tap
    /// One finger resting longer than `longPressDuration`.
    case longPress
    case twoFingerTap
}
```

and in `Action`:

```swift
    case click(button: MouseButton, at: CGPoint, count: Int, source: ClickSource)
```

- [ ] **Step 2: Set the source at the five engine sites**

In `Sources/TouchCore/Gesture/GestureEngine.swift`:

| Site | Old | New |
| --- | --- | --- |
| `tick`, `.oneFinger` long press | `return [.click(button: .right, at: last, count: 1)]` | `return [.click(button: .right, at: last, count: 1, source: .longPress)]` |
| `finishTwoFinger`, `.twoPending` n == 0 | `return (isTap ? [.click(button: .right, at: c, count: 1)] : [], false)` | `return (isTap ? [.click(button: .right, at: c, count: 1, source: .twoFingerTap)] : [], false)` |
| `finishTwoFinger`, `.twoReleasing` n == 0 | same as above | same new text |
| `continueGesture`, `.oneFinger` long press | `return [.click(button: .right, at: p, count: 1)]` | `return [.click(button: .right, at: p, count: 1, source: .longPress)]` |
| `tapActions` | `return [.click(button: .left, at: position, count: count)]` | `return [.click(button: .left, at: position, count: count, source: .tap)]` |

In `Sources/TouchCore/Routing/ActionRouter.swift` change the pattern `case .click(let button, let p, let count):` to `case .click(let button, let p, let count, _):` (Task 7 rewrites this file; this keeps it compiling now).

- [ ] **Step 3: Update the tests**

`Tests/TouchCoreTests/GestureEngineOneFingerTests.swift`: every `.click(button: .left, at: …, count: N)` gains `, source: .tap` before the closing parenthesis (9 occurrences: `tapProducesLeftClick`, `doubleTap` ×2, `secondTapFarAwayIsSingleClick`, `slowLiftWithoutMovementIsStillAClick`, `reusedIDAfterLiftStartsFreshTap` ×2, `contactReplacedDuringTapClicksAndRestarts` ×2). The two right clicks in `longPressRightClickViaTick` and `longPressRightClickViaFrame` gain `, source: .longPress`.

`Tests/TouchCoreTests/GestureEngineTwoFingerTests.swift`: the three `.click(button: .right, at: pt(120, 100), count: 1)` (in `twoFingerTapIsRightClick`, `staggeredTwoFingerTapIsRightClick`, `staggeredTwoFingerTapWithIntermediateFrames`) gain `, source: .twoFingerTap`.

`Tests/TouchCoreTests/ActionRouterTests.swift` line in `mouseActionsPassThrough`: `.click(button: .right, at: pt(1, 2), count: 1)` becomes `.click(button: .right, at: pt(1, 2), count: 1, source: .longPress)`.

- [ ] **Step 4: Build and run the engine and router suites**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter "GestureEngine|ActionRouter"`
Expected: 40 engine tests + 5 router tests pass. Then the full suite: 99 + 13 pass (TouchInject compiles unchanged because it compares `button == .left`).

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchCore/Gesture/Action.swift Sources/TouchCore/Gesture/GestureEngine.swift Sources/TouchCore/Routing/ActionRouter.swift Tests/TouchCoreTests
git commit -m "feat(core): tag click actions with their gesture source and extend MouseButton"
```

---

### Task 2: Middle, back and forward buttons in the injector

**Files:**
- Modify: `Sources/TouchInject/EventInjector.swift`
- Test: `Tests/TouchInjectTests/EventBuilderTests.swift`

**Interfaces:**
- Consumes: `MouseButton` (Task 1).
- Produces: `EventInjector.mouseEventTypes(for:) -> (down: CGEventType, up: CGEventType, button: CGMouseButton)`.

- [ ] **Step 1: Write the failing test**

Append to `EventBuilderTests`:

```swift
    @Test func otherMouseButtonsUseOtherEventsWithButtonNumbers() throws {
        #expect(EventInjector.mouseEventTypes(for: .left) == (.leftMouseDown, .leftMouseUp, .left))
        #expect(EventInjector.mouseEventTypes(for: .right) == (.rightMouseDown, .rightMouseUp, .right))
        let middle = EventInjector.mouseEventTypes(for: .middle)
        #expect(middle.down == .otherMouseDown && middle.up == .otherMouseUp && middle.button.rawValue == 2)
        #expect(EventInjector.mouseEventTypes(for: .back).button.rawValue == 3)
        #expect(EventInjector.mouseEventTypes(for: .forward).button.rawValue == 4)
        let e = try #require(EventInjector.mouseEvent(.otherMouseDown, at: p, button: EventInjector.mouseEventTypes(for: .back).button, clickCount: 1, source: source))
        #expect(e.type == .otherMouseDown)
        #expect(e.getIntegerValueField(.mouseEventButtonNumber) == 3)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter EventBuilderTests`
Expected: compile error "type 'EventInjector' has no member 'mouseEventTypes'".

- [ ] **Step 3: Implement**

In `EventInjector.perform`, replace the `.click` case body:

```swift
        case .click(let button, let p, let count):
            let types = Self.mouseEventTypes(for: button)
            post(Self.mouseEvent(.mouseMoved, at: p, button: .left, clickCount: 0, source: source))
            post(Self.mouseEvent(types.down, at: p, button: types.button, clickCount: count, source: source))
            post(Self.mouseEvent(types.up, at: p, button: types.button, clickCount: count, source: source))
```

Add next to the other static builders:

```swift
    /// CGEvent types and button for a logical button. Middle, back and forward are "other" mouse events with the
    /// button numbers AppKit reports as `NSEvent.buttonNumber` (2, 3, 4).
    static func mouseEventTypes(for button: MouseButton) -> (down: CGEventType, up: CGEventType, button: CGMouseButton) {
        switch button {
        case .left: return (.leftMouseDown, .leftMouseUp, .left)
        case .right: return (.rightMouseDown, .rightMouseUp, .right)
        case .middle: return (.otherMouseDown, .otherMouseUp, .center)
        case .back: return (.otherMouseDown, .otherMouseUp, CGMouseButton(rawValue: 3) ?? .center)
        case .forward: return (.otherMouseDown, .otherMouseUp, CGMouseButton(rawValue: 4) ?? .center)
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter EventBuilderTests`
Expected: 8 tests pass. If `getIntegerValueField(.mouseEventButtonNumber)` returns 0 for button 3, CoreGraphics ignored the raw button; then set the field explicitly in `mouseEvent` (`event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))`) and keep the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchInject/EventInjector.swift Tests/TouchInjectTests/EventBuilderTests.swift
git commit -m "feat(inject): middle, back and forward mouse buttons"
```

---

### Task 3: Gesture catalogue

**Files:**
- Create: `Sources/TouchCore/Profiles/GestureKind.swift`
- Test: `Tests/TouchCoreTests/GestureKindTests.swift`

**Interfaces:**
- Consumes: `SwipeDirection` (Action.swift).
- Produces: `FingerGroup`, `GestureKind` (`String` raw, `Codable`, `CaseIterable`, `CodingKeyRepresentable`), `.group`, `.displayName`, `.isRecognized`, `.isContinuous`, `GestureKind.recognized: Set<GestureKind>`, `GestureKind.swipe(fingers:direction:) -> GestureKind?`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter GestureKindTests`
Expected: compile error "cannot find 'GestureKind' in scope".

- [ ] **Step 3: Implement**

`Sources/TouchCore/Profiles/GestureKind.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter GestureKindTests`
Expected: 5 tests pass. If `codableUsesRawValues` fails to decode the dictionary with an "expected to decode Array" error, the `CodingKeyRepresentable` conformance is missing — it is what lets Swift encode `[GestureKind: …]` as a JSON object.

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchCore/Profiles/GestureKind.swift Tests/TouchCoreTests/GestureKindTests.swift
git commit -m "feat(core): gesture catalogue following the UPDD gesture list"
```

---

### Task 4: Actions and bindings

**Files:**
- Create: `Sources/TouchCore/Profiles/GestureAction.swift`
- Modify: `Sources/TouchCore/Routing/Command.swift` (`KeyCommand: Codable`, `showDesktop`, `Command.openFile`)
- Test: `Tests/TouchCoreTests/GestureActionTests.swift`

**Interfaces:**
- Consumes: `MouseButton`, `KeyCommand`, `GestureKind`.
- Produces: `SystemAction` (`missionControl, appExpose, spaceLeft, spaceRight, showDesktop`; `.displayName`, `.keyCommand`), `GestureAction` (`none`, `passThrough`, `mouseClick(button:count:)`, `keystroke(key:)`, `systemAction(action:)`, `openFile(path:)`; lenient decoding), `GestureBinding` (`enabled`, `action`, `naturalScrolling: Bool?`, `momentum: Bool?`; `GestureBinding.builtIn(for:)`), `Command.openFile(String)`, `KeyCommand.showDesktop`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter GestureActionTests`
Expected: compile error "cannot find 'GestureAction' in scope".

- [ ] **Step 3: Extend Command.swift**

Make `KeyCommand` `Codable` (`public struct KeyCommand: Equatable, Sendable, Codable`) and add after `spaceRight`:

```swift
    public static let showDesktop = KeyCommand(keyCode: 103)                 // F11
```

Add to `Command`:

```swift
    /// Opens a file or application; executed by the app layer, not the injector.
    case openFile(String)
```

- [ ] **Step 4: Write GestureAction.swift**

```swift
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
```

- [ ] **Step 5: Run to verify the tests pass**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter GestureActionTests`
Expected: 5 tests pass. Then the full suite still passes (`Command.openFile` is a new case: `EventInjector.perform` switches over `Command` exhaustively — add `case .openFile: break  // executed by the app layer` there so TouchInject compiles).

- [ ] **Step 6: Commit**

```bash
git add Sources/TouchCore/Profiles/GestureAction.swift Sources/TouchCore/Routing/Command.swift Sources/TouchInject/EventInjector.swift Tests/TouchCoreTests/GestureActionTests.swift
git commit -m "feat(core): gesture actions, bindings and built-in default set"
```

---

### Task 5: Profiles, overrides and the resolver

**Files:**
- Modify: `Sources/TouchCore/Gesture/GestureConfig.swift` (add `clamped()`, use it in `init(from:)`)
- Create: `Sources/TouchCore/Profiles/GestureProfile.swift`, `Sources/TouchCore/Profiles/ProfileResolver.swift`
- Test: `Tests/TouchCoreTests/GestureProfileTests.swift`, `Tests/TouchCoreTests/ProfileResolverTests.swift`

**Interfaces:**
- Consumes: `GestureConfig`, `GestureKind`, `GestureBinding`.
- Produces: `GestureConfig.clamped()`, `GestureConfigOverrides` (`init()`, `init(full:)`, `isEmpty`, `apply(to:)`), `GestureConfigField` (`label`, `unit`, `step`, `value` key path, `override` key path, `GestureConfigField.all`), `GestureProfile` (`defaultID`, `id`, `bundleID`, `displayName`, `bindings`, `config`), `EffectiveProfile` (`profileID`, `profileName`, `config`, `bindings`, `binding(_:)`, `.builtIn`), `ProfileResolver.effective(for:defaultProfile:appProfiles:)`. Used by Tasks 6–11.

- [ ] **Step 1: Write the failing tests**

`Tests/TouchCoreTests/GestureProfileTests.swift`:

```swift
import Testing
import Foundation
@testable import TouchCore

@Suite struct GestureProfileTests {
    @Test func overridesApplyFieldByFieldAndClamp() {
        var o = GestureConfigOverrides()
        #expect(o.isEmpty)
        o.longPressDuration = 1.0
        o.stuckTimeout = -1          // clamped to 0
        o.momentumDecayPerFrame = 5  // clamped to 0.999
        let applied = o.apply(to: GestureConfig())
        #expect(applied.longPressDuration == 1.0)
        #expect(applied.stuckTimeout == 0)
        #expect(applied.momentumDecayPerFrame == 0.999)
        #expect(applied.tapMaxMovement == GestureConfig().tapMaxMovement)
        var full = GestureConfig()
        full.swipeDistance = 90
        #expect(GestureConfigOverrides(full: full).apply(to: GestureConfig()) == full)
        #expect(!GestureConfigOverrides(full: full).isEmpty)
    }

    @Test func clampedMatchesDecodeLimits() throws {
        var c = GestureConfig()
        c.rotateThreshold = 400
        c.velocityWindow = .nan
        let clamped = c.clamped()
        #expect(clamped.rotateThreshold == 180)
        #expect(clamped.velocityWindow == GestureConfig().velocityWindow)
        let decoded = try JSONDecoder().decode(GestureConfig.self, from: Data("{\"rotateThreshold\": 400}".utf8))
        #expect(decoded.rotateThreshold == 180)
    }

    @Test func fieldDescriptorsCoverEveryTunable() {
        #expect(GestureConfigField.all.count == 14)
        #expect(GestureConfigField.all.map(\.label).contains("Long press duration"))
        var o = GestureConfigOverrides()
        for field in GestureConfigField.all { o[keyPath: field.override] = 1 }
        #expect(!o.isEmpty)
        let config = o.apply(to: GestureConfig())
        for field in GestureConfigField.all where field.label != "Momentum decay per frame" {
            #expect(config[keyPath: field.value] == 1, field.label)
        }
        #expect(config.momentumDecayPerFrame == 0.999)
    }

    @Test func profileRoundTripsThroughJSON() throws {
        var overrides = GestureConfigOverrides()
        overrides.tapMaxDuration = 0.4
        let profile = GestureProfile(bundleID: "com.apple.Safari", displayName: "Safari",
                                     bindings: [.twoFingerTap: GestureBinding(action: .mouseClick(button: .middle, count: 1)),
                                                .threeFingerSwipeLeft: GestureBinding(action: .keystroke(key: KeyCommand(keyCode: 33, command: true)))],
                                     config: overrides)
        let data = try JSONEncoder().encode(profile)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"twoFingerTap\":{"))
        #expect(!json.contains("stuckTimeout"))
        #expect(try JSONDecoder().decode(GestureProfile.self, from: data) == profile)
        #expect(profile.id == "com.apple.Safari")
        #expect(GestureProfile().id == GestureProfile.defaultID)
    }

    @Test func unknownKindsAreDroppedAndUnknownActionsFallBack() throws {
        let json = """
        {"bundleID":"com.example.App","displayName":"App",
         "bindings":{"tap":{"enabled":true,"action":{"none":{}}},
                     "sixFingerWiggle":{"enabled":true,"action":{"none":{}}},
                     "press":{"action":{"warp":{"to":"moon"}}}},
         "config":{"longPressDuration":0.7,"gravity":9.81}}
        """
        let profile = try JSONDecoder().decode(GestureProfile.self, from: Data(json.utf8))
        #expect(profile.bindings == [.tap: GestureBinding(action: .none), .press: GestureBinding(action: .passThrough)])
        #expect(profile.config.longPressDuration == 0.7)
        let reencoded = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        #expect(!reencoded.contains("sixFingerWiggle"))
    }

    @Test func profileWithoutNameOrBindingsDecodes() throws {
        let profile = try JSONDecoder().decode(GestureProfile.self, from: Data("{\"bundleID\":\"com.example.App\"}".utf8))
        #expect(profile.displayName == "com.example.App")
        #expect(profile.bindings.isEmpty)
        #expect(profile.config.isEmpty)
    }
}
```

`Tests/TouchCoreTests/ProfileResolverTests.swift`:

```swift
import Testing
@testable import TouchCore

@Suite struct ProfileResolverTests {
    var defaultProfile: GestureProfile {
        var config = GestureConfigOverrides()
        config.longPressDuration = 0.8
        return GestureProfile(bindings: [.twoFingerTap: GestureBinding(action: .mouseClick(button: .middle, count: 1))], config: config)
    }
    var safari: GestureProfile {
        var config = GestureConfigOverrides()
        config.tapMaxDuration = 0.4
        return GestureProfile(bundleID: "com.apple.Safari", displayName: "Safari",
                              bindings: [.threeFingerSwipeLeft: GestureBinding(action: .keystroke(key: KeyCommand(keyCode: 33, command: true)))],
                              config: config)
    }

    @Test func appProfileOverridesDefaultWhichOverridesBuiltIn() {
        let e = ProfileResolver.effective(for: "com.apple.Safari", defaultProfile: defaultProfile, appProfiles: [safari])
        #expect(e.profileID == "com.apple.Safari")
        #expect(e.profileName == "Safari")
        #expect(e.binding(.twoFingerTap).action == .mouseClick(button: .middle, count: 1))     // from the default profile
        #expect(e.binding(.threeFingerSwipeLeft).action == .keystroke(key: KeyCommand(keyCode: 33, command: true)))
        #expect(e.binding(.threeFingerSwipeRight).action == .systemAction(action: .spaceLeft))   // built in
        #expect(e.config.longPressDuration == 0.8)
        #expect(e.config.tapMaxDuration == 0.4)
        #expect(e.config.swipeDistance == GestureConfig().swipeDistance)
        #expect(e.bindings.count == GestureKind.allCases.count)
    }

    @Test func nilAndUnknownBundleIDsUseTheDefaultProfile() {
        let forNil = ProfileResolver.effective(for: nil, defaultProfile: defaultProfile, appProfiles: [safari])
        let forUnknown = ProfileResolver.effective(for: "com.example.Unknown", defaultProfile: defaultProfile, appProfiles: [safari])
        #expect(forNil == forUnknown)
        #expect(forNil.profileID == GestureProfile.defaultID)
        #expect(forNil.binding(.threeFingerSwipeLeft).action == .systemAction(action: .spaceRight))
        #expect(forNil.config.tapMaxDuration == GestureConfig().tapMaxDuration)
    }

    @Test func emptyAppProfileEqualsTheDefaultProfileExceptForItsName() {
        let empty = GestureProfile(bundleID: "com.example.Empty", displayName: "Empty")
        let e = ProfileResolver.effective(for: "com.example.Empty", defaultProfile: defaultProfile, appProfiles: [empty])
        let d = ProfileResolver.effective(for: nil, defaultProfile: defaultProfile, appProfiles: [])
        #expect(e.bindings == d.bindings)
        #expect(e.config == d.config)
        #expect(e.profileName == "Empty")
    }

    @Test func overridesAreClamped() {
        var config = GestureConfigOverrides()
        config.stuckTimeout = -1
        config.momentumDecayPerFrame = 5
        let app = GestureProfile(bundleID: "com.example.App", displayName: "App", config: config)
        let e = ProfileResolver.effective(for: "com.example.App", defaultProfile: GestureProfile(), appProfiles: [app])
        #expect(e.config.stuckTimeout == 0)
        #expect(e.config.momentumDecayPerFrame == 0.999)
    }

    @Test func builtInEffectiveProfileIsTheDefaultSet() {
        let e = EffectiveProfile.builtIn
        #expect(e.config == GestureConfig())
        #expect(e.binding(.threeFingerSwipeUp).action == .systemAction(action: .missionControl))
        #expect(e.binding(.twoFingerDrag) == GestureBinding(action: .passThrough, naturalScrolling: true, momentum: true))
        #expect(e.binding(.fiveFingerTap).action == .none)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter "GestureProfileTests|ProfileResolverTests"`
Expected: compile errors (missing types).

- [ ] **Step 3: Add `clamped()` to GestureConfig**

Replace the body of `init(from:)` and the private `clamp` helper in `Sources/TouchCore/Gesture/GestureConfig.swift` with:

```swift
    /// Missing values take the default; every value is then clamped (see `clamped()`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureConfig()
        func read(_ key: CodingKeys, _ fallback: Double) throws -> Double {
            try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
        }
        tapMaxDuration = try read(.tapMaxDuration, d.tapMaxDuration)
        tapMaxMovement = try read(.tapMaxMovement, d.tapMaxMovement)
        doubleTapInterval = try read(.doubleTapInterval, d.doubleTapInterval)
        longPressDuration = try read(.longPressDuration, d.longPressDuration)
        classifyMovement = try read(.classifyMovement, d.classifyMovement)
        pinchThreshold = try read(.pinchThreshold, d.pinchThreshold)
        rotateThreshold = try read(.rotateThreshold, d.rotateThreshold)
        momentumMinVelocity = try read(.momentumMinVelocity, d.momentumMinVelocity)
        velocityWindow = try read(.velocityWindow, d.velocityWindow)
        momentumDecayPerFrame = try read(.momentumDecayPerFrame, d.momentumDecayPerFrame)
        momentumStopVelocity = try read(.momentumStopVelocity, d.momentumStopVelocity)
        swipeDistance = try read(.swipeDistance, d.swipeDistance)
        swipeMaxDuration = try read(.swipeMaxDuration, d.swipeMaxDuration)
        stuckTimeout = try read(.stuckTimeout, d.stuckTimeout)
        self = clamped()
    }

    /// Every field limited to its range; non-finite values take the default. Applied on decode and to profile
    /// overrides, so a hand-edited settings file can never crash the pipeline: durations 0…10 s,
    /// `momentumDecayPerFrame` 0…0.999, `velocityWindow` 0.008…1 s, `rotateThreshold` 0…180°, the rest ≥ 0.
    public func clamped() -> GestureConfig {
        let d = GestureConfig()
        let seconds = 0.0...10.0
        let nonNegative = 0.0...Double.greatestFiniteMagnitude
        var c = self
        c.tapMaxDuration = Self.clamp(tapMaxDuration, seconds, default: d.tapMaxDuration)
        c.tapMaxMovement = Self.clamp(tapMaxMovement, nonNegative, default: d.tapMaxMovement)
        c.doubleTapInterval = Self.clamp(doubleTapInterval, seconds, default: d.doubleTapInterval)
        c.longPressDuration = Self.clamp(longPressDuration, seconds, default: d.longPressDuration)
        c.classifyMovement = Self.clamp(classifyMovement, nonNegative, default: d.classifyMovement)
        c.pinchThreshold = Self.clamp(pinchThreshold, nonNegative, default: d.pinchThreshold)
        c.rotateThreshold = Self.clamp(rotateThreshold, 0...180, default: d.rotateThreshold)
        c.momentumMinVelocity = Self.clamp(momentumMinVelocity, nonNegative, default: d.momentumMinVelocity)
        c.velocityWindow = Self.clamp(velocityWindow, 0.008...1.0, default: d.velocityWindow)
        c.momentumDecayPerFrame = Self.clamp(momentumDecayPerFrame, 0...0.999, default: d.momentumDecayPerFrame)
        c.momentumStopVelocity = Self.clamp(momentumStopVelocity, nonNegative, default: d.momentumStopVelocity)
        c.swipeDistance = Self.clamp(swipeDistance, nonNegative, default: d.swipeDistance)
        c.swipeMaxDuration = Self.clamp(swipeMaxDuration, seconds, default: d.swipeMaxDuration)
        c.stuckTimeout = Self.clamp(stuckTimeout, seconds, default: d.stuckTimeout)
        return c
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
```

(The existing test `configClampsHostileValues` keeps passing.)

- [ ] **Step 4: Write GestureProfile.swift**

```swift
import Foundation

/// `GestureConfig` with every field optional; nil inherits from the profile below.
public struct GestureConfigOverrides: Codable, Equatable, Sendable {
    public var tapMaxDuration: Double?
    public var tapMaxMovement: Double?
    public var doubleTapInterval: Double?
    public var longPressDuration: Double?
    public var classifyMovement: Double?
    public var pinchThreshold: Double?
    public var rotateThreshold: Double?
    public var momentumMinVelocity: Double?
    public var velocityWindow: Double?
    public var momentumDecayPerFrame: Double?
    public var momentumStopVelocity: Double?
    public var swipeDistance: Double?
    public var swipeMaxDuration: Double?
    public var stuckTimeout: Double?

    public init() {}

    /// Overrides every field with the values of `config` (used when migrating a flat schema-1 config).
    public init(full config: GestureConfig) {
        for field in GestureConfigField.all {
            self[keyPath: field.override] = config[keyPath: field.value]
        }
    }

    public var isEmpty: Bool { self == GestureConfigOverrides() }

    /// `base` with every non-nil field replaced, then clamped.
    public func apply(to base: GestureConfig) -> GestureConfig {
        var result = base
        for field in GestureConfigField.all {
            if let value = self[keyPath: field.override] { result[keyPath: field.value] = value }
        }
        return result.clamped()
    }
}

/// One tunable of `GestureConfig`, for settings UIs: label, unit and where the value lives.
public struct GestureConfigField: Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let unit: String
    public let step: Double
    public let value: WritableKeyPath<GestureConfig, Double> & Sendable
    public let override: WritableKeyPath<GestureConfigOverrides, Double?> & Sendable

    public static let all: [GestureConfigField] = [
        GestureConfigField(label: "Tap max duration", unit: "s", step: 0.05, value: \.tapMaxDuration, override: \.tapMaxDuration),
        GestureConfigField(label: "Tap max movement", unit: "pt", step: 1, value: \.tapMaxMovement, override: \.tapMaxMovement),
        GestureConfigField(label: "Double tap interval", unit: "s", step: 0.05, value: \.doubleTapInterval, override: \.doubleTapInterval),
        GestureConfigField(label: "Long press duration", unit: "s", step: 0.05, value: \.longPressDuration, override: \.longPressDuration),
        GestureConfigField(label: "Scroll classification movement", unit: "pt", step: 1, value: \.classifyMovement, override: \.classifyMovement),
        GestureConfigField(label: "Pinch threshold", unit: "pt", step: 1, value: \.pinchThreshold, override: \.pinchThreshold),
        GestureConfigField(label: "Rotate threshold", unit: "°", step: 1, value: \.rotateThreshold, override: \.rotateThreshold),
        GestureConfigField(label: "Momentum minimum velocity", unit: "pt/s", step: 10, value: \.momentumMinVelocity, override: \.momentumMinVelocity),
        GestureConfigField(label: "Velocity window", unit: "s", step: 0.01, value: \.velocityWindow, override: \.velocityWindow),
        GestureConfigField(label: "Momentum decay per frame", unit: "", step: 0.005, value: \.momentumDecayPerFrame, override: \.momentumDecayPerFrame),
        GestureConfigField(label: "Momentum stop velocity", unit: "pt/s", step: 5, value: \.momentumStopVelocity, override: \.momentumStopVelocity),
        GestureConfigField(label: "Swipe distance", unit: "pt", step: 5, value: \.swipeDistance, override: \.swipeDistance),
        GestureConfigField(label: "Swipe max duration", unit: "s", step: 0.05, value: \.swipeMaxDuration, override: \.swipeMaxDuration),
        GestureConfigField(label: "Stuck contact timeout", unit: "s", step: 0.05, value: \.stuckTimeout, override: \.stuckTimeout),
    ]
}

/// The default profile (`bundleID == nil`) or the profile of one application. Only deviations are stored.
public struct GestureProfile: Codable, Equatable, Sendable, Identifiable {
    public static let defaultID = "default"

    public var id: String { bundleID ?? Self.defaultID }
    public var bundleID: String?
    public var displayName: String
    public var bindings: [GestureKind: GestureBinding]
    public var config: GestureConfigOverrides

    public init(bundleID: String? = nil, displayName: String = "Default",
                bindings: [GestureKind: GestureBinding] = [:], config: GestureConfigOverrides = GestureConfigOverrides()) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.bindings = bindings
        self.config = config
    }

    private enum CodingKeys: String, CodingKey { case bundleID, displayName, bindings, config }

    /// Lenient: unknown gesture kinds are dropped (a newer version may have written them), unknown actions
    /// fall back to `passThrough` inside `GestureBinding`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? bundleID ?? "Default"
        let raw = try c.decodeIfPresent([String: GestureBinding].self, forKey: .bindings) ?? [:]
        var bindings: [GestureKind: GestureBinding] = [:]
        for (key, binding) in raw {
            if let kind = GestureKind(rawValue: key) { bindings[kind] = binding }
        }
        self.bindings = bindings
        config = try c.decodeIfPresent(GestureConfigOverrides.self, forKey: .config) ?? GestureConfigOverrides()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(bundleID, forKey: .bundleID)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(bindings, forKey: .bindings)
        try c.encode(config, forKey: .config)
    }
}
```

If Swift 6 rejects `WritableKeyPath<…> & Sendable` as a stored property type or the `static let all`, mark `GestureConfigField` as `@unchecked Sendable` and use plain `WritableKeyPath` types; key paths to value-type properties carry no mutable state.

- [ ] **Step 5: Write ProfileResolver.swift**

```swift
import Foundation

/// A fully resolved profile: every gesture kind has a binding and the config is complete.
public struct EffectiveProfile: Equatable, Sendable {
    public var profileID: String
    public var profileName: String
    public var config: GestureConfig
    public var bindings: [GestureKind: GestureBinding]

    public init(profileID: String, profileName: String, config: GestureConfig, bindings: [GestureKind: GestureBinding]) {
        self.profileID = profileID
        self.profileName = profileName
        self.config = config
        self.bindings = bindings
    }

    public func binding(_ kind: GestureKind) -> GestureBinding {
        bindings[kind] ?? .builtIn(for: kind)
    }

    /// The milestone 1/2 default set with default tuning.
    public static let builtIn = ProfileResolver.effective(for: nil, defaultProfile: GestureProfile(), appProfiles: [])
}

/// Resolves built-in defaults ⟵ default profile ⟵ app profile. Pure and deterministic.
public enum ProfileResolver {
    public static func effective(for bundleID: String?, defaultProfile: GestureProfile, appProfiles: [GestureProfile]) -> EffectiveProfile {
        var bindings: [GestureKind: GestureBinding] = [:]
        for kind in GestureKind.allCases {
            bindings[kind] = defaultProfile.bindings[kind] ?? .builtIn(for: kind)
        }
        var config = defaultProfile.config.apply(to: GestureConfig())
        var id = GestureProfile.defaultID
        var name = defaultProfile.displayName
        if let bundleID, let app = appProfiles.first(where: { $0.bundleID == bundleID }) {
            for (kind, binding) in app.bindings { bindings[kind] = binding }
            config = app.config.apply(to: config)
            id = app.id
            name = app.displayName
        }
        return EffectiveProfile(profileID: id, profileName: name, config: config, bindings: bindings)
    }
}
```

- [ ] **Step 6: Run to verify the tests pass**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter "GestureProfileTests|ProfileResolverTests|GestureEngineOneFingerTests"`
Expected: 6 + 5 + 14 tests pass (the one-finger suite covers `configClampsHostileValues`).

- [ ] **Step 7: Commit**

```bash
git add Sources/TouchCore/Gesture/GestureConfig.swift Sources/TouchCore/Profiles Tests/TouchCoreTests/GestureProfileTests.swift Tests/TouchCoreTests/ProfileResolverTests.swift
git commit -m "feat(core): gesture profiles with partial overrides and the profile resolver"
```

---

### Task 6: Settings schema 2 and migration

**Files:**
- Modify: `Sources/TouchCore/Settings/Settings.swift`, `Sources/TouchCore/Settings/SettingsStore.swift`
- Modify: `Tests/TouchCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `GestureProfile`, `GestureConfigOverrides`, `EffectiveProfile`, `ProfileResolver`.
- Produces: `Settings` schema 2 (`defaultProfile`, `appProfiles`, computed `naturalScrolling`, `effectiveProfile(for:)`, `profile(id:)`, `upsert(_:)`, `removeProfile(bundleID:)`); `SettingsStore.load()` migrates schema 1 (backup `settings.json.v1`, immediate save). The field `settings.gesture` no longer exists — Task 8 updates the app layer.

- [ ] **Step 1: Update and extend the tests**

In `Tests/TouchCoreTests/SettingsStoreTests.swift`:

Replace the body of `roundTrip` with:

```swift
        let store = try temporaryStore()
        var s = Settings()
        s.enabled = false
        s.displaySelection = .display(uuid: "ABC-123")
        s.naturalScrolling = false
        s.defaultProfile.config.tapMaxMovement = 11
        var safariConfig = GestureConfigOverrides()
        safariConfig.longPressDuration = 1
        s.upsert(GestureProfile(bundleID: "com.apple.Safari", displayName: "Safari",
                                bindings: [.threeFingerSwipeLeft: GestureBinding(action: .keystroke(key: KeyCommand(keyCode: 33, command: true)))],
                                config: safariConfig))
        s.calibrations["20231224X1"] = Calibration(orientation: 90, scaleX: 1, scaleY: 1, offsetX: 0.01, offsetY: 0)
        s.launchAtLogin = true
        try store.save(s)
        #expect(store.load() == s)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(!text.contains("\"gesture\" :"))
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path + ".v1"))
```

In `partialFileGetsDefaults` replace the last three expectations with:

```swift
        #expect(s.naturalScrolling == true)
        #expect(s.defaultProfile == GestureProfile())
        #expect(s.appProfiles.isEmpty)
        #expect(s.displaySelection == .auto)
```

In `newerSchemaVersionIsNormalizedOnSave` change `#expect(loaded.schemaVersion == 1)` to `== 2` and the final text check to `"\"schemaVersion\" : 2"`, and add `#expect(!FileManager.default.fileExists(atPath: store.fileURL.path + ".v7"))`.

Add these tests:

```swift
    @Test func legacySchemaOneFileIsMigratedAndBackedUp() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let legacy = """
        {"schemaVersion":1,"enabled":true,"naturalScrolling":false,
         "gesture":{"longPressDuration":0.9,"tapMaxMovement":12},
         "calibrations":{"X":{"orientation":90}},"launchAtLogin":true}
        """
        try Data(legacy.utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.schemaVersion == 2)
        #expect(s.naturalScrolling == false)
        #expect(s.launchAtLogin == true)
        #expect(s.calibrations["X"]?.orientation == 90)
        let effective = s.effectiveProfile(for: nil)
        #expect(effective.config.longPressDuration == 0.9)
        #expect(effective.config.tapMaxMovement == 12)
        #expect(effective.config.swipeDistance == GestureConfig().swipeDistance)
        #expect(effective.binding(.twoFingerDrag).naturalScrolling == false)
        let backup = store.fileURL.path + ".v1"
        #expect(FileManager.default.fileExists(atPath: backup))
        #expect(try String(contentsOf: URL(fileURLWithPath: backup), encoding: .utf8) == legacy)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(!text.contains("\n  \"naturalScrolling\""))   // no top-level legacy key (top-level keys are indented by two spaces)
        #expect(!text.contains("\n  \"gesture\""))
        #expect(store.load() == s)   // second load is stable
    }

    @Test func fileWithoutSchemaVersionIsTreatedAsLegacy() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{\"enabled\": false, \"naturalScrolling\": false}".utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.enabled == false)
        #expect(s.naturalScrolling == false)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path + ".v1"))
    }

    @Test func duplicateProfilesCollapse() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let json = """
        {"schemaVersion":2,"appProfiles":[
          {"bundleID":"com.apple.Safari","displayName":"Safari","bindings":{},"config":{}},
          {"bundleID":"com.apple.Safari","displayName":"Safari copy","bindings":{},"config":{}},
          {"displayName":"No bundle id","bindings":{},"config":{}}]}
        """
        try Data(json.utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.appProfiles.map(\.displayName) == ["Safari"])
        try store.save(s)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.components(separatedBy: "com.apple.Safari").count == 2)
    }

    @Test func upsertReplacesAndSortsAndRemoveDeletes() {
        var s = Settings()
        s.upsert(GestureProfile(bundleID: "com.b.App", displayName: "Zed"))
        s.upsert(GestureProfile(bundleID: "com.a.App", displayName: "alpha"))
        #expect(s.appProfiles.map(\.displayName) == ["alpha", "Zed"])
        s.upsert(GestureProfile(bundleID: "com.b.App", displayName: "Beta"))
        #expect(s.appProfiles.map(\.displayName) == ["alpha", "Beta"])
        #expect(s.profile(id: "com.a.App")?.displayName == "alpha")
        #expect(s.profile(id: GestureProfile.defaultID) == s.defaultProfile)
        var renamed = s.defaultProfile
        renamed.displayName = "Mine"
        s.upsert(renamed)
        #expect(s.defaultProfile.displayName == "Mine")
        s.removeProfile(bundleID: "com.a.App")
        #expect(s.appProfiles.map(\.id) == ["com.b.App"])
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter SettingsStoreTests`
Expected: compile errors (`defaultProfile`, `upsert` missing).

- [ ] **Step 3: Rewrite Settings.swift**

```swift
import Foundation

public enum DisplaySelection: Codable, Equatable, Sendable {
    case auto
    case display(uuid: String)
}

/// Schema 2: general options plus the default gesture profile and one profile per application.
public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    /// Always the current version; a file's version is not carried over, so a save writes the version that
    /// matches the payload. Schema 1 (`gesture`, `naturalScrolling` at the top level) is migrated in `init(from:)`.
    public var schemaVersion: Int = Settings.currentSchemaVersion
    public var enabled: Bool = true
    public var displaySelection: DisplaySelection = .auto
    /// Keyed by device serial number.
    public var calibrations: [String: Calibration] = [:]
    public var launchAtLogin: Bool = false
    public var defaultProfile: GestureProfile = GestureProfile()
    /// Unique bundle IDs, sorted by display name.
    public var appProfiles: [GestureProfile] = []

    public init() {}

    /// Scroll direction of the default profile's two-finger drag (the menu toggle).
    public var naturalScrolling: Bool {
        get { defaultProfile.bindings[.twoFingerDrag]?.naturalScrolling ?? GestureBinding.builtIn(for: .twoFingerDrag).naturalScrolling ?? true }
        set {
            var binding = defaultProfile.bindings[.twoFingerDrag] ?? .builtIn(for: .twoFingerDrag)
            binding.naturalScrolling = newValue
            defaultProfile.bindings[.twoFingerDrag] = binding
        }
    }

    public func effectiveProfile(for bundleID: String?) -> EffectiveProfile {
        ProfileResolver.effective(for: bundleID, defaultProfile: defaultProfile, appProfiles: appProfiles)
    }

    public func profile(id: String) -> GestureProfile? {
        id == GestureProfile.defaultID ? defaultProfile : appProfiles.first { $0.id == id }
    }

    /// Inserts or replaces by bundle ID (nil replaces the default profile) and keeps the list sorted by name.
    public mutating func upsert(_ profile: GestureProfile) {
        guard let bundleID = profile.bundleID else {
            defaultProfile = profile
            return
        }
        appProfiles.removeAll { $0.bundleID == bundleID }
        appProfiles.append(profile)
        appProfiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public mutating func removeProfile(bundleID: String) {
        appProfiles.removeAll { $0.bundleID == bundleID }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, enabled, displaySelection, calibrations, launchAtLogin, defaultProfile, appProfiles
        case gesture, naturalScrolling   // schema 1 only
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        displaySelection = try c.decodeIfPresent(DisplaySelection.self, forKey: .displaySelection) ?? d.displaySelection
        calibrations = try c.decodeIfPresent([String: Calibration].self, forKey: .calibrations) ?? d.calibrations
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        defaultProfile = try c.decodeIfPresent(GestureProfile.self, forKey: .defaultProfile) ?? d.defaultProfile
        defaultProfile.bundleID = nil
        var seen = Set<String>()
        appProfiles = (try c.decodeIfPresent([GestureProfile].self, forKey: .appProfiles) ?? []).filter { profile in
            guard let bundleID = profile.bundleID else { return false }
            return seen.insert(bundleID).inserted
        }
        // Schema 1: the flat gesture config and the natural-scrolling flag become the default profile.
        if let legacy = try c.decodeIfPresent(GestureConfig.self, forKey: .gesture) {
            defaultProfile.config = GestureConfigOverrides(full: legacy)
        }
        if let legacyNatural = try c.decodeIfPresent(Bool.self, forKey: .naturalScrolling) {
            naturalScrolling = legacyNatural
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(displaySelection, forKey: .displaySelection)
        try c.encode(calibrations, forKey: .calibrations)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(defaultProfile, forKey: .defaultProfile)
        try c.encode(appProfiles, forKey: .appProfiles)
    }
}
```

- [ ] **Step 4: Migrate in SettingsStore.load()**

Replace `load()`:

```swift
    private struct SchemaProbe: Decodable { var schemaVersion: Int? }

    /// Missing file → defaults. Older schema → migrated by `Settings.init(from:)`, the original copied to
    /// `settings.json.v<N>`, the result saved. Unreadable file → set aside as `.broken`, defaults written.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        do {
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            let version = (try? JSONDecoder().decode(SchemaProbe.self, from: data).schemaVersion) ?? 1
            if version < Settings.currentSchemaVersion {
                let backup = URL(fileURLWithPath: fileURL.path + ".v\(version)")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
                try? save(settings)
            }
            return settings
        } catch {
            let broken = URL(fileURLWithPath: fileURL.path + ".broken")
            try? FileManager.default.removeItem(at: broken)
            try? FileManager.default.moveItem(at: fileURL, to: broken)
            let defaults = Settings()
            try? save(defaults)
            return defaults
        }
    }
```

- [ ] **Step 5: Run the TouchCore suite**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter TouchCoreTests` — `swift test` compiles the whole package; the app target no longer compiles because `settings.gesture` and `settings.naturalScrolling` setters are used there. To run the core tests before Task 8, build only the test target's dependencies: `swift build --scratch-path /private/tmp/claude-501/tb-build --target TouchCore` and run `swift test --scratch-path /private/tmp/claude-501/tb-build --filter SettingsStoreTests` — if the package-wide build blocks on the app target, make the minimal compile fix in `Sources/TouchBridge` now: in `DevicePipeline.swift` replace every `settings.gesture` with `settings.effectiveProfile(for: nil).config`, and in `AppState.swift` leave `settings.naturalScrolling` (it is a computed property with a setter, it still compiles). Task 8 replaces these call sites properly.
Expected: SettingsStoreTests 10 pass; full TouchCore suite passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/TouchCore/Settings Sources/TouchBridge/DevicePipeline.swift Tests/TouchCoreTests/SettingsStoreTests.swift
git commit -m "feat(core): settings schema 2 with gesture profiles and migration from schema 1"
```

---

### Task 7: Profile-driven ActionRouter

**Files:**
- Rewrite: `Sources/TouchCore/Routing/ActionRouter.swift`
- Rewrite: `Tests/TouchCoreTests/ActionRouterTests.swift`

**Interfaces:**
- Consumes: `EffectiveProfile`, `GestureBinding`, `GestureAction`, `GestureKind`, `Action`, `Command`.
- Produces: `ActionRouter(profile:)`, `ActionRouter(profile:continuing:)`, `mutating route(_:context:) -> [Command]`, `profile`. Used by Task 8.

- [ ] **Step 1: Write the failing tests** (replace the whole file)

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter ActionRouterTests`
Expected: compile errors (`ActionRouter(profile:)` missing).

- [ ] **Step 3: Rewrite ActionRouter.swift**

```swift
import Foundation
import CoreGraphics

/// Maps engine actions to commands through the effective profile of the frontmost application.
/// Continuous gestures remember the decision made at `began` until their next `began`, so a drag or scroll
/// never switches halfway between pass-through and suppressed — also when the profile changes mid-gesture
/// (`init(profile:continuing:)`).
public struct ActionRouter: Sendable {
    public var profile: EffectiveProfile
    /// Continuous kinds whose last `began` was not passed through. Magnify and rotate are tracked under
    /// `.spread` and `.rotateLeft` respectively, because their direction is only known from `changed` on.
    private(set) var suppressed: Set<GestureKind> = []
    /// Last cursor position seen; mouse clicks bound to swipes happen here.
    private var cursor: CGPoint = .zero

    public init(profile: EffectiveProfile) {
        self.profile = profile
    }

    /// A router for a new profile that keeps the gesture state of `previous`.
    public init(profile: EffectiveProfile, continuing previous: ActionRouter) {
        self.profile = profile
        self.suppressed = previous.suppressed
        self.cursor = previous.cursor
    }

    public mutating func route(_ action: Action, context: RouterContext) -> [Command] {
        switch action {
        case .moveCursor(let p):
            cursor = p
            return [.moveCursor(p)]
        case .click(let button, let p, let count, let source):
            cursor = p
            let kind: GestureKind
            switch source {
            case .tap: kind = count >= 2 ? .doubleTap : .tap
            case .longPress: kind = .press
            case .twoFingerTap: kind = .twoFingerTap
            }
            return discrete(kind, passThrough: [.click(button, p, count)], at: p)
        case .drag(let phase, let p):
            cursor = p
            return continuous(.drag, phase: phase, at: p) { [.drag(phase, p)] }
        case .scroll(let phase, let delta, let p):
            let sign = scrollSign
            return continuous(.twoFingerDrag, phase: phase, at: p) {
                [.scroll(phase, CGVector(dx: delta.dx * sign, dy: delta.dy * sign), p)]
            }
        case .scrollMomentum(let v, let p):
            let binding = profile.binding(.twoFingerDrag)
            guard !suppressed.contains(.twoFingerDrag), binding.enabled, binding.action == .passThrough, binding.momentum ?? true else { return [] }
            let sign = scrollSign
            return [.scrollMomentum(CGVector(dx: v.dx * sign, dy: v.dy * sign), p)]
        case .cancelMomentum:
            return [.cancelMomentum]
        case .magnify(let phase, let delta, let p):
            return twoWay(key: .spread, phase: phase, value: delta, positive: .spread, negative: .pinch) { [.magnify(phase, delta, p)] }
        case .rotate(let phase, let degrees, let p):
            return twoWay(key: .rotateLeft, phase: phase, value: degrees, positive: .rotateLeft, negative: .rotateRight) { [.rotate(phase, degrees, p)] }
        case .swipe(let fingers, let direction):
            guard let kind = GestureKind.swipe(fingers: fingers, direction: direction) else { return [] }
            return discrete(kind, passThrough: [], at: cursor)   // swipes have no native behaviour
        }
    }

    private var scrollSign: Double {
        (profile.binding(.twoFingerDrag).naturalScrolling ?? true) ? 1 : -1
    }

    private func discrete(_ kind: GestureKind, passThrough: [Command], at p: CGPoint) -> [Command] {
        let binding = profile.binding(kind)
        guard binding.enabled else { return [] }
        return commands(for: binding.action, passThrough: passThrough, at: p)
    }

    private func commands(for action: GestureAction, passThrough: [Command], at p: CGPoint) -> [Command] {
        switch action {
        case .none: return []
        case .passThrough: return passThrough
        case .mouseClick(let button, let count): return [.click(button, p, count)]
        case .keystroke(let key): return [.key(key)]
        case .systemAction(let system): return [.key(system.keyCommand)]
        case .openFile(let path): return [.openFile(path)]
        }
    }

    /// `began` decides: pass-through passes every phase, none/disabled drops every phase, a discrete action
    /// fires once and drops the rest.
    private mutating func continuous(_ kind: GestureKind, phase: GesturePhase, at p: CGPoint, passThrough: () -> [Command]) -> [Command] {
        if phase == .began {
            let binding = profile.binding(kind)
            if binding.enabled, binding.action == .passThrough {
                suppressed.remove(kind)
                return passThrough()
            }
            suppressed.insert(kind)
            guard binding.enabled else { return [] }
            return commands(for: binding.action, passThrough: [], at: p)
        }
        return suppressed.contains(kind) ? [] : passThrough()
    }

    /// Magnify and rotate: `began` and `ended` pass when either direction is pass-through; each `changed`
    /// passes only when its own direction is. In Part A only pass-through and none are effective for these kinds.
    private mutating func twoWay(key: GestureKind, phase: GesturePhase, value: Double, positive: GestureKind, negative: GestureKind,
                                 passThrough: () -> [Command]) -> [Command] {
        let pos = profile.binding(positive)
        let neg = profile.binding(negative)
        let positivePasses = pos.enabled && pos.action == .passThrough
        let negativePasses = neg.enabled && neg.action == .passThrough
        switch phase {
        case .began:
            if positivePasses || negativePasses { suppressed.remove(key) } else { suppressed.insert(key) }
            return suppressed.contains(key) ? [] : passThrough()
        case .changed:
            guard !suppressed.contains(key) else { return [] }
            return (value >= 0 ? positivePasses : negativePasses) ? passThrough() : []
        case .ended, .cancelled:
            return suppressed.contains(key) ? [] : passThrough()
        }
    }
}
```

- [ ] **Step 4: Run the router tests and the whole core suite**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build --filter ActionRouterTests`
Expected: 10 tests pass. `DevicePipeline` still constructs `ActionRouter(naturalScrolling:)` — the package build fails until Task 8; if `swift test` refuses to build the test target because of the app target, apply this minimal fix in `Sources/TouchBridge/DevicePipeline.swift` now: replace both `ActionRouter(naturalScrolling: settings.naturalScrolling)` with `ActionRouter(profile: settings.effectiveProfile(for: nil))`. Task 8 finishes the wiring.

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchCore/Routing/ActionRouter.swift Sources/TouchBridge/DevicePipeline.swift Tests/TouchCoreTests/ActionRouterTests.swift
git commit -m "feat(core): route gestures through per-application profiles"
```

---

### Task 8: Frontmost app, per-pipeline profiles, open-file execution

**Files:**
- Create: `Sources/TouchBridge/FrontmostAppObserver.swift`
- Modify: `Sources/TouchBridge/DevicePipeline.swift`, `Sources/TouchBridge/PipelineController.swift`, `Sources/TouchBridge/AppState.swift`

**Interfaces:**
- Consumes: `Settings.effectiveProfile(for:)`, `EffectiveProfile`, `ActionRouter(profile:continuing:)`, `Command.openFile`.
- Produces: `FrontmostAppObserver` (`bundleID`, `onChange`, `start()`, `stop()`), `DevicePipeline.init(id:info:layout:mapping:profile:enabled:)`, `DevicePipeline.apply(profile:enabled:)`, `DevicePipeline.onOpenFile`, `PipelineController.activeProfile`, `PipelineController.onActiveProfile`, `AppState.frontmostBundleID`, `AppState.activeProfileName`. Used by Tasks 9–11.

No unit tests cover the app layer; the gate is a warning-free build, the unchanged TouchCore/TouchInject suites, and a signed bundle.

- [ ] **Step 1: Write FrontmostAppObserver.swift**

```swift
import AppKit

/// Reports the bundle identifier of the frontmost application; nil when macOS reports none.
@MainActor
final class FrontmostAppObserver {
    private(set) var bundleID: String?
    var onChange: ((String?) -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, self.bundleID != id else { return }
                self.bundleID = id
                self.onChange?(id)
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}
```

- [ ] **Step 2: Rework DevicePipeline**

Replace the initializer, remove `updateSettings(_:)`, add `onOpenFile` and `apply(profile:enabled:)`, and route `.openFile` in `run`:

```swift
    var onContacts: (@Sendable ([Contact]) -> Void)?
    /// Called (on the pipeline queue) for `Command.openFile`; the app layer opens the file on the main actor.
    var onOpenFile: (@Sendable (String) -> Void)?
```

```swift
    init(id: DeviceID, info: DeviceInfo, layout: TouchScreenLayout, mapping: MappingConfig, profile: EffectiveProfile, enabled: Bool) {
        self.id = id
        self.info = info
        self.layout = layout
        queue = DispatchQueue(label: "org.touchbridge.pipeline.\(id)", qos: .userInteractive)
        decoder = ReportDecoder(layout: layout)
        mapper = DisplayMapper(config: mapping)
        tracker = TouchTracker(stuckTimeout: UInt64(profile.config.stuckTimeout * 1_000_000_000))
        engine = GestureEngine(config: profile.config)
        router = ActionRouter(profile: profile)
        injector = EventInjector(queue: queue, momentum: MomentumGenerator(
            decayPerFrame: profile.config.momentumDecayPerFrame,
            stopVelocity: profile.config.momentumStopVelocity))
        self.enabled = enabled
    }
```

```swift
    /// Applies the effective profile of the frontmost app and the touch-enabled flag. A running gesture keeps
    /// the routing decision made at its start (`ActionRouter(profile:continuing:)`); new thresholds apply from
    /// the next decision on.
    func apply(profile: EffectiveProfile, enabled: Bool) {
        queue.async {
            self.engine.config = profile.config
            self.router = ActionRouter(profile: profile, continuing: self.router)
            self.tracker.stuckTimeout = UInt64(profile.config.stuckTimeout * 1_000_000_000)
            self.injector.momentum = MomentumGenerator(decayPerFrame: profile.config.momentumDecayPerFrame,
                                                       stopVelocity: profile.config.momentumStopVelocity)
            if self.enabled && !enabled { self.finishGestures() }
            self.enabled = enabled
        }
    }
```

In `run(_:)`:

```swift
    private func run(_ actions: [Action]) {
        guard !actions.isEmpty else { return }
        let context = RouterContext(frontmostBundleID: router.profile.profileID)
        for action in actions {
            logger.debug("action \(String(describing: action), privacy: .public)")
            for command in router.route(action, context: context) {
                if case .openFile(let path) = command {
                    onOpenFile?(path)
                } else {
                    injector.perform(command)
                }
            }
        }
    }
```

- [ ] **Step 3: Wire PipelineController**

Add properties:

```swift
    /// Reports the frontmost bundle ID and the profile that now applies (for the settings window header).
    var onActiveProfile: ((String?, EffectiveProfile) -> Void)?
    private let frontmost = FrontmostAppObserver()
    private static let ownBundleID = Bundle.main.bundleIdentifier ?? "org.touchbridge.TouchBridge"
```

In `start()`, after `displays.startObserving { … }`:

```swift
        frontmost.onChange = { [weak self] _ in self?.applyProfile() }
        frontmost.start()
```

Add:

```swift
    /// The effective profile for the frontmost application. TouchBridge itself and an unknown frontmost app use
    /// the default profile, so configuring never locks the user out.
    var activeProfile: EffectiveProfile {
        let id = frontmost.bundleID
        let lookup = (id == nil || id == Self.ownBundleID) ? nil : id
        return settings.effectiveProfile(for: lookup)
    }

    private func applyProfile() {
        let profile = activeProfile
        for pipeline in registry.all { pipeline.apply(profile: profile, enabled: settings.enabled) }
        onActiveProfile?(frontmost.bundleID, profile)
    }

    private func open(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            logger.error("open file: \(path, privacy: .public) does not exist")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
```

Replace `updateSettings`:

```swift
    func updateSettings(_ settings: Settings) {
        self.settings = settings
        applyProfile()
        remapAll()
    }
```

In `handle(.attached)` construct the pipeline with the profile and wire the file callback:

```swift
                let pipeline = DevicePipeline(id: id, info: info, layout: layout,
                                              mapping: mapping(for: info, layout: layout),
                                              profile: activeProfile, enabled: settings.enabled)
                pipeline.onContacts = { [weak self] contacts in
                    Task { @MainActor in self?.onContacts?(id, contacts) }
                }
                pipeline.onOpenFile = { [weak self] path in
                    Task { @MainActor in self?.open(path) }
                }
```

- [ ] **Step 4: Extend AppState**

Add after `var liveContacts: [Contact] = []`:

```swift
    /// Frontmost application and the gesture profile that applies to it, for the settings window header.
    var frontmostBundleID: String?
    var activeProfileName = "Default"
```

In `startController()` after `controller.onContacts = …`:

```swift
        controller.onActiveProfile = { [weak self] bundleID, profile in
            self?.frontmostBundleID = bundleID
            self?.activeProfileName = profile.profileName
        }
```

`setNaturalScrolling` keeps working unchanged (`settings.naturalScrolling` is now a computed property on the default profile).

- [ ] **Step 5: Build, test, bundle**

Run: `swift build --scratch-path /private/tmp/claude-501/tb-build` (no warnings), `swift test --scratch-path /private/tmp/claude-501/tb-build` (expected 99 + 26 TouchCore/TouchInject tests from Tasks 1–7 all green; exact count printed by the run), `Scripts/build-app.sh debug` (signed bundle, do not open).

- [ ] **Step 6: Commit**

```bash
git add Sources/TouchBridge
git commit -m "feat(app): apply the frontmost application's gesture profile to every pipeline"
```

---

### Task 9: Settings window skeleton, profile sidebar and profile editing API

**Files:**
- Modify: `Sources/TouchBridge/AppState.swift` (profile editing API, `showSettings`)
- Create: `Sources/TouchBridge/Views/Settings/SettingsView.swift`, `Sources/TouchBridge/Views/Settings/ProfileSidebar.swift`, `Sources/TouchBridge/Views/Settings/AppInfo.swift`
- Modify: `Sources/TouchBridge/Views/MenuContent.swift` ("Settings…" replaces "Open settings file")

**Interfaces:**
- Consumes: `Settings.profile(id:)`, `upsert`, `removeProfile`, `GestureProfile`, `GestureBinding.builtIn`, `GestureConfigField`.
- Produces: `AppState.selectedProfileID`, `selectedProfile`, `showSettings()`, `addProfile(appAt:)`, `removeProfile(id:)`, `resolvedBinding(_:in:)`, `setBinding(_:for:in:)`, `resetBinding(for:in:)`, `resolvedConfigValue(_:in:)`, `setConfigValue(_:for:in:)`, `restoreGestures(in:)`, `restoreTuning(in:)`; views `SettingsView`, `ProfileSidebar`, `AdvancedTab`; `AppInfo.describe(bundleID:fallbackName:)`. Tasks 10–11 fill the Gestures and Tuning tabs; this task ships them as placeholders that Task 11 replaces.

- [ ] **Step 1: Add the editing API to AppState**

Add after `activeProfileName`:

```swift
    /// Profile shown in the settings window: `GestureProfile.defaultID` or an app's bundle identifier.
    var selectedProfileID: String = GestureProfile.defaultID

    var selectedProfile: GestureProfile {
        settings.profile(id: selectedProfileID) ?? settings.defaultProfile
    }
```

Add after `showIdentifier()`:

```swift
    func showSettings() {
        Windows.shared.show(SettingsView(state: self), title: "TouchBridge Settings", id: "settings")
    }

    // MARK: - Profile editing (every change is saved and pushed to the pipelines at once)

    /// Adds a profile for the application bundle at `url` (from the open panel) and selects it.
    func addProfile(appAt url: URL) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            lastError = "Not an application bundle: \(url.lastPathComponent)"
            return
        }
        if settings.profile(id: bundleID) == nil {
            let info = bundle.infoDictionary ?? [:]
            let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            settings.upsert(GestureProfile(bundleID: bundleID, displayName: name))
            saveSettings()
        }
        selectedProfileID = bundleID
    }

    func removeProfile(id: String) {
        guard id != GestureProfile.defaultID else { return }
        settings.removeProfile(bundleID: id)
        if selectedProfileID == id { selectedProfileID = GestureProfile.defaultID }
        saveSettings()
    }

    /// The binding shown for `kind` in profile `id`, and whether it is inherited (not set in that profile).
    func resolvedBinding(_ kind: GestureKind, in id: String) -> (binding: GestureBinding, inherited: Bool) {
        if let own = settings.profile(id: id)?.bindings[kind] { return (own, false) }
        if id == GestureProfile.defaultID { return (.builtIn(for: kind), true) }
        return (settings.effectiveProfile(for: nil).binding(kind), true)
    }

    func setBinding(_ binding: GestureBinding, for kind: GestureKind, in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.bindings[kind] = binding
        settings.upsert(profile)
        saveSettings()
    }

    func resetBinding(for kind: GestureKind, in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.bindings[kind] = nil
        settings.upsert(profile)
        saveSettings()
    }

    /// The tuning value shown for `field` in profile `id`, and whether it is inherited.
    func resolvedConfigValue(_ field: GestureConfigField, in id: String) -> (value: Double, inherited: Bool) {
        if let own = settings.profile(id: id)?.config[keyPath: field.override] { return (own, false) }
        let inherited = id == GestureProfile.defaultID ? GestureConfig() : settings.effectiveProfile(for: nil).config
        return (inherited[keyPath: field.value], true)
    }

    /// nil removes the override (the value is inherited again).
    func setConfigValue(_ value: Double?, for field: GestureConfigField, in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.config[keyPath: field.override] = value
        settings.upsert(profile)
        saveSettings()
    }

    func restoreGestures(in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.bindings = [:]
        settings.upsert(profile)
        saveSettings()
    }

    func restoreTuning(in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.config = GestureConfigOverrides()
        settings.upsert(profile)
        saveSettings()
    }
```

- [ ] **Step 2: Write AppInfo.swift**

```swift
import AppKit
import UniformTypeIdentifiers

enum AppInfo {
    /// Icon and name for a profile's application; a generic icon and "(not installed)" when it is missing.
    @MainActor
    static func describe(bundleID: String, fallbackName: String) -> (name: String, icon: NSImage, installed: Bool) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return (fallbackName, NSWorkspace.shared.icon(forFile: url.path), true)
        }
        return (fallbackName + " (not installed)", NSWorkspace.shared.icon(for: .applicationBundle), false)
    }
}
```

- [ ] **Step 3: Write ProfileSidebar.swift**

```swift
import AppKit
import SwiftUI
import TouchCore
import UniformTypeIdentifiers

struct ProfileSidebar: View {
    @Bindable var state: AppState
    @State private var confirmRemove = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $state.selectedProfileID) {
                Label("Default", systemImage: "hand.tap").tag(GestureProfile.defaultID)
                Section("Applications") {
                    ForEach(state.settings.appProfiles) { profile in
                        let info = AppInfo.describe(bundleID: profile.id, fallbackName: profile.displayName)
                        HStack {
                            Image(nsImage: info.icon).resizable().frame(width: 18, height: 18)
                            Text(info.name)
                        }
                        .tag(profile.id)
                    }
                }
            }
            Divider()
            HStack {
                Button { addProfile() } label: { Image(systemName: "plus") }
                    .help("Add a profile for an application in /Applications")
                Button { confirmRemove = true } label: { Image(systemName: "minus") }
                    .disabled(state.selectedProfileID == GestureProfile.defaultID)
                    .help("Remove the selected profile")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .confirmationDialog("Remove the profile \"\(state.selectedProfile.displayName)\"?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { state.removeProfile(id: state.selectedProfileID) }
        } message: {
            Text("The application falls back to the default profile.")
        }
    }

    private func addProfile() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the application this profile applies to"
        if panel.runModal() == .OK, let url = panel.url {
            state.addProfile(appAt: url)
        }
    }
}
```

- [ ] **Step 4: Write SettingsView.swift (with placeholder tabs)**

```swift
import SwiftUI
import TouchCore

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationSplitView {
            ProfileSidebar(state: state)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                TabView {
                    GesturesTab(state: state, profileID: state.selectedProfileID)
                        .tabItem { Text("Gestures") }
                    TuningTab(state: state, profileID: state.selectedProfileID)
                        .tabItem { Text("Tuning") }
                    AdvancedTab(state: state)
                        .tabItem { Text("Advanced") }
                }
                .padding()
            }
        }
        .frame(minWidth: 960, minHeight: 600)
    }

    private var header: some View {
        HStack {
            Text(state.selectedProfile.displayName).font(.title2)
            Spacer()
            Text("Frontmost: \(state.frontmostBundleID ?? "—")  ·  active profile: \(state.activeProfileName)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
    }
}

// Replaced in Task 11.
struct GesturesTab: View {
    @Bindable var state: AppState
    let profileID: String
    var body: some View { Text("Gestures for \(profileID)") }
}

// Replaced in Task 11.
struct TuningTab: View {
    @Bindable var state: AppState
    let profileID: String
    var body: some View { Text("Tuning for \(profileID)") }
}

struct AdvancedTab: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Button("Open settings file") { state.openSettingsFile() }
            Text("~/Library/Application Support/TouchBridge/settings.json. Edits made outside TouchBridge take effect after a restart.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 5: Menu entry**

In `MenuContent.swift` replace `Button("Open settings file") { state.openSettingsFile() }` with `Button("Settings…") { state.showSettings() }`.

- [ ] **Step 6: Build, bundle, commit**

Run: `swift build --scratch-path /private/tmp/claude-501/tb-build` (no warnings), `swift test --scratch-path /private/tmp/claude-501/tb-build` (unchanged), `Scripts/build-app.sh debug`.

```bash
git add Sources/TouchBridge
git commit -m "feat(app): settings window with profile sidebar and profile editing API"
```

---

### Task 10: Shortcut recorder and key names

**Files:**
- Create: `Sources/TouchBridge/Views/Settings/ShortcutRecorder.swift`

**Interfaces:**
- Consumes: `KeyCommand`.
- Produces: `KeyNames.display(_ key: KeyCommand) -> String`, `KeyNames.name(forKeyCode:)`, `RecorderResult`, `ShortcutRecorder` (`NSViewRepresentable`), `ShortcutRecorderSheet(current:onDone:)`. Used by Task 11.

- [ ] **Step 1: Write ShortcutRecorder.swift**

```swift
import AppKit
import Carbon.HIToolbox
import SwiftUI
import TouchCore

/// Human-readable key combinations, e.g. "⌘[" or "⌃↑", using the current keyboard layout for letters.
enum KeyNames {
    static func display(_ key: KeyCommand) -> String {
        var text = ""
        if key.control { text += "⌃" }
        if key.option { text += "⌥" }
        if key.shift { text += "⇧" }
        if key.command { text += "⌘" }
        return text + name(forKeyCode: key.keyCode)
    }

    static func name(forKeyCode code: UInt16) -> String {
        if let special = specialNames[code] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "key \(code)"
        }
        let layoutData = unsafeBitCast(layoutPointer, to: CFData.self) as Data
        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { bytes -> OSStatus in
            UCKeyTranslate(bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                           code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "key \(code)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static let specialNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

enum RecorderResult {
    case recorded(KeyCommand)
    case cleared
    case cancelled
}

/// Captures the next key combination. Escape cancels, Delete clears.
final class RecorderNSView: NSView {
    var current: KeyCommand? { didSet { needsDisplay = true } }
    var onResult: ((RecorderResult) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onResult?(.cancelled)
        case 51, 117:
            current = nil
            onResult?(.cleared)
        default:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = KeyCommand(keyCode: event.keyCode,
                                 control: flags.contains(.control), option: flags.contains(.option),
                                 shift: flags.contains(.shift), command: flags.contains(.command))
            current = key
            onResult?(.recorded(key))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        let text = current.map(KeyNames.display) ?? "Press keys…"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: current == nil ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let current: KeyCommand?
    let onResult: (RecorderResult) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.current = current
        view.onResult = onResult
        return view
    }

    func updateNSView(_ view: RecorderNSView, context: Context) {
        view.onResult = onResult
    }
}

/// Sheet: record a shortcut, warn when it has no modifier, confirm with "Use". `onDone(nil)` = cancelled.
struct ShortcutRecorderSheet: View {
    let current: KeyCommand?
    let onDone: (KeyCommand?) -> Void
    @State private var recorded: KeyCommand?
    @State private var warning: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("Press the keyboard shortcut").font(.headline)
            ShortcutRecorder(current: current) { result in
                switch result {
                case .recorded(let key):
                    recorded = key
                    warning = (key.control || key.option || key.shift || key.command) ? nil
                        : "A shortcut without a modifier key types that key into the frontmost app."
                case .cleared:
                    recorded = nil
                    warning = nil
                case .cancelled:
                    onDone(nil)
                }
            }
            .frame(width: 260, height: 44)
            Text(warning ?? "Escape cancels, Delete clears.").font(.footnote).foregroundStyle(warning == nil ? .secondary : .orange)
            HStack {
                Button("Cancel") { onDone(nil) }
                Button("Use") { onDone(recorded) }.disabled(recorded == nil)
            }
        }
        .padding(20)
        .onAppear { recorded = current }
    }
}
```

The buttons carry no `keyboardShortcut` modifiers on purpose: Return and Escape must reach the recorder.

- [ ] **Step 2: Build**

Run: `swift build --scratch-path /private/tmp/claude-501/tb-build`
Expected: no warnings. If `TISCopyCurrentKeyboardLayoutInputSource()` is imported as a managed `TISInputSource!` rather than `Unmanaged`, drop `?.takeRetainedValue()`. If `UCKeyTranslate`'s option parameter type differs, cast with `UInt32(kUCKeyTranslateNoDeadKeysBit)`.

- [ ] **Step 3: Commit**

```bash
git add Sources/TouchBridge/Views/Settings/ShortcutRecorder.swift
git commit -m "feat(app): keyboard shortcut recorder with layout-aware key names"
```

---

### Task 11: Gestures tab and Tuning tab

**Files:**
- Create: `Sources/TouchBridge/Views/Settings/GesturesTab.swift`, `Sources/TouchBridge/Views/Settings/TuningTab.swift`
- Modify: `Sources/TouchBridge/Views/Settings/SettingsView.swift` (delete the two placeholder structs)

**Interfaces:**
- Consumes: the `AppState` editing API (Task 9), `KeyNames`, `ShortcutRecorderSheet` (Task 10), `GestureKind`, `FingerGroup`, `GestureBinding`, `GestureAction`, `MouseButton`, `SystemAction`, `GestureConfigField`.
- Produces: `GesturesTab`, `GestureRow`, `ActionMenu`, `TuningTab`, `TuningRow`.

- [ ] **Step 1: Write GesturesTab.swift**

```swift
import AppKit
import SwiftUI
import TouchCore

struct GesturesTab: View {
    @Bindable var state: AppState
    let profileID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(FingerGroup.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(GestureKind.allCases.filter { $0.group == group }, id: \.self) { kind in
                            GestureRow(state: state, profileID: profileID, kind: kind)
                        }
                    }
                }
            }
            HStack {
                if profileID != GestureProfile.defaultID {
                    Text("Grey “Default” rows inherit from the default profile.").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore defaults") { state.restoreGestures(in: profileID) }
            }
        }
    }
}

struct GestureRow: View {
    @Bindable var state: AppState
    let profileID: String
    let kind: GestureKind
    @State private var recordingShortcut = false

    var body: some View {
        let resolved = state.resolvedBinding(kind, in: profileID)
        let binding = resolved.binding
        HStack(spacing: 12) {
            Text(kind.displayName).frame(width: 240, alignment: .leading)
            Toggle("", isOn: Binding(get: { binding.enabled }, set: { value in store(binding) { $0.enabled = value } }))
                .labelsHidden()
                .help("Enabled")
            ActionMenu(kind: kind, action: binding.action,
                       onChoose: { action in store(binding) { $0.action = action } },
                       onRecordShortcut: { recordingShortcut = true })
                .frame(width: 230, alignment: .leading)
            if case .openFile(let path) = binding.action, !FileManager.default.fileExists(atPath: path) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help("File not found: \(path)")
            }
            if kind == .twoFingerDrag {
                Toggle("Natural scrolling", isOn: Binding(get: { binding.naturalScrolling ?? true }, set: { value in store(binding) { $0.naturalScrolling = value } }))
                Toggle("Momentum", isOn: Binding(get: { binding.momentum ?? true }, set: { value in store(binding) { $0.momentum = value } }))
            }
            Spacer()
            if profileID != GestureProfile.defaultID {
                Text(resolved.inherited ? "Default" : "Custom").font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(!kind.isRecognized)
        .help(kind.isRecognized ? "" : "Not recognized yet")
        .contextMenu {
            if !resolved.inherited, profileID != GestureProfile.defaultID {
                Button("Reset to default") { state.resetBinding(for: kind, in: profileID) }
            }
        }
        .sheet(isPresented: $recordingShortcut) {
            ShortcutRecorderSheet(current: currentKey(binding.action)) { key in
                if let key { store(binding) { $0.action = .keystroke(key: key) } }
                recordingShortcut = false
            }
        }
    }

    /// Copies `binding`, applies `change` and stores the result in the selected profile.
    private func store(_ binding: GestureBinding, _ change: (inout GestureBinding) -> Void) {
        var copy = binding
        change(&copy)
        state.setBinding(copy, for: kind, in: profileID)
    }

    private func currentKey(_ action: GestureAction) -> KeyCommand? {
        if case .keystroke(let key) = action { return key }
        return nil
    }
}

struct ActionMenu: View {
    let kind: GestureKind
    let action: GestureAction
    let onChoose: (GestureAction) -> Void
    let onRecordShortcut: () -> Void

    /// Pinch, spread and rotate only pass through or are off in this version; discrete actions come with Part C.
    private var discreteAllowed: Bool {
        ![GestureKind.pinch, .spread, .rotateLeft, .rotateRight].contains(kind)
    }

    var body: some View {
        Menu {
            Button("Pass through") { onChoose(.passThrough) }
            Button("None") { onChoose(.none) }
            Divider()
            Menu("Mouse click") {
                ForEach(MouseButton.allCases, id: \.self) { button in
                    Menu(button.displayName) {
                        Button("Single click") { onChoose(.mouseClick(button: button, count: 1)) }
                        Button("Double click") { onChoose(.mouseClick(button: button, count: 2)) }
                        Button("Triple click") { onChoose(.mouseClick(button: button, count: 3)) }
                    }
                }
            }
            .disabled(!discreteAllowed)
            Button("Keyboard shortcut…") { onRecordShortcut() }.disabled(!discreteAllowed)
            Menu("System") {
                ForEach(SystemAction.allCases, id: \.self) { system in
                    Button(system.displayName) { onChoose(.systemAction(action: system)) }
                }
            }
            .disabled(!discreteAllowed)
            Button("Open file…") { chooseFile() }.disabled(!discreteAllowed)
            if !discreteAllowed {
                Divider()
                Text("Other actions for this gesture come in a later version")
            }
        } label: {
            Text(Self.title(for: action))
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a file or application to open"
        if panel.runModal() == .OK, let url = panel.url {
            onChoose(.openFile(path: url.path))
        }
    }

    static func title(for action: GestureAction) -> String {
        switch action {
        case .none: return "None"
        case .passThrough: return "Pass through"
        case .mouseClick(let button, let count): return "\(button.displayName) click" + (count > 1 ? " ×\(count)" : "")
        case .keystroke(let key): return KeyNames.display(key)
        case .systemAction(let system): return system.displayName
        case .openFile(let path): return "Open " + URL(fileURLWithPath: path).lastPathComponent
        }
    }
}
```

- [ ] **Step 2: Write TuningTab.swift**

```swift
import SwiftUI
import TouchCore

struct TuningTab: View {
    @Bindable var state: AppState
    let profileID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Form {
                ForEach(GestureConfigField.all) { field in
                    TuningRow(state: state, profileID: profileID, field: field)
                }
            }
            .formStyle(.grouped)
            HStack {
                if profileID != GestureProfile.defaultID {
                    Text("Tick “Override” to give this application its own value.").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore defaults") { state.restoreTuning(in: profileID) }
            }
        }
    }
}

struct TuningRow: View {
    @Bindable var state: AppState
    let profileID: String
    let field: GestureConfigField

    private var isDefaultProfile: Bool { profileID == GestureProfile.defaultID }

    var body: some View {
        let resolved = state.resolvedConfigValue(field, in: profileID)
        let editable = isDefaultProfile || !resolved.inherited
        let value = Binding(get: { resolved.value }, set: { state.setConfigValue($0, for: field, in: profileID) })
        HStack(spacing: 12) {
            if !isDefaultProfile {
                Toggle("Override", isOn: Binding(get: { !resolved.inherited },
                                                set: { on in state.setConfigValue(on ? resolved.value : nil, for: field, in: profileID) }))
                    .labelsHidden()
                    .help("Override the inherited value")
            }
            Text(field.label).frame(width: 260, alignment: .leading)
            TextField("", value: value, format: .number.precision(.fractionLength(0...3)))
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
                .disabled(!editable)
            Stepper("", value: value, step: field.step).labelsHidden().disabled(!editable)
            Text(field.unit).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            Spacer()
            Text("Default \(GestureConfig()[keyPath: field.value].formatted(.number.precision(.fractionLength(0...3))))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Remove the placeholders**

Delete the two `// Replaced in Task 11.` structs (`GesturesTab`, `TuningTab`) from `SettingsView.swift`.

- [ ] **Step 4: Build, test, bundle**

Run: `swift build --scratch-path /private/tmp/claude-501/tb-build` (no warnings), `swift test --scratch-path /private/tmp/claude-501/tb-build` (unchanged), `Scripts/build-app.sh debug`. Do not open the app.

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchBridge/Views/Settings
git commit -m "feat(app): gestures and tuning tabs with per-profile overrides"
```

---

### Task 12: Documentation and acceptance checklist

**Files:**
- Modify: `README.md`, `CLAUDE.md`, `docs/notes/follow-ups.md`

- [ ] **Step 1: README**

Replace the "Settings" section with:

```markdown
## Settings

Open "Settings…" from the menu bar icon. The sidebar lists the **Default** profile and one profile per application (add one with "+", choosing the app in /Applications). The profile of the frontmost application applies; TouchBridge itself and apps without a profile use Default.

- **Gestures**: every gesture has an on/off switch and an action: pass through (the built-in behaviour), none, a mouse click (left, right, middle, back, forward; single to triple), a keyboard shortcut (recorded by pressing it), a system action (Mission Control, App Exposé, Space left/right, Show desktop) or a file/application to open. Two-finger drag additionally has natural scrolling and momentum switches. Rows marked "Default" in an application profile inherit from the default profile; "Reset to default" in the context menu removes an override. Greyed-out gestures are not recognized yet (they come with later versions).
- **Tuning**: all engine thresholds and durations (tap and double-tap timing, long-press duration, scroll classification, pinch and rotate thresholds, momentum, swipe distance and duration, stuck-contact timeout). In an application profile, tick "Override" to give the app its own value.
- **Advanced**: opens `~/Library/Application Support/TouchBridge/settings.json` (schema 2). The file holds `enabled`, `displaySelection` (`{"auto":{}}` or `{"display":{"uuid":"…"}}`), `calibrations` (per device serial: `orientation` 0/90/180/270, `scaleX`, `scaleY`, `offsetX`, `offsetY`), `launchAtLogin`, `defaultProfile` and `appProfiles` (each with `bundleID`, `displayName`, `bindings` keyed by gesture name, `config` overrides). A schema-1 file from an earlier version is migrated on launch and kept as `settings.json.v1`.
```

Add to "Troubleshooting":

```markdown
- A gesture does nothing in one app only: open Settings… and check that app's profile; "Restore defaults" resets it. The header shows which profile is active for the frontmost app.
- A shortcut without a modifier (e.g. "A") types into the frontmost app; use ⌘/⌥/⌃ combinations.
```

- [ ] **Step 2: CLAUDE.md**

Append:

```markdown
- Gesture profiles (spec docs/superpowers/specs/2026-10-21-touchbridge-profiles-settings-design.md, Part A): GestureKind catalogue (raw values are JSON keys, never rename), GestureAction/GestureBinding, GestureProfile with GestureConfigOverrides, ProfileResolver (built-in ⟵ default ⟵ app), ActionRouter(profile:). Settings schema 2; schema 1 migrates on load (backup .v1). Settings window in Sources/TouchBridge/Views/Settings. Parts B (multi-finger taps/drags) and C (edge swipes, squeeze/splay, discrete pinch/rotate) are not started.
```

- [ ] **Step 3: follow-ups.md**

Add a section "Part A acceptance (needs the panel)" with this checklist and mark Parts B and C as next:

```markdown
## Part A acceptance (needs the panel)

1. Launch: the old settings.json is migrated; `settings.json.v1` sits next to it; natural scrolling and tuning from before still apply.
2. Settings… → "+" → Safari. Gestures: set "Three finger swipe left" to the keyboard shortcut ⌘[. In Safari a three-finger swipe left goes back; in Finder it still switches Spaces. The header shows "active profile: Safari" while Safari is frontmost.
3. Tuning in the Safari profile: tick Override on "Long press duration", set 1.0. A long press opens the context menu later in Safari, unchanged in Finder.
4. Set "Two finger tap" to Mouse click → Middle in the Safari profile: a two-finger tap on a link opens it in a new tab.
5. Default profile: switch "Natural scrolling" off in the Gestures row of "Two finger drag"; the menu toggle follows, and scrolling inverts everywhere without a profile.
6. Remove the Safari profile ("−", confirm): Safari uses the default profile again.
7. Quit and relaunch: all settings persist; `log stream --predicate 'subsystem == "org.touchbridge"'` shows no errors.
```

- [ ] **Step 4: Full verification and commit**

Run: `swift test --scratch-path /private/tmp/claude-501/tb-build` (all green) and `Scripts/build-app.sh release` (signed bundle).

```bash
git add README.md CLAUDE.md docs/notes/follow-ups.md
git commit -m "docs: settings window, gesture profiles and part A acceptance checklist"
```

