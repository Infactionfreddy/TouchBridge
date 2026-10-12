# TouchBridge M1+M2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A signed macOS menu-bar app that seizes a USB HID multitouch screen, interprets up to 10 contacts itself, and injects mouse events and trackpad gestures (scroll with momentum, pinch, rotate, 3/4-finger swipes) system-wide.

**Architecture:** One user-session process. A Swift package with three libraries (TouchCore: pure, deterministic parsing/tracking/gesture logic; TouchDevice: IOKit HID access; TouchInject: CGEvent synthesis) plus a SwiftUI executable and a `hidrecord` CLI. Pipeline per device on one serial queue: report → decode → map → track → gesture → route → inject.

**Tech Stack:** Swift 6 language mode, Swift Package Manager (no .xcodeproj), Swift Testing (`import Testing`), SwiftUI `MenuBarExtra`, IOKit HID (`IOHIDManager`), CoreGraphics `CGEvent`, `ServiceManagement` (`SMAppService`), `os.Logger`.

**Spec:** `docs/superpowers/specs/2026-10-12-touchbridge-design.md`

## Global Constraints

- Swift tools version 6.0, language mode 6; every type in TouchCore is `Sendable`; no global mutable state.
- Minimum macOS 14; built and run on macOS 26.6.2 / Xcode 27 / Swift 6.4.
- SPM only. Xcode opens `Package.swift` directly. No `.xcodeproj` is committed.
- TouchCore has no AppKit, IOKit or CoreGraphics-event dependency; it may import `Foundation` and use `CGPoint`/`CGRect`/`CGVector` from CoreGraphics geometry only.
- TouchCore never reads system clocks. All time comes from `timestamp` parameters (nanoseconds, monotonic, `UInt64`).
- Device matching is by HID usage only: Primary Usage Page `0x0D`, Primary Usage `0x04`. No vendor/product ID lists.
- Undocumented CGEvent field numbers live only in `Sources/TouchInject/GestureEventFields.swift`, each with a source comment.
- Bundle identifier `org.touchbridge.TouchBridge`; signing identity for dev builds `Apple Development: Frederic Garsolke (LLLQH7PQW7)`.
- Logging: `os.Logger` with subsystem `org.touchbridge`, categories `device`, `pipeline`, `inject`, `permissions`. Raw coordinates only at `.debug`.
- Settings file: `~/Library/Application Support/TouchBridge/settings.json`, `schemaVersion` 1.
- Gesture defaults (spec 5.6): tapMaxDuration 0.25 s, tapMaxMovement 8 pt, doubleTapInterval 0.30 s, longPressDuration 0.60 s, classifyMovement 10 pt, pinchThreshold 12 pt, rotateThreshold 8°, momentumMinVelocity 50 pt/s, momentumDecayPerFrame 0.96 @ 60 Hz, momentumStopVelocity 20 pt/s, swipeDistance 60 pt, swipeMaxDuration 0.5 s, stuckTimeout 0.5 s.
- License MIT. Commit messages: conventional prefixes (`feat:`, `test:`, `chore:`, `docs:`), no attribution trailers.
- Language: code, comments, README in English. The spec is German; identifiers follow the spec's names.

## Review Focus

Inputs the spec implies but did not list; each has a pinned test in the owning task:

1. **Contact ID reused in the very next frame** (finger lifts with id 3, a new finger immediately gets id 3): the tracker must emit `ended` then `began`; the engine must not turn the position jump into a drag. → Task 6 (`TouchTrackerTests.reusedIDIsNewTouch`) and Task 7 (`GestureEngineOneFingerTests.reusedIDAfterLiftStartsFreshTap`).
2. **Hybrid report whose continuation never arrives** (count = 12 with 10 slots, then a fresh count = 1 report): the decoder must drop the stale pending contacts and emit the new frame. → Task 4 (`ReportDecoderTests.staleHybridPendingIsDiscardedByNewCount`).
3. **Coordinates outside the logical range** (after calibration offset or a device reporting x > logicalMax): the mapped point must be clamped to the display frame. → Task 5 (`DisplayMapperTests.clampsOutsideRange`).
4. **Two-finger tap with staggered landing and lifting** (second finger lands 40 ms after the first, first lifts 30 ms before the second): still one right click, never a left click. → Task 8 (`GestureEngineTwoFingerTests.staggeredTwoFingerTapIsRightClick`).
5. **Non-monotonic or duplicate timestamps** (two frames with the same timestamp, or a frame earlier than the previous): no division by zero, no negative durations, velocity keeps the previous value. → Task 8 (`GestureEngineTwoFingerTests.duplicateTimestampKeepsVelocity`) and Task 6 (`TouchTrackerTests.olderTimestampDoesNotExpireTouch`).

---

## File Structure

```
TouchBridge/
  Package.swift
  LICENSE                                   MIT
  README.md
  CLAUDE.md                                 project guide for future sessions
  App/Info.plist                            bundle metadata, LSUIElement
  Scripts/build-app.sh                      swift build → dist/TouchBridge.app, codesign
  Scripts/install.sh                        copy to ~/Applications, register login item
  Sources/TouchCore/HID/HIDUsage.swift          usage constants
  Sources/TouchCore/HID/HIDDescriptor.swift     HIDField/HIDDescriptor types + HIDDescriptorParser
  Sources/TouchCore/HID/TouchScreenLayout.swift finger slots, contact count field, report ID
  Sources/TouchCore/HID/ReportDecoder.swift     RawContact, TouchFrame, bit extraction, hybrid merge
  Sources/TouchCore/Mapping/DisplayMapper.swift Calibration, MappingConfig, Contact, ScreenFrame, mapper
  Sources/TouchCore/Touch/TouchTracker.swift    ActiveTouch, TouchEvent, lifecycle + stuck timeout
  Sources/TouchCore/Gesture/Action.swift        GesturePhase, MouseButton, SwipeDirection, Action
  Sources/TouchCore/Gesture/GestureConfig.swift thresholds, Codable with defaults
  Sources/TouchCore/Gesture/Geometry.swift      centroid, distance, angle helpers
  Sources/TouchCore/Gesture/GestureEngine.swift state machine
  Sources/TouchCore/Routing/Command.swift       KeyCommand, Command, RouterContext
  Sources/TouchCore/Routing/ActionRouter.swift  default set, natural scrolling, swipe → keys
  Sources/TouchCore/Settings/Settings.swift     Settings, DisplaySelection
  Sources/TouchCore/Settings/SettingsStore.swift load/save/.broken handling
  Sources/TouchDevice/DeviceEvent.swift         DeviceID, DeviceInfo, DeviceOpenMode, DeviceEvent
  Sources/TouchDevice/DeviceManager.swift       IOHIDManager thread, seize, report callbacks
  Sources/TouchInject/GestureEventFields.swift  the only file with private field numbers
  Sources/TouchInject/MomentumGenerator.swift   pure momentum frame sequence
  Sources/TouchInject/EventInjector.swift       Command → CGEvent, momentum timer, releaseAll
  Sources/hidrecord/main.swift                  CLI recorder / seize spike
  Sources/TouchBridge/TouchBridgeApp.swift      @main, MenuBarExtra, windows, AppDelegate
  Sources/TouchBridge/AppState.swift            @MainActor observable status + settings
  Sources/TouchBridge/PermissionCoordinator.swift
  Sources/TouchBridge/DisplayResolver.swift     display selection, frames, reconfiguration
  Sources/TouchBridge/DevicePipeline.swift      per-device queue, tick timer, wiring
  Sources/TouchBridge/PipelineController.swift  owns DeviceManager, pipelines, wake handling
  Sources/TouchBridge/Views/MenuContent.swift
  Sources/TouchBridge/Views/PermissionsView.swift
  Sources/TouchBridge/Views/GestureIdentifierView.swift  EventProbeView + live contacts
  Tests/TouchCoreTests/Fixtures/elan-report-descriptor.hex
  Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl    recorded in Task 12
  Tests/TouchCoreTests/Support/Fixtures.swift            fixture loading
  Tests/TouchCoreTests/Support/ElanReport.swift          payload builder
  Tests/TouchCoreTests/Support/TouchBuilders.swift       ActiveTouch/time helpers
  Tests/TouchCoreTests/*Tests.swift                      one file per component
  Tests/TouchInjectTests/MomentumGeneratorTests.swift
  Tests/TouchInjectTests/EventBuilderTests.swift
```

Test commands used throughout: `swift build` (all targets), `swift test` (all), `swift test --filter <SuiteName>` (one suite; Swift Testing matches suite and test names by regex).

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`, `LICENSE`, `README.md`, `CLAUDE.md`
- Create: `Sources/TouchCore/HID/HIDUsage.swift`, `Sources/TouchDevice/DeviceEvent.swift` (placeholder content replaced in Task 12), `Sources/TouchInject/GestureEventFields.swift` (placeholder replaced in Task 13), `Sources/TouchBridge/TouchBridgeApp.swift` (placeholder replaced in Task 14), `Sources/hidrecord/main.swift` (placeholder replaced in Task 12)
- Create: `Tests/TouchCoreTests/Fixtures/elan-report-descriptor.hex`, `Tests/TouchCoreTests/Support/Fixtures.swift`, `Tests/TouchCoreTests/FixtureTests.swift`, `Tests/TouchInjectTests/SmokeTests.swift`

**Interfaces:**
- Produces: `HIDUsage` (page/id constants used by Tasks 2–4), `Fixtures.elanDescriptorBytes()` (Tasks 2–4, 12).

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TouchBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TouchCore", targets: ["TouchCore"]),
        .library(name: "TouchDevice", targets: ["TouchDevice"]),
        .library(name: "TouchInject", targets: ["TouchInject"]),
        .executable(name: "TouchBridge", targets: ["TouchBridge"]),
        .executable(name: "hidrecord", targets: ["hidrecord"]),
    ],
    targets: [
        .target(name: "TouchCore"),
        .target(name: "TouchDevice", dependencies: ["TouchCore"]),
        .target(name: "TouchInject", dependencies: ["TouchCore"]),
        .executableTarget(
            name: "TouchBridge",
            dependencies: ["TouchCore", "TouchDevice", "TouchInject"]
        ),
        .executableTarget(name: "hidrecord", dependencies: ["TouchCore", "TouchDevice"]),
        .testTarget(
            name: "TouchCoreTests",
            dependencies: ["TouchCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "TouchInjectTests", dependencies: ["TouchInject"]),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Write HIDUsage.swift**

```swift
import Foundation

/// A HID usage: usage page plus usage ID (USB HID Usage Tables).
public struct HIDUsage: Hashable, Sendable {
    public var page: UInt16
    public var id: UInt16

    public init(page: UInt16, id: UInt16) {
        self.page = page
        self.id = id
    }

    public static let genericDesktopPage: UInt16 = 0x01
    public static let digitizerPage: UInt16 = 0x0D

    public static let x = HIDUsage(page: 0x01, id: 0x30)
    public static let y = HIDUsage(page: 0x01, id: 0x31)

    public static let touchScreen = HIDUsage(page: 0x0D, id: 0x04)
    public static let finger = HIDUsage(page: 0x0D, id: 0x22)
    public static let inRange = HIDUsage(page: 0x0D, id: 0x32)
    public static let tipSwitch = HIDUsage(page: 0x0D, id: 0x42)
    public static let confidence = HIDUsage(page: 0x0D, id: 0x47)
    public static let contactIdentifier = HIDUsage(page: 0x0D, id: 0x51)
    public static let contactCount = HIDUsage(page: 0x0D, id: 0x54)
    public static let contactCountMaximum = HIDUsage(page: 0x0D, id: 0x55)
    public static let scanTime = HIDUsage(page: 0x0D, id: 0x56)
}
```

- [ ] **Step 3: Write placeholders so every target compiles**

`Sources/TouchDevice/DeviceEvent.swift`:
```swift
import Foundation
import TouchCore

/// Replaced with the real definitions in Task 12.
public enum TouchDevicePlaceholder {}
```

`Sources/TouchInject/GestureEventFields.swift`:
```swift
import Foundation
import TouchCore

/// Replaced with the real definitions in Task 13.
public enum TouchInjectPlaceholder {}
```

`Sources/TouchBridge/TouchBridgeApp.swift`:
```swift
import Foundation

// Replaced with the SwiftUI app in Task 14.
print("TouchBridge placeholder")
```
Note: an executable target may use top-level code only in `main.swift`. Name this placeholder file `main.swift` for now and rename it in Task 14.

`Sources/hidrecord/main.swift`:
```swift
import Foundation

// Replaced with the recorder in Task 12.
print("hidrecord placeholder")
```

- [ ] **Step 4: Write the descriptor fixture**

`Tests/TouchCoreTests/Fixtures/elan-report-descriptor.hex` (one line, no spaces; this is the Elan descriptor from the spec's Appendix A, the ten finger collections concatenated):

```
050d0904a10185010922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0050d09565500650027ffffff7f9501752081020954257f95017508810285020955250ab1020600ff09c58503150026ff007508960001b102c00600ff0901a10185090901150026ff00953f750881020901150026ff00950475089102c005010902a10185070901a100050919012903150025017501950381027501950581030501093075109501550e6511350046790826a00b81020931468a03269006810209381581257f750895018106c0c0
```

- [ ] **Step 5: Write fixture loader and a smoke test**

`Tests/TouchCoreTests/Support/Fixtures.swift`:
```swift
import Foundation

enum Fixtures {
    static func url(_ name: String, _ ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureError.missing("\(name).\(ext)")
        }
        return url
    }

    static func elanDescriptorBytes() throws -> [UInt8] {
        let text = try String(contentsOf: url("elan-report-descriptor", "hex"), encoding: .utf8)
        return try hexBytes(text)
    }

    static func hexBytes(_ text: String) throws -> [UInt8] {
        let clean = text.filter { !$0.isWhitespace }
        guard clean.count % 2 == 0 else { throw FixtureError.oddHexLength }
        var out: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { throw FixtureError.badHex(String(clean[index..<next])) }
            out.append(byte)
            index = next
        }
        return out
    }

    enum FixtureError: Error { case missing(String), oddHexLength, badHex(String) }
}
```

`Tests/TouchCoreTests/FixtureTests.swift`:
```swift
import Testing
@testable import TouchCore

@Suite struct FixtureTests {
    @Test func elanDescriptorLoads() throws {
        let bytes = try Fixtures.elanDescriptorBytes()
        #expect(bytes.count == 586)
        #expect(bytes.first == 0x05)
        #expect(bytes.last == 0xC0)
    }
}
```
(586 = length of the hex string / 2. If the count differs after pasting, recount the fixture rather than changing the test: `wc -c` of the file minus trailing newline, divided by 2.)

`Tests/TouchInjectTests/SmokeTests.swift`:
```swift
import Testing
@testable import TouchInject

@Suite struct SmokeTests {
    @Test func moduleLinks() {
        _ = TouchInjectPlaceholder.self
    }
}
```

- [ ] **Step 6: Write LICENSE, README.md, CLAUDE.md**

`LICENSE`: the MIT license text with `Copyright (c) 2026 Frederic Garsolke`.

`README.md`:
```markdown
# TouchBridge

Multitouch for USB touch screens on macOS. TouchBridge takes exclusive control of a HID touch screen, tracks all contacts itself and injects mouse events and trackpad gestures (scroll with momentum, pinch, rotate, 3/4-finger swipes) system-wide.

Status: milestone 1 and 2 in development. See `docs/superpowers/specs/` for the design.

## Build

```
swift build
swift test
Scripts/build-app.sh        # → dist/TouchBridge.app (signed)
Scripts/install.sh          # → ~/Applications/TouchBridge.app
```

## Permissions

TouchBridge needs **Input Monitoring** (to open the touch screen exclusively) and **Accessibility** (to post events). The app asks for both on first launch.

## License

MIT
```

`CLAUDE.md`:
```markdown
# TouchBridge

macOS menu-bar app: exclusive HID access to a USB multitouch screen, own gesture engine, CGEvent injection.

- Spec: docs/superpowers/specs/2026-10-12-touchbridge-design.md (German)
- Plan: docs/superpowers/plans/2026-10-12-touchbridge-m1-m2.md
- Build: `swift build`; tests: `swift test`; app bundle: `Scripts/build-app.sh`; install: `Scripts/install.sh`
- Modules: TouchCore (pure logic, deterministic, Sendable, no system clocks), TouchDevice (IOKit), TouchInject (CGEvent), TouchBridge (SwiftUI app), hidrecord (CLI recorder)
- Undocumented CGEvent fields only in Sources/TouchInject/GestureEventFields.swift
- Device matching by HID usage page 0x0D / usage 0x04 only, never by vendor ID
- Tests: Swift Testing (`import Testing`), fixtures in Tests/TouchCoreTests/Fixtures
- Reference hardware: Elan 10-finger screen, VID 0x0712 PID 0x000A, descriptor in the spec appendix
```

- [ ] **Step 7: Build and run tests**

Run: `cd /Users/frede/Documents/Programming/TouchBridge && swift build && swift test`
Expected: build succeeds for all five targets; 2 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift LICENSE README.md CLAUDE.md Sources Tests
git commit -m "chore: scaffold TouchBridge package with core, device, inject, app and recorder targets"
```

---

### Task 2: HID report descriptor parser

**Files:**
- Create: `Sources/TouchCore/HID/HIDDescriptor.swift`
- Test: `Tests/TouchCoreTests/HIDDescriptorParserTests.swift`

**Interfaces:**
- Consumes: `HIDUsage`, `Fixtures.elanDescriptorBytes()`.
- Produces: `HIDReportKind`, `HIDCollection`, `HIDField`, `HIDDescriptor`, `HIDDescriptorError`, `HIDDescriptorParser().parse(_ bytes: [UInt8]) throws -> HIDDescriptor`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import TouchCore

@Suite struct HIDDescriptorParserTests {
    @Test func parsesElanInputFieldsOfReportOne() throws {
        let d = try HIDDescriptorParser().parse(try Fixtures.elanDescriptorBytes())
        #expect(d.usesReportIDs)
        let report1 = d.fields.filter { $0.kind == .input && $0.reportID == 1 }
        #expect(report1.count == 52)   // 10 × (id, tip, pad, x, y) + scan time + contact count

        let first = report1[0]
        #expect(first.usage == .contactIdentifier)
        #expect(first.bitOffset == 0)
        #expect(first.bitSize == 6)
        #expect(first.logicalMax == 63)

        let tip = report1[1]
        #expect(tip.usage == .tipSwitch)
        #expect(tip.bitOffset == 6)
        #expect(tip.bitSize == 1)

        let pad = report1[2]
        #expect(pad.isConstant)
        #expect(pad.bitOffset == 7)

        let x = report1[3]
        #expect(x.usage == .x)
        #expect(x.bitOffset == 8)
        #expect(x.bitSize == 16)
        #expect(x.logicalMax == 2976)

        let y = report1[4]
        #expect(y.usage == .y)
        #expect(y.bitOffset == 24)
        #expect(y.logicalMax == 1680)

        let secondFingerID = report1[5]
        #expect(secondFingerID.usage == .contactIdentifier)
        #expect(secondFingerID.bitOffset == 40)

        let scan = report1[50]
        #expect(scan.usage == .scanTime)
        #expect(scan.bitOffset == 400)
        #expect(scan.bitSize == 32)
        #expect(scan.logicalMax == 0x7FFF_FFFF)

        let count = report1[51]
        #expect(count.usage == .contactCount)
        #expect(count.bitOffset == 432)
        #expect(count.bitSize == 8)
        #expect(count.logicalMax == 127)
    }

    @Test func fingerCollectionsAreDistinct() throws {
        let d = try HIDDescriptorParser().parse(try Fixtures.elanDescriptorBytes())
        let tips = d.fields.filter { $0.kind == .input && $0.reportID == 1 && $0.usage == .tipSwitch }
        let fingerIndices = tips.compactMap { $0.collections.last(where: { $0.usage == .finger })?.index }
        #expect(fingerIndices.count == 10)
        #expect(Set(fingerIndices).count == 10)
        #expect(tips.allSatisfy { $0.collections.first?.usage == .touchScreen })
    }

    @Test func parsesFeatureAndOtherReports() throws {
        let d = try HIDDescriptorParser().parse(try Fixtures.elanDescriptorBytes())
        let max = d.fields.first { $0.kind == .feature && $0.reportID == 2 }
        #expect(max?.usage == .contactCountMaximum)
        #expect(max?.logicalMax == 10)
        let blob = d.fields.filter { $0.kind == .feature && $0.reportID == 3 }
        #expect(blob.count == 256)
        let mouseButtons = d.fields.filter { $0.kind == .input && $0.reportID == 7 && $0.usage.page == 0x09 }
        #expect(mouseButtons.map(\.usage.id) == [1, 2, 3])
        let wheel = d.fields.first { $0.kind == .input && $0.reportID == 7 && $0.usage == HIDUsage(page: 0x01, id: 0x38) }
        #expect(wheel?.logicalMin == -127)
        #expect(wheel?.logicalMax == 127)
    }

    @Test func descriptorWithoutReportIDsStartsAtOffsetZero() throws {
        // Usage Page Generic Desktop, Usage Mouse, Collection App, Usage X, Usage Y,
        // Logical Min -127, Logical Max 127, Report Size 8, Report Count 2, Input (Data,Var,Rel), End
        let bytes: [UInt8] = [0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x09, 0x30, 0x09, 0x31,
                              0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x02, 0x81, 0x06, 0xC0]
        let d = try HIDDescriptorParser().parse(bytes)
        #expect(!d.usesReportIDs)
        #expect(d.fields.count == 2)
        #expect(d.fields[0].usage == .x)
        #expect(d.fields[0].bitOffset == 0)
        #expect(d.fields[1].usage == .y)
        #expect(d.fields[1].bitOffset == 8)
        #expect(d.fields[0].reportID == 0)
    }

    @Test func unsignedLogicalMaxWhenMinIsNonNegative() throws {
        // Logical Min 0, Logical Max 0xFF encoded in one byte: must read as 255, not -1
        let bytes: [UInt8] = [0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x09, 0x30,
                              0x15, 0x00, 0x25, 0xFF, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02, 0xC0]
        let d = try HIDDescriptorParser().parse(bytes)
        #expect(d.fields[0].logicalMax == 255)
    }

    @Test func rejectsLongItemsAndPushPop() {
        #expect(throws: HIDDescriptorError.longItemUnsupported(offset: 0)) {
            try HIDDescriptorParser().parse([0xFE, 0x00, 0x00])
        }
        #expect(throws: HIDDescriptorError.unsupportedGlobalItem(tag: 0xA, offset: 0)) {
            try HIDDescriptorParser().parse([0xA4])   // Push
        }
    }

    @Test func rejectsUnbalancedCollections() {
        #expect(throws: HIDDescriptorError.unbalancedCollection(offset: 0)) {
            try HIDDescriptorParser().parse([0xC0])
        }
        #expect(throws: HIDDescriptorError.unbalancedCollection(offset: 2)) {
            try HIDDescriptorParser().parse([0xA1, 0x01])
        }
    }

    @Test func rejectsTruncatedItem() {
        #expect(throws: HIDDescriptorError.truncatedItem(offset: 0)) {
            try HIDDescriptorParser().parse([0x26, 0xA0])   // 2-byte item, only one data byte
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HIDDescriptorParserTests`
Expected: compile error "cannot find 'HIDDescriptorParser' in scope".

- [ ] **Step 3: Write the implementation**

`Sources/TouchCore/HID/HIDDescriptor.swift`:
```swift
import Foundation

public enum HIDReportKind: Sendable, Equatable {
    case input, output, feature
}

/// A collection in the descriptor. `index` is unique per descriptor, in order of appearance.
public struct HIDCollection: Hashable, Sendable {
    public var index: Int
    public var usage: HIDUsage
    /// 0 physical, 1 application, 2 logical, 3 report, 4 named array, 5 usage switch, 6 usage modifier
    public var type: UInt8

    public init(index: Int, usage: HIDUsage, type: UInt8) {
        self.index = index
        self.usage = usage
        self.type = type
    }
}

/// One report field (one element of a Report Count group).
public struct HIDField: Equatable, Sendable {
    public var kind: HIDReportKind
    /// 0 when the descriptor does not use report IDs.
    public var reportID: UInt8
    public var usage: HIDUsage
    /// Bit offset inside the report payload, report ID byte excluded.
    public var bitOffset: Int
    public var bitSize: Int
    public var logicalMin: Int
    public var logicalMax: Int
    public var isConstant: Bool
    /// Enclosing collections, outermost first.
    public var collections: [HIDCollection]

    public init(kind: HIDReportKind, reportID: UInt8, usage: HIDUsage, bitOffset: Int, bitSize: Int,
                logicalMin: Int, logicalMax: Int, isConstant: Bool, collections: [HIDCollection]) {
        self.kind = kind
        self.reportID = reportID
        self.usage = usage
        self.bitOffset = bitOffset
        self.bitSize = bitSize
        self.logicalMin = logicalMin
        self.logicalMax = logicalMax
        self.isConstant = isConstant
        self.collections = collections
    }
}

public struct HIDDescriptor: Equatable, Sendable {
    public var fields: [HIDField]
    public var usesReportIDs: Bool

    public init(fields: [HIDField], usesReportIDs: Bool) {
        self.fields = fields
        self.usesReportIDs = usesReportIDs
    }
}

public enum HIDDescriptorError: Error, Equatable {
    case truncatedItem(offset: Int)
    case longItemUnsupported(offset: Int)
    case unsupportedGlobalItem(tag: UInt8, offset: Int)
    case unbalancedCollection(offset: Int)
}

/// Parses the short-item subset of the HID 1.11 report descriptor format that touch screens use.
/// Supported: Input/Output/Feature/Collection/End Collection; Usage Page, Logical Min/Max,
/// Report Size/ID/Count; Usage, Usage Minimum/Maximum. Physical range and units are skipped.
/// Push/Pop and long items are rejected.
public struct HIDDescriptorParser: Sendable {
    public init() {}

    private struct Globals {
        var usagePage: UInt16 = 0
        var logicalMin = 0
        var logicalMax = 0
        var reportSize = 0
        var reportID: UInt8 = 0
        var reportCount = 0
    }

    private struct Locals {
        var usages: [HIDUsage] = []
        var usageMin: HIDUsage?
    }

    private struct OffsetKey: Hashable {
        var kind: HIDReportKind
        var reportID: UInt8
    }

    public func parse(_ bytes: [UInt8]) throws -> HIDDescriptor {
        var globals = Globals()
        var locals = Locals()
        var stack: [HIDCollection] = []
        var nextCollectionIndex = 0
        var fields: [HIDField] = []
        var offsets: [OffsetKey: Int] = [:]
        var usesReportIDs = false
        var i = 0

        while i < bytes.count {
            let prefix = bytes[i]
            if prefix == 0xFE { throw HIDDescriptorError.longItemUnsupported(offset: i) }
            let sizeCode = Int(prefix & 0x03)
            let size = sizeCode == 3 ? 4 : sizeCode
            let type = (prefix >> 2) & 0x03
            let tag = prefix >> 4
            guard i + 1 + size <= bytes.count else { throw HIDDescriptorError.truncatedItem(offset: i) }

            var raw: UInt32 = 0
            for b in 0..<size { raw |= UInt32(bytes[i + 1 + b]) << (8 * b) }
            let signed: Int
            switch size {
            case 1: signed = Int(Int8(truncatingIfNeeded: raw))
            case 2: signed = Int(Int16(truncatingIfNeeded: raw))
            case 4: signed = Int(Int32(truncatingIfNeeded: raw))
            default: signed = 0
            }

            switch type {
            case 1: // global
                switch tag {
                case 0x0: globals.usagePage = UInt16(raw & 0xFFFF)
                case 0x1: globals.logicalMin = signed
                case 0x2:
                    // A non-negative minimum lets the maximum be read unsigned (e.g. 25 FF = 255).
                    globals.logicalMax = (globals.logicalMin >= 0 && signed < 0) ? Int(raw) : signed
                case 0x3, 0x4, 0x5, 0x6: break // physical min/max, unit exponent, unit
                case 0x7: globals.reportSize = Int(raw)
                case 0x8:
                    globals.reportID = UInt8(raw & 0xFF)
                    usesReportIDs = true
                case 0x9: globals.reportCount = Int(raw)
                default: throw HIDDescriptorError.unsupportedGlobalItem(tag: tag, offset: i)
                }
            case 2: // local
                switch tag {
                case 0x0: locals.usages.append(Self.usage(raw, size: size, page: globals.usagePage))
                case 0x1: locals.usageMin = Self.usage(raw, size: size, page: globals.usagePage)
                case 0x2:
                    let max = Self.usage(raw, size: size, page: globals.usagePage)
                    if let min = locals.usageMin, min.id <= max.id {
                        for id in min.id...max.id { locals.usages.append(HIDUsage(page: min.page, id: id)) }
                    }
                    locals.usageMin = nil
                default: break // designators, strings, delimiters
                }
            case 0: // main
                switch tag {
                case 0xA:
                    let usage = locals.usages.first ?? HIDUsage(page: globals.usagePage, id: 0)
                    stack.append(HIDCollection(index: nextCollectionIndex, usage: usage, type: UInt8(raw & 0xFF)))
                    nextCollectionIndex += 1
                    locals = Locals()
                case 0xC:
                    guard !stack.isEmpty else { throw HIDDescriptorError.unbalancedCollection(offset: i) }
                    stack.removeLast()
                    locals = Locals()
                case 0x8, 0x9, 0xB:
                    let kind: HIDReportKind = tag == 0x8 ? .input : (tag == 0x9 ? .output : .feature)
                    let key = OffsetKey(kind: kind, reportID: globals.reportID)
                    var offset = offsets[key, default: 0]
                    let isConstant = (raw & 0x1) != 0
                    for n in 0..<globals.reportCount {
                        let usage: HIDUsage
                        if locals.usages.isEmpty {
                            usage = HIDUsage(page: globals.usagePage, id: 0)
                        } else {
                            usage = locals.usages[min(n, locals.usages.count - 1)]
                        }
                        fields.append(HIDField(kind: kind, reportID: globals.reportID, usage: usage,
                                               bitOffset: offset, bitSize: globals.reportSize,
                                               logicalMin: globals.logicalMin, logicalMax: globals.logicalMax,
                                               isConstant: isConstant, collections: stack))
                        offset += globals.reportSize
                    }
                    offsets[key] = offset
                    locals = Locals()
                default: break
                }
            default: break // reserved
            }
            i += 1 + size
        }
        guard stack.isEmpty else { throw HIDDescriptorError.unbalancedCollection(offset: bytes.count) }
        return HIDDescriptor(fields: fields, usesReportIDs: usesReportIDs)
    }

    /// A 4-byte usage item carries the page in its upper 16 bits (extended usage).
    private static func usage(_ raw: UInt32, size: Int, page: UInt16) -> HIDUsage {
        if size == 4 {
            return HIDUsage(page: UInt16(raw >> 16), id: UInt16(raw & 0xFFFF))
        }
        return HIDUsage(page: page, id: UInt16(raw & 0xFFFF))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HIDDescriptorParserTests`
Expected: 8 tests pass. If `rejectsUnbalancedCollections` reports offset 2 vs 2 mismatch, check that the end-of-input check uses `bytes.count` (2 for `[0xA1, 0x01]`).

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchCore/HID/HIDDescriptor.swift Tests/TouchCoreTests/HIDDescriptorParserTests.swift
git commit -m "feat(core): parse HID report descriptors into fields with bit offsets"
```

---

### Task 3: Touch screen layout extraction

**Files:**
- Create: `Sources/TouchCore/HID/TouchScreenLayout.swift`
- Create: `Tests/TouchCoreTests/Support/SyntheticDescriptors.swift`
- Modify: `Tests/TouchCoreTests/Support/Fixtures.swift` (add `elanLayout()`)
- Test: `Tests/TouchCoreTests/TouchScreenLayoutTests.swift`

**Interfaces:**
- Consumes: `HIDDescriptor`, `HIDField`, `HIDUsage`.
- Produces: `FingerSlot`, `TouchScreenLayout(descriptor:) throws`, `TouchScreenLayout.LayoutError`, properties `reportID: UInt8`, `usesReportIDs: Bool`, `slots: [FingerSlot]`, `contactCount: HIDField`, `scanTime: HIDField?`, `logicalMaxX: Int`, `logicalMaxY: Int`, `payloadByteCount: Int`; test helper `Fixtures.elanLayout()`, `SyntheticDescriptors.twoFingerNoReportID`.

- [ ] **Step 1: Write the synthetic descriptor helper**

`Tests/TouchCoreTests/Support/SyntheticDescriptors.swift`:
```swift
enum SyntheticDescriptors {
    /// Two-finger touch screen without report IDs.
    /// Per finger: tip (1 bit), contact id (7 bits), x (16), y (16) = 40 bits. Contact count (8 bits) at bit 80.
    static let twoFingerNoReportID: [UInt8] = {
        let finger: [UInt8] = [
            0x09, 0x22, 0xA1, 0x02,             // Usage Finger, Collection Logical
            0x05, 0x0D, 0x09, 0x42,             // Usage Page Digitizer, Usage Tip Switch
            0x15, 0x00, 0x25, 0x01,             // Logical 0..1
            0x75, 0x01, 0x95, 0x01, 0x81, 0x02, // 1 bit input
            0x09, 0x51, 0x25, 0x0F,             // Usage Contact ID, Logical Max 15
            0x75, 0x07, 0x95, 0x01, 0x81, 0x02, // 7 bit input
            0x05, 0x01, 0x09, 0x30, 0x09, 0x31, // Generic Desktop X, Y
            0x26, 0xFF, 0x03,                   // Logical Max 1023
            0x75, 0x10, 0x95, 0x02, 0x81, 0x02, // 2 × 16 bit input
            0xC0,
        ]
        return [0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01] + finger + finger
            + [0x05, 0x0D, 0x09, 0x54, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02, 0xC0]
    }()

    /// Touch screen with one finger but no Contact Count field.
    static let fingerWithoutContactCount: [UInt8] = [
        0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01,
        0x09, 0x22, 0xA1, 0x02, 0x05, 0x0D, 0x09, 0x42, 0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0x75, 0x07, 0x95, 0x01, 0x81, 0x03,
        0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x26, 0xFF, 0x0F, 0x75, 0x10, 0x95, 0x02, 0x81, 0x02, 0xC0,
        0xC0,
    ]

    /// Touch screen whose finger has X but no Y.
    static let fingerWithoutY: [UInt8] = [
        0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01,
        0x09, 0x22, 0xA1, 0x02, 0x05, 0x0D, 0x09, 0x42, 0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0x75, 0x07, 0x95, 0x01, 0x81, 0x03,
        0x05, 0x01, 0x09, 0x30, 0x26, 0xFF, 0x0F, 0x75, 0x10, 0x95, 0x01, 0x81, 0x02, 0xC0,
        0x05, 0x0D, 0x09, 0x54, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,
        0xC0,
    ]

    /// Mouse only (no touch screen collection).
    static let mouseOnly: [UInt8] = [
        0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x09, 0x30, 0x09, 0x31,
        0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x02, 0x81, 0x06, 0xC0,
    ]
}
```

Add to `Tests/TouchCoreTests/Support/Fixtures.swift` inside `enum Fixtures`:
```swift
    static func elanLayout() throws -> TouchScreenLayout {
        try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(elanDescriptorBytes()))
    }
```
and add `@testable import TouchCore` at the top of that file.

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
@testable import TouchCore

@Suite struct TouchScreenLayoutTests {
    @Test func elanLayoutHasTenSlots() throws {
        let layout = try Fixtures.elanLayout()
        #expect(layout.reportID == 1)
        #expect(layout.usesReportIDs)
        #expect(layout.slots.count == 10)
        #expect(layout.slots[0].contactID?.bitOffset == 0)
        #expect(layout.slots[0].tipSwitch.bitOffset == 6)
        #expect(layout.slots[0].x.bitOffset == 8)
        #expect(layout.slots[0].y.bitOffset == 24)
        #expect(layout.slots[9].x.bitOffset == 9 * 40 + 8)
        #expect(layout.slots[0].inRange == nil)
        #expect(layout.contactCount.bitOffset == 432)
        #expect(layout.scanTime?.bitOffset == 400)
        #expect(layout.logicalMaxX == 2976)
        #expect(layout.logicalMaxY == 1680)
        #expect(layout.payloadByteCount == 55)
    }

    @Test func syntheticLayoutWithoutReportIDs() throws {
        let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(SyntheticDescriptors.twoFingerNoReportID))
        #expect(layout.reportID == 0)
        #expect(!layout.usesReportIDs)
        #expect(layout.slots.count == 2)
        #expect(layout.slots[0].tipSwitch.bitOffset == 0)
        #expect(layout.slots[0].contactID?.bitOffset == 1)
        #expect(layout.slots[1].tipSwitch.bitOffset == 40)
        #expect(layout.contactCount.bitOffset == 80)
        #expect(layout.scanTime == nil)
        #expect(layout.logicalMaxX == 1023)
        #expect(layout.payloadByteCount == 11)
    }

    @Test func errors() throws {
        let parser = HIDDescriptorParser()
        #expect(throws: TouchScreenLayout.LayoutError.noTouchScreenCollection) {
            try TouchScreenLayout(descriptor: parser.parse(SyntheticDescriptors.mouseOnly))
        }
        #expect(throws: TouchScreenLayout.LayoutError.missingContactCount) {
            try TouchScreenLayout(descriptor: parser.parse(SyntheticDescriptors.fingerWithoutContactCount))
        }
        #expect(throws: TouchScreenLayout.LayoutError.slotIncomplete(index: 0)) {
            try TouchScreenLayout(descriptor: parser.parse(SyntheticDescriptors.fingerWithoutY))
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter TouchScreenLayoutTests`
Expected: compile error "cannot find 'TouchScreenLayout' in scope".

- [ ] **Step 4: Write the implementation**

`Sources/TouchCore/HID/TouchScreenLayout.swift`:
```swift
import Foundation

/// The fields of one finger (one Finger logical collection) inside the touch report.
public struct FingerSlot: Equatable, Sendable {
    public var contactID: HIDField?
    public var tipSwitch: HIDField
    public var x: HIDField
    public var y: HIDField
    public var inRange: HIDField?
    public var confidence: HIDField?
}

/// Where the touch data lives inside the device's input report.
public struct TouchScreenLayout: Equatable, Sendable {
    public enum LayoutError: Error, Equatable {
        case noTouchScreenCollection
        case missingContactCount
        case noFingerSlots
        case slotIncomplete(index: Int)
    }

    public var reportID: UInt8
    public var usesReportIDs: Bool
    public var slots: [FingerSlot]
    public var contactCount: HIDField
    public var scanTime: HIDField?
    public var logicalMaxX: Int
    public var logicalMaxY: Int
    /// Bytes of the input report payload, report ID byte excluded.
    public var payloadByteCount: Int

    public init(descriptor: HIDDescriptor) throws {
        let touchFields = descriptor.fields.filter { field in
            field.kind == .input
                && field.collections.contains { $0.usage == .touchScreen && $0.type == 1 }
        }
        guard !touchFields.isEmpty else { throw LayoutError.noTouchScreenCollection }
        guard let count = touchFields.first(where: { $0.usage == .contactCount }) else {
            throw LayoutError.missingContactCount
        }
        let reportFields = touchFields.filter { $0.reportID == count.reportID }

        var groups: [Int: [HIDField]] = [:]
        var order: [Int] = []
        for field in reportFields {
            guard let finger = field.collections.last(where: { $0.usage == .finger }) else { continue }
            if groups[finger.index] == nil { order.append(finger.index) }
            groups[finger.index, default: []].append(field)
        }
        guard !order.isEmpty else { throw LayoutError.noFingerSlots }

        var slots: [FingerSlot] = []
        for (index, collectionIndex) in order.enumerated() {
            let group = groups[collectionIndex] ?? []
            guard let tip = group.first(where: { $0.usage == .tipSwitch }),
                  let x = group.first(where: { $0.usage == .x }),
                  let y = group.first(where: { $0.usage == .y }) else {
                throw LayoutError.slotIncomplete(index: index)
            }
            slots.append(FingerSlot(
                contactID: group.first { $0.usage == .contactIdentifier },
                tipSwitch: tip, x: x, y: y,
                inRange: group.first { $0.usage == .inRange },
                confidence: group.first { $0.usage == .confidence }
            ))
        }

        let lastBit = reportFields.map { $0.bitOffset + $0.bitSize }.max() ?? 0
        self.reportID = count.reportID
        self.usesReportIDs = descriptor.usesReportIDs
        self.slots = slots
        self.contactCount = count
        self.scanTime = reportFields.first { $0.usage == .scanTime }
        self.logicalMaxX = slots[0].x.logicalMax
        self.logicalMaxY = slots[0].y.logicalMax
        self.payloadByteCount = (lastBit + 7) / 8
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter TouchScreenLayoutTests`
Expected: 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/TouchCore/HID/TouchScreenLayout.swift Tests/TouchCoreTests/Support Tests/TouchCoreTests/TouchScreenLayoutTests.swift
git commit -m "feat(core): derive finger slots and contact count field from a descriptor"
```

---

### Task 4: Report decoder

**Files:**
- Create: `Sources/TouchCore/HID/ReportDecoder.swift`
- Create: `Tests/TouchCoreTests/Support/ElanReport.swift`
- Test: `Tests/TouchCoreTests/ReportDecoderTests.swift`

**Interfaces:**
- Consumes: `TouchScreenLayout`, `HIDField`.
- Produces: `RawContact { id: Int, x: Int, y: Int, down: Bool }`, `TouchFrame { timestamp: UInt64, contacts: [RawContact] }`, `ReportDecoder(layout:)` with `mutating func decode(payload: [UInt8], timestamp: UInt64) -> TouchFrame?`; test helper `ElanReport.payload(contacts:count:scanTime:)`.

- [ ] **Step 1: Write the payload builder**

`Tests/TouchCoreTests/Support/ElanReport.swift`:
```swift
enum ElanReport {
    struct Slot {
        var id: Int
        var x: Int
        var y: Int
        var down: Bool
    }

    /// Builds the 55-byte payload of Elan report 1 (report ID byte excluded).
    /// Slot layout: byte 0 = contact id (bits 0-5) | tip (bit 6); x LE u16; y LE u16.
    static func payload(contacts: [Slot], count: Int, scanTime: UInt32 = 0) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 55)
        for (i, c) in contacts.prefix(10).enumerated() {
            let base = i * 5
            p[base] = UInt8(c.id & 0x3F) | (c.down ? 0x40 : 0)
            p[base + 1] = UInt8(c.x & 0xFF)
            p[base + 2] = UInt8((c.x >> 8) & 0xFF)
            p[base + 3] = UInt8(c.y & 0xFF)
            p[base + 4] = UInt8((c.y >> 8) & 0xFF)
        }
        p[50] = UInt8(scanTime & 0xFF)
        p[51] = UInt8((scanTime >> 8) & 0xFF)
        p[52] = UInt8((scanTime >> 16) & 0xFF)
        p[53] = UInt8((scanTime >> 24) & 0xFF)
        p[54] = UInt8(count)
        return p
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
@testable import TouchCore

@Suite struct ReportDecoderTests {
    @Test func decodesTwoContacts() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let payload = ElanReport.payload(contacts: [
            .init(id: 0, x: 1000, y: 500, down: true),
            .init(id: 1, x: 2000, y: 800, down: true),
        ], count: 2, scanTime: 42)
        let frame = decoder.decode(payload: payload, timestamp: 5)
        #expect(frame == TouchFrame(timestamp: 5, contacts: [
            RawContact(id: 0, x: 1000, y: 500, down: true),
            RawContact(id: 1, x: 2000, y: 800, down: true),
        ]))
    }

    @Test func zeroCountIsEmptyFrame() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let frame = decoder.decode(payload: ElanReport.payload(contacts: [], count: 0), timestamp: 1)
        #expect(frame == TouchFrame(timestamp: 1, contacts: []))
    }

    @Test func liftIsReportedWithDownFalse() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let payload = ElanReport.payload(contacts: [.init(id: 3, x: 10, y: 20, down: false)], count: 1)
        #expect(decoder.decode(payload: payload, timestamp: 1)?.contacts == [RawContact(id: 3, x: 10, y: 20, down: false)])
    }

    @Test func decodesTenContacts() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let slots = (0..<10).map { ElanReport.Slot(id: $0, x: $0 * 100, y: $0 * 50, down: true) }
        let frame = decoder.decode(payload: ElanReport.payload(contacts: slots, count: 10), timestamp: 1)
        #expect(frame?.contacts.count == 10)
        #expect(frame?.contacts[9] == RawContact(id: 9, x: 900, y: 450, down: true))
    }

    @Test func shortPayloadIsIgnored() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        #expect(decoder.decode(payload: [UInt8](repeating: 0, count: 10), timestamp: 1) == nil)
    }

    @Test func hybridReportsAreMerged() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let first = (0..<10).map { ElanReport.Slot(id: $0, x: $0, y: 0, down: true) }
        let second = [ElanReport.Slot(id: 10, x: 10, y: 0, down: true), ElanReport.Slot(id: 11, x: 11, y: 0, down: true)]
        #expect(decoder.decode(payload: ElanReport.payload(contacts: first, count: 12), timestamp: 1) == nil)
        let frame = decoder.decode(payload: ElanReport.payload(contacts: second, count: 0), timestamp: 2)
        #expect(frame?.timestamp == 2)
        #expect(frame?.contacts.count == 12)
        #expect(frame?.contacts.map(\.id) == Array(0..<12))
    }

    @Test func staleHybridPendingIsDiscardedByNewCount() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let first = (0..<10).map { ElanReport.Slot(id: $0, x: $0, y: 0, down: true) }
        #expect(decoder.decode(payload: ElanReport.payload(contacts: first, count: 12), timestamp: 1) == nil)
        let fresh = decoder.decode(payload: ElanReport.payload(contacts: [.init(id: 4, x: 7, y: 8, down: true)], count: 1), timestamp: 2)
        #expect(fresh == TouchFrame(timestamp: 2, contacts: [RawContact(id: 4, x: 7, y: 8, down: true)]))
    }

    @Test func decodesLayoutWithoutReportIDs() throws {
        let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(SyntheticDescriptors.twoFingerNoReportID))
        var decoder = ReportDecoder(layout: layout)
        // finger 0: tip 1, id 5 → byte0 = 0b0000_1011 = 0x0B; x = 0x0123, y = 0x0045
        // finger 1: tip 0, id 0 → 0x00; x = 0, y = 0; count = 1
        let payload: [UInt8] = [0x0B, 0x23, 0x01, 0x45, 0x00,
                                0x00, 0x00, 0x00, 0x00, 0x00,
                                0x01]
        let frame = decoder.decode(payload: payload, timestamp: 9)
        #expect(frame == TouchFrame(timestamp: 9, contacts: [RawContact(id: 5, x: 0x123, y: 0x45, down: true)]))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ReportDecoderTests`
Expected: compile error "cannot find 'ReportDecoder' in scope".

- [ ] **Step 4: Write the implementation**

`Sources/TouchCore/HID/ReportDecoder.swift`:
```swift
import Foundation

/// One contact as reported by the device, in digitizer units.
public struct RawContact: Equatable, Sendable {
    public var id: Int
    public var x: Int
    public var y: Int
    public var down: Bool

    public init(id: Int, x: Int, y: Int, down: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.down = down
    }
}

/// All contacts of one report (or of one merged hybrid-mode group).
public struct TouchFrame: Equatable, Sendable {
    /// Monotonic nanoseconds.
    public var timestamp: UInt64
    public var contacts: [RawContact]

    public init(timestamp: UInt64, contacts: [RawContact]) {
        self.timestamp = timestamp
        self.contacts = contacts
    }
}

/// Turns raw touch report payloads into `TouchFrame`s.
/// Parallel mode: every report carries all contacts and `contactCount` > 0 (or 0 when all lifted).
/// Hybrid mode: the first report carries `contactCount` = total and the first slots; follow-up reports
/// carry `contactCount` = 0 and the remaining slots until the total is reached.
public struct ReportDecoder: Sendable {
    public let layout: TouchScreenLayout
    private var pending: [RawContact] = []
    private var expected = 0

    public init(layout: TouchScreenLayout) {
        self.layout = layout
    }

    /// `payload` excludes the report ID byte. Returns nil for short payloads and incomplete hybrid groups.
    public mutating func decode(payload: [UInt8], timestamp: UInt64) -> TouchFrame? {
        guard payload.count >= layout.payloadByteCount else { return nil }
        let reported = Int(Self.value(of: layout.contactCount, in: payload))
        if reported > 0 {
            pending = []
            expected = reported
        } else if expected == 0 {
            return TouchFrame(timestamp: timestamp, contacts: [])
        }

        let remaining = expected - pending.count
        for slot in layout.slots.prefix(max(remaining, 0)) {
            let id = slot.contactID.map { Int(Self.value(of: $0, in: payload)) } ?? pending.count
            pending.append(RawContact(
                id: id,
                x: Int(Self.value(of: slot.x, in: payload)),
                y: Int(Self.value(of: slot.y, in: payload)),
                down: Self.value(of: slot.tipSwitch, in: payload) != 0
            ))
        }

        if pending.count >= expected {
            let frame = TouchFrame(timestamp: timestamp, contacts: pending)
            pending = []
            expected = 0
            return frame
        }
        return nil
    }

    /// Little-endian bit field extraction.
    static func value(of field: HIDField, in bytes: [UInt8]) -> UInt32 {
        var value: UInt32 = 0
        for bit in 0..<field.bitSize {
            let absolute = field.bitOffset + bit
            let byte = bytes[absolute / 8]
            let b = (byte >> UInt8(absolute % 8)) & 1
            value |= UInt32(b) << UInt32(bit)
        }
        return value
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ReportDecoderTests`
Expected: 8 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/TouchCore/HID/ReportDecoder.swift Tests/TouchCoreTests/Support/ElanReport.swift Tests/TouchCoreTests/ReportDecoderTests.swift
git commit -m "feat(core): decode touch reports into frames, including hybrid-mode merging"
```

---

### Task 5: Display mapper

**Files:**
- Create: `Sources/TouchCore/Mapping/DisplayMapper.swift`
- Test: `Tests/TouchCoreTests/DisplayMapperTests.swift`

**Interfaces:**
- Consumes: `TouchFrame`, `RawContact`.
- Produces: `Calibration` (Codable), `MappingConfig`, `Contact { id, position: CGPoint, down }`, `ScreenFrame { timestamp, contacts: [Contact] }`, `DisplayMapper(config:)` with `map(x:y:) -> CGPoint` and `map(_ frame: TouchFrame) -> ScreenFrame`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
@testable import TouchCore

@Suite struct DisplayMapperTests {
    let frame = CGRect(x: 3024, y: 0, width: 1920, height: 1080)   // external display right of the main one

    func mapper(orientation: Int = 0, calibration: Calibration? = nil, frame: CGRect? = nil) -> DisplayMapper {
        var cal = calibration ?? Calibration()
        cal.orientation = orientation
        return DisplayMapper(config: MappingConfig(logicalMaxX: 2976, logicalMaxY: 1680,
                                                   displayFrame: frame ?? self.frame, calibration: cal))
    }

    @Test func identityCorners() {
        let m = mapper()
        #expect(m.map(x: 0, y: 0) == CGPoint(x: 3024, y: 0))
        #expect(m.map(x: 2976, y: 1680) == CGPoint(x: 3024 + 1920, y: 1080))
        #expect(m.map(x: 1488, y: 840) == CGPoint(x: 3024 + 960, y: 540))
    }

    @Test func orientations() {
        #expect(mapper(orientation: 90).map(x: 0, y: 0) == CGPoint(x: 3024 + 1920, y: 0))
        #expect(mapper(orientation: 180).map(x: 0, y: 0) == CGPoint(x: 3024 + 1920, y: 1080))
        #expect(mapper(orientation: 270).map(x: 0, y: 0) == CGPoint(x: 3024, y: 1080))
        #expect(mapper(orientation: 90).map(x: 2976, y: 0) == CGPoint(x: 3024 + 1920, y: 1080))
    }

    @Test func calibrationScaleAndOffset() {
        let cal = Calibration(orientation: 0, scaleX: 0.5, scaleY: 2, offsetX: 0.25, offsetY: -0.5)
        let m = mapper(calibration: cal)
        // nx = 0.5*0.5+0.25 = 0.5 ; ny = 0.5*2-0.5 = 0.5
        #expect(m.map(x: 1488, y: 840) == CGPoint(x: 3024 + 960, y: 540))
    }

    @Test func clampsOutsideRange() {
        let m = mapper(calibration: Calibration(orientation: 0, scaleX: 1, scaleY: 1, offsetX: 0.5, offsetY: 0))
        #expect(m.map(x: 2976, y: 0) == CGPoint(x: 3024 + 1920, y: 0))
        #expect(m.map(x: 4000, y: 5000) == CGPoint(x: 3024 + 1920, y: 1080))
        #expect(mapper().map(x: -5, y: -5) == CGPoint(x: 3024, y: 0))
    }

    @Test func negativeOriginDisplay() {
        let m = mapper(frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080))
        #expect(m.map(x: 0, y: 0) == CGPoint(x: -1920, y: -200))
        #expect(m.map(x: 2976, y: 1680) == CGPoint(x: 0, y: 880))
    }

    @Test func mapsWholeFrame() {
        let m = mapper()
        let out = m.map(TouchFrame(timestamp: 7, contacts: [RawContact(id: 2, x: 0, y: 1680, down: true)]))
        #expect(out == ScreenFrame(timestamp: 7, contacts: [Contact(id: 2, position: CGPoint(x: 3024, y: 1080), down: true)]))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DisplayMapperTests`
Expected: compile error "cannot find 'DisplayMapper' in scope".

- [ ] **Step 3: Write the implementation**

`Sources/TouchCore/Mapping/DisplayMapper.swift`:
```swift
import Foundation
import CoreGraphics

/// Per-device calibration. Orientation is applied to normalized coordinates before scale/offset.
public struct Calibration: Codable, Equatable, Sendable {
    /// 0, 90, 180 or 270 degrees.
    public var orientation: Int
    public var scaleX: Double
    public var scaleY: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(orientation: Int = 0, scaleX: Double = 1, scaleY: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.orientation = orientation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orientation = try c.decodeIfPresent(Int.self, forKey: .orientation) ?? 0
        scaleX = try c.decodeIfPresent(Double.self, forKey: .scaleX) ?? 1
        scaleY = try c.decodeIfPresent(Double.self, forKey: .scaleY) ?? 1
        offsetX = try c.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try c.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
    }
}

public struct MappingConfig: Equatable, Sendable {
    public var logicalMaxX: Int
    public var logicalMaxY: Int
    /// Global CoreGraphics display coordinates (origin top-left of the main display).
    public var displayFrame: CGRect
    public var calibration: Calibration

    public init(logicalMaxX: Int, logicalMaxY: Int, displayFrame: CGRect, calibration: Calibration) {
        self.logicalMaxX = logicalMaxX
        self.logicalMaxY = logicalMaxY
        self.displayFrame = displayFrame
        self.calibration = calibration
    }
}

/// A contact in global screen coordinates.
public struct Contact: Equatable, Sendable {
    public var id: Int
    public var position: CGPoint
    public var down: Bool

    public init(id: Int, position: CGPoint, down: Bool) {
        self.id = id
        self.position = position
        self.down = down
    }
}

public struct ScreenFrame: Equatable, Sendable {
    public var timestamp: UInt64
    public var contacts: [Contact]

    public init(timestamp: UInt64, contacts: [Contact]) {
        self.timestamp = timestamp
        self.contacts = contacts
    }
}

public struct DisplayMapper: Sendable {
    public var config: MappingConfig

    public init(config: MappingConfig) {
        self.config = config
    }

    public func map(_ frame: TouchFrame) -> ScreenFrame {
        ScreenFrame(timestamp: frame.timestamp, contacts: frame.contacts.map {
            Contact(id: $0.id, position: map(x: $0.x, y: $0.y), down: $0.down)
        })
    }

    public func map(x: Int, y: Int) -> CGPoint {
        var nx = Double(x) / Double(max(config.logicalMaxX, 1))
        var ny = Double(y) / Double(max(config.logicalMaxY, 1))
        switch config.calibration.orientation {
        case 90: (nx, ny) = (1 - ny, nx)
        case 180: (nx, ny) = (1 - nx, 1 - ny)
        case 270: (nx, ny) = (ny, 1 - nx)
        default: break
        }
        nx = nx * config.calibration.scaleX + config.calibration.offsetX
        ny = ny * config.calibration.scaleY + config.calibration.offsetY
        nx = min(max(nx, 0), 1)
        ny = min(max(ny, 0), 1)
        let f = config.displayFrame
        return CGPoint(x: f.origin.x + nx * f.width, y: f.origin.y + ny * f.height)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DisplayMapperTests`
Expected: 6 tests pass. If `orientations` fails on `(x: 2976, y: 0)` with orientation 90: nx = 1 - 0 = 1, ny = 1 → bottom-right; that is the intended definition (clockwise rotation of the touch point). Whether 90 or 270 matches a physically rotated display is decided in Task 15 by trying both.

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchCore/Mapping/DisplayMapper.swift Tests/TouchCoreTests/DisplayMapperTests.swift
git commit -m "feat(core): map digitizer coordinates to global display coordinates"
```

---

### Task 6: Touch tracker

**Files:**
- Create: `Sources/TouchCore/Touch/TouchTracker.swift`
- Create: `Tests/TouchCoreTests/Support/TouchBuilders.swift`
- Test: `Tests/TouchCoreTests/TouchTrackerTests.swift`

**Interfaces:**
- Consumes: `ScreenFrame`, `Contact`.
- Produces: `ActiveTouch { id, position, startPosition, startTime, lastUpdate }`, `TouchPhase`, `TouchEvent { id, phase, position, timestamp }`, `TouchTracker(stuckTimeout: UInt64)` with `process(_ frame: ScreenFrame) -> [TouchEvent]`, `tick(_ timestamp: UInt64) -> [TouchEvent]`, `touches: [ActiveTouch]`; test helpers `ms(_:)`, `pt(_:_:)`, `touch(_:_:_:start:now:)`.

- [ ] **Step 1: Write the test helpers**

`Tests/TouchCoreTests/Support/TouchBuilders.swift`:
```swift
import CoreGraphics
@testable import TouchCore

/// Milliseconds → nanoseconds.
func ms(_ n: Int) -> UInt64 { UInt64(n) * 1_000_000 }

func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

func touch(_ id: Int, _ x: Double, _ y: Double, start: UInt64 = 0, now: UInt64 = 0) -> ActiveTouch {
    ActiveTouch(id: id, position: pt(x, y), startPosition: pt(x, y), startTime: start, lastUpdate: now)
}

func frame(_ t: UInt64, _ contacts: [(id: Int, x: Double, y: Double, down: Bool)]) -> ScreenFrame {
    ScreenFrame(timestamp: t, contacts: contacts.map { Contact(id: $0.id, position: pt($0.x, $0.y), down: $0.down) })
}
```

- [ ] **Step 2: Write the failing tests**

```swift
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

    @Test func touchesKeepArrivalOrder() {
        var tracker = TouchTracker(stuckTimeout: ms(500))
        _ = tracker.process(frame(ms(0), [(7, 10, 10, true)]))
        _ = tracker.process(frame(ms(5), [(2, 20, 20, true), (7, 10, 10, true)]))
        #expect(tracker.touches.map(\.id) == [7, 2])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter TouchTrackerTests`
Expected: compile error "cannot find 'TouchTracker' in scope".

- [ ] **Step 4: Write the implementation**

`Sources/TouchCore/Touch/TouchTracker.swift`:
```swift
import Foundation
import CoreGraphics

public struct ActiveTouch: Equatable, Sendable {
    public var id: Int
    public var position: CGPoint
    public var startPosition: CGPoint
    public var startTime: UInt64
    public var lastUpdate: UInt64

    public init(id: Int, position: CGPoint, startPosition: CGPoint, startTime: UInt64, lastUpdate: UInt64) {
        self.id = id
        self.position = position
        self.startPosition = startPosition
        self.startTime = startTime
        self.lastUpdate = lastUpdate
    }
}

public enum TouchPhase: Sendable, Equatable {
    case began, moved, ended
}

public struct TouchEvent: Equatable, Sendable {
    public var id: Int
    public var phase: TouchPhase
    public var position: CGPoint
    public var timestamp: UInt64

    public init(id: Int, phase: TouchPhase, position: CGPoint, timestamp: UInt64) {
        self.id = id
        self.phase = phase
        self.position = position
        self.timestamp = timestamp
    }
}

/// Maintains the set of active contacts across frames and ends contacts that stop being reported.
public struct TouchTracker: Sendable {
    public var stuckTimeout: UInt64
    public private(set) var touches: [ActiveTouch] = []

    public init(stuckTimeout: UInt64 = 500_000_000) {
        self.stuckTimeout = stuckTimeout
    }

    public mutating func process(_ frame: ScreenFrame) -> [TouchEvent] {
        var events: [TouchEvent] = []
        var seen = Set<Int>()
        for contact in frame.contacts {
            if let index = touches.firstIndex(where: { $0.id == contact.id }) {
                if contact.down {
                    touches[index].position = contact.position
                    touches[index].lastUpdate = frame.timestamp
                    events.append(TouchEvent(id: contact.id, phase: .moved, position: contact.position, timestamp: frame.timestamp))
                    seen.insert(contact.id)
                } else {
                    events.append(TouchEvent(id: contact.id, phase: .ended, position: contact.position, timestamp: frame.timestamp))
                    touches.remove(at: index)
                }
            } else if contact.down {
                touches.append(ActiveTouch(id: contact.id, position: contact.position, startPosition: contact.position,
                                           startTime: frame.timestamp, lastUpdate: frame.timestamp))
                events.append(TouchEvent(id: contact.id, phase: .began, position: contact.position, timestamp: frame.timestamp))
                seen.insert(contact.id)
            }
        }
        for touch in touches where !seen.contains(touch.id) {
            events.append(TouchEvent(id: touch.id, phase: .ended, position: touch.position, timestamp: frame.timestamp))
        }
        touches.removeAll { !seen.contains($0.id) }
        return events
    }

    public mutating func tick(_ timestamp: UInt64) -> [TouchEvent] {
        let expired = touches.filter { timestamp > $0.lastUpdate && timestamp - $0.lastUpdate > stuckTimeout }
        guard !expired.isEmpty else { return [] }
        let ids = Set(expired.map(\.id))
        touches.removeAll { ids.contains($0.id) }
        return expired.map { TouchEvent(id: $0.id, phase: .ended, position: $0.position, timestamp: timestamp) }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter TouchTrackerTests`
Expected: 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/TouchCore/Touch/TouchTracker.swift Tests/TouchCoreTests/Support/TouchBuilders.swift Tests/TouchCoreTests/TouchTrackerTests.swift
git commit -m "feat(core): track contact lifecycle with stuck-contact timeout"
```

---

### Task 7: Gesture engine, one finger

**Files:**
- Create: `Sources/TouchCore/Gesture/Action.swift`, `Sources/TouchCore/Gesture/GestureConfig.swift`, `Sources/TouchCore/Gesture/Geometry.swift`, `Sources/TouchCore/Gesture/GestureEngine.swift`
- Test: `Tests/TouchCoreTests/GestureEngineOneFingerTests.swift`

**Interfaces:**
- Consumes: `ActiveTouch`.
- Produces: `GesturePhase`, `MouseButton`, `SwipeDirection`, `Action` (all cases, used by Tasks 8–10 and 13), `GestureConfig` (Codable, used by Task 11), `Geometry` (internal helpers), `GestureEngine(config:)` with `update(touches:timestamp:) -> [Action]`, `tick(_:) -> [Action]`, `reset() -> [Action]`, `isIdle: Bool`. The two-finger branch is stubbed in this task and replaced in Task 8; the multi-finger branch in Task 9.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
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

    @Test func configIsCodableWithDefaults() throws {
        let decoded = try JSONDecoder().decode(GestureConfig.self, from: Data("{\"tapMaxMovement\": 12}".utf8))
        #expect(decoded.tapMaxMovement == 12)
        #expect(decoded.longPressDuration == 0.6)
        let roundTrip = try JSONDecoder().decode(GestureConfig.self, from: JSONEncoder().encode(GestureConfig()))
        #expect(roundTrip == GestureConfig())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GestureEngineOneFingerTests`
Expected: compile error "cannot find 'GestureEngine' in scope".

- [ ] **Step 3: Write Action.swift**

```swift
import Foundation
import CoreGraphics

public enum GesturePhase: Sendable, Equatable {
    case began, changed, ended, cancelled
}

public enum MouseButton: Sendable, Equatable {
    case left, right
}

public enum SwipeDirection: Sendable, Equatable {
    case up, down, left, right
}

/// What the gesture engine wants to happen. Positions are global screen coordinates.
public enum Action: Equatable, Sendable {
    case moveCursor(to: CGPoint)
    case click(button: MouseButton, at: CGPoint, count: Int)
    case drag(phase: GesturePhase, to: CGPoint)
    /// `delta` in points, content-follows-finger direction (natural). Router applies the user setting.
    case scroll(phase: GesturePhase, delta: CGVector, at: CGPoint)
    /// Velocity in points per second at lift-off.
    case scrollMomentum(velocity: CGVector, at: CGPoint)
    case cancelMomentum
    /// `delta` = distance_now / distance_prev − 1 (AppKit magnification semantics).
    case magnify(phase: GesturePhase, delta: Double, at: CGPoint)
    /// Degrees, counter-clockwise positive (AppKit rotation semantics).
    case rotate(phase: GesturePhase, degrees: Double, at: CGPoint)
    case swipe(fingers: Int, direction: SwipeDirection)
}
```

- [ ] **Step 4: Write GestureConfig.swift**

```swift
import Foundation

/// Gesture thresholds. Durations in seconds, distances in points, velocities in points per second.
public struct GestureConfig: Codable, Equatable, Sendable {
    public var tapMaxDuration: Double = 0.25
    public var tapMaxMovement: Double = 8
    public var doubleTapInterval: Double = 0.30
    public var longPressDuration: Double = 0.60
    public var classifyMovement: Double = 10
    public var pinchThreshold: Double = 12
    public var rotateThreshold: Double = 8
    public var momentumMinVelocity: Double = 50
    public var momentumDecayPerFrame: Double = 0.96
    public var momentumStopVelocity: Double = 20
    public var swipeDistance: Double = 60
    public var swipeMaxDuration: Double = 0.5
    public var stuckTimeout: Double = 0.5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureConfig()
        tapMaxDuration = try c.decodeIfPresent(Double.self, forKey: .tapMaxDuration) ?? d.tapMaxDuration
        tapMaxMovement = try c.decodeIfPresent(Double.self, forKey: .tapMaxMovement) ?? d.tapMaxMovement
        doubleTapInterval = try c.decodeIfPresent(Double.self, forKey: .doubleTapInterval) ?? d.doubleTapInterval
        longPressDuration = try c.decodeIfPresent(Double.self, forKey: .longPressDuration) ?? d.longPressDuration
        classifyMovement = try c.decodeIfPresent(Double.self, forKey: .classifyMovement) ?? d.classifyMovement
        pinchThreshold = try c.decodeIfPresent(Double.self, forKey: .pinchThreshold) ?? d.pinchThreshold
        rotateThreshold = try c.decodeIfPresent(Double.self, forKey: .rotateThreshold) ?? d.rotateThreshold
        momentumMinVelocity = try c.decodeIfPresent(Double.self, forKey: .momentumMinVelocity) ?? d.momentumMinVelocity
        momentumDecayPerFrame = try c.decodeIfPresent(Double.self, forKey: .momentumDecayPerFrame) ?? d.momentumDecayPerFrame
        momentumStopVelocity = try c.decodeIfPresent(Double.self, forKey: .momentumStopVelocity) ?? d.momentumStopVelocity
        swipeDistance = try c.decodeIfPresent(Double.self, forKey: .swipeDistance) ?? d.swipeDistance
        swipeMaxDuration = try c.decodeIfPresent(Double.self, forKey: .swipeMaxDuration) ?? d.swipeMaxDuration
        stuckTimeout = try c.decodeIfPresent(Double.self, forKey: .stuckTimeout) ?? d.stuckTimeout
    }
}
```

- [ ] **Step 5: Write Geometry.swift**

```swift
import Foundation
import CoreGraphics

enum Geometry {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(b.x - a.x, b.y - a.y)
    }

    static func centroid(_ touches: [ActiveTouch]) -> CGPoint {
        guard !touches.isEmpty else { return .zero }
        let sum = touches.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.position.x, y: $0.y + $1.position.y) }
        return CGPoint(x: sum.x / Double(touches.count), y: sum.y / Double(touches.count))
    }

    static func pairDistance(_ touches: [ActiveTouch]) -> Double {
        distance(touches[0].position, touches[1].position)
    }

    /// Angle of the vector from touch 0 to touch 1 in degrees, screen coordinates (y down).
    static func pairAngle(_ touches: [ActiveTouch]) -> Double {
        let a = touches[0].position, b = touches[1].position
        return atan2(b.y - a.y, b.x - a.x) * 180 / .pi
    }

    /// Shortest signed difference `to − from`, normalized to (−180, 180].
    static func angleDelta(from: Double, to: Double) -> Double {
        var d = to - from
        while d > 180 { d -= 360 }
        while d <= -180 { d += 360 }
        return d
    }

    /// Seconds between two monotonic nanosecond timestamps; 0 when `to` is not after `from`.
    static func seconds(from: UInt64, to: UInt64) -> Double {
        to > from ? Double(to - from) / 1_000_000_000 : 0
    }
}
```

- [ ] **Step 6: Write GestureEngine.swift (one-finger logic, other branches stubbed)**

```swift
import Foundation
import CoreGraphics

/// Deterministic gesture state machine. Time comes only from the `timestamp` arguments.
public struct GestureEngine: Sendable {
    public var config: GestureConfig

    enum State: Equatable {
        case idle
        case oneFinger(id: Int, start: CGPoint, last: CGPoint, startTime: UInt64)
        case dragging(id: Int, last: CGPoint)
        case twoPending(startCentroid: CGPoint, startDistance: Double, startAngle: Double, startTime: UInt64, last: CGPoint)
        case twoReleasing(startCentroid: CGPoint, startTime: UInt64)
        case scrolling(prevCentroid: CGPoint, prevTime: UInt64, velocity: CGVector)
        case pinching(prevDistance: Double, last: CGPoint)
        case rotating(prevAngle: Double, last: CGPoint)
        case multiPending(count: Int, startCentroid: CGPoint, startTime: UInt64)
        /// Fingers are down but nothing more will be recognized until all lift.
        case consumed
    }

    struct TapRecord: Equatable {
        var time: UInt64
        var position: CGPoint
    }

    private(set) var state: State = .idle
    private var lastTap: TapRecord?
    private var momentumMayBeRunning = false

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    public var isIdle: Bool { state == .idle }

    public mutating func update(touches: [ActiveTouch], timestamp: UInt64) -> [Action] {
        let n = touches.count
        if case .consumed = state {
            if n == 0 { state = .idle }
            return []
        }
        if n == expectedCount {
            return continueGesture(touches, timestamp)
        }
        let (actions, enter) = finishGesture(newCount: n, timestamp: timestamp)
        return enter ? actions + self.enter(touches, timestamp) : actions
    }

    public mutating func tick(_ timestamp: UInt64) -> [Action] {
        switch state {
        case .oneFinger(_, _, let last, let startTime):
            if Geometry.seconds(from: startTime, to: timestamp) >= config.longPressDuration {
                state = .consumed
                return [.click(button: .right, at: last, count: 1)]
            }
        case .twoReleasing(_, let startTime):
            if Geometry.seconds(from: startTime, to: timestamp) > config.tapMaxDuration { state = .consumed }
        case .multiPending(_, _, let startTime):
            if Geometry.seconds(from: startTime, to: timestamp) > config.swipeMaxDuration { state = .consumed }
        default:
            break
        }
        return []
    }

    /// Ends any open gesture and returns to idle. Used on device loss, display changes and sleep.
    public mutating func reset() -> [Action] {
        let actions: [Action]
        switch state {
        case .dragging(_, let last): actions = [.drag(phase: .cancelled, to: last)]
        case .scrolling(let prev, _, _): actions = [.scroll(phase: .ended, delta: .zero, at: prev)]
        case .pinching(_, let last): actions = [.magnify(phase: .ended, delta: 0, at: last)]
        case .rotating(_, let last): actions = [.rotate(phase: .ended, degrees: 0, at: last)]
        default: actions = []
        }
        state = .idle
        lastTap = nil
        return actions
    }

    // MARK: - Finger-count bookkeeping

    private var expectedCount: Int {
        switch state {
        case .idle: return 0
        case .oneFinger, .dragging, .twoReleasing: return 1
        case .twoPending, .scrolling, .pinching, .rotating: return 2
        case .multiPending(let count, _, _): return count
        case .consumed: return -1
        }
    }

    /// Finishes the current gesture for a changed finger count. Returns the actions and whether `enter` should run.
    private mutating func finishGesture(newCount n: Int, timestamp: UInt64) -> ([Action], Bool) {
        switch state {
        case .idle:
            return ([], true)
        case .oneFinger(_, _, let last, let startTime):
            if n == 0 {
                state = .idle
                return (tapActions(at: last, touchStart: startTime, timestamp: timestamp), false)
            }
            return ([], true)
        case .dragging(_, let last):
            state = .idle
            return ([.drag(phase: .ended, to: last)], n > 0)
        case .twoPending, .twoReleasing, .scrolling, .pinching, .rotating:
            return finishTwoFinger(newCount: n, timestamp: timestamp)
        case .multiPending:
            return finishMulti(newCount: n)
        case .consumed:
            state = n == 0 ? .idle : .consumed
            return ([], false)
        }
    }

    // Replaced in Task 8.
    private mutating func finishTwoFinger(newCount n: Int, timestamp: UInt64) -> ([Action], Bool) {
        state = n == 0 ? .idle : .consumed
        return ([], false)
    }

    // Replaced in Task 9.
    private mutating func finishMulti(newCount n: Int) -> ([Action], Bool) {
        state = n == 0 ? .idle : .consumed
        return ([], false)
    }

    private mutating func enter(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        var out: [Action] = []
        if momentumMayBeRunning && !touches.isEmpty {
            out.append(.cancelMomentum)
            momentumMayBeRunning = false
        }
        switch touches.count {
        case 0:
            state = .idle
        case 1:
            let t = touches[0]
            state = .oneFinger(id: t.id, start: t.position, last: t.position, startTime: timestamp)
            out.append(.moveCursor(to: t.position))
        case 2:
            enterTwoFinger(touches, timestamp)
        case 3, 4:
            enterMulti(touches, timestamp)
        default:
            state = .consumed
        }
        return out
    }

    // Replaced in Task 8.
    private mutating func enterTwoFinger(_ touches: [ActiveTouch], _ timestamp: UInt64) {
        state = .consumed
    }

    // Replaced in Task 9.
    private mutating func enterMulti(_ touches: [ActiveTouch], _ timestamp: UInt64) {
        state = .consumed
    }

    // MARK: - Same finger count

    private mutating func continueGesture(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        switch state {
        case .idle, .consumed, .twoReleasing:
            return []
        case .oneFinger(let id, let start, _, let startTime):
            let p = touches[0].position
            if Geometry.distance(p, start) > config.tapMaxMovement {
                state = .dragging(id: id, last: p)
                return [.drag(phase: .began, to: start), .drag(phase: .changed, to: p)]
            }
            if Geometry.seconds(from: startTime, to: timestamp) >= config.longPressDuration {
                state = .consumed
                return [.click(button: .right, at: p, count: 1)]
            }
            state = .oneFinger(id: id, start: start, last: p, startTime: startTime)
            return []
        case .dragging(let id, _):
            let p = touches[0].position
            state = .dragging(id: id, last: p)
            return [.drag(phase: .changed, to: p)]
        case .twoPending, .scrolling, .pinching, .rotating:
            return continueTwoFinger(touches, timestamp)
        case .multiPending:
            return continueMulti(touches, timestamp)
        }
    }

    // Replaced in Task 8.
    private mutating func continueTwoFinger(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        []
    }

    // Replaced in Task 9.
    private mutating func continueMulti(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        []
    }

    // MARK: - Taps

    private mutating func tapActions(at position: CGPoint, touchStart: UInt64, timestamp: UInt64) -> [Action] {
        var count = 1
        if let previous = lastTap,
           Geometry.seconds(from: previous.time, to: touchStart) <= config.doubleTapInterval,
           Geometry.distance(previous.position, position) <= config.tapMaxMovement {
            count = 2
            lastTap = nil
        } else {
            lastTap = TapRecord(time: timestamp, position: position)
        }
        return [.click(button: .left, at: position, count: count)]
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter GestureEngineOneFingerTests`
Expected: 10 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/TouchCore/Gesture Tests/TouchCoreTests/GestureEngineOneFingerTests.swift
git commit -m "feat(core): gesture engine with tap, double tap, drag and long-press right click"
```

---

### Task 8: Gesture engine, two fingers

**Files:**
- Modify: `Sources/TouchCore/Gesture/GestureEngine.swift` (replace `enterTwoFinger`, `continueTwoFinger`, `finishTwoFinger`)
- Test: `Tests/TouchCoreTests/GestureEngineTwoFingerTests.swift`

**Interfaces:**
- Consumes: everything from Task 7.
- Produces: scroll/pinch/rotate/two-finger-tap behaviour of `GestureEngine.update` and `tick`; no new types.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
@testable import TouchCore

@Suite struct GestureEngineTwoFingerTests {
    func pair(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> [ActiveTouch] {
        [touch(1, ax, ay), touch(2, bx, by)]
    }

    @Test func twoFingerTapIsRightClick() {
        var e = GestureEngine()
        #expect(e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(100)) == [.click(button: .right, at: pt(120, 100), count: 1)])
        #expect(e.isIdle)
    }

    @Test func staggeredTwoFingerTapIsRightClick() {
        var e = GestureEngine()
        #expect(e.update(touches: [touch(1, 100, 100)], timestamp: ms(0)) == [.moveCursor(to: pt(100, 100))])
        #expect(e.update(touches: pair(100, 100, 140, 100), timestamp: ms(40)).isEmpty)
        #expect(e.update(touches: [touch(2, 140, 100)], timestamp: ms(120)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(150)) == [.click(button: .right, at: pt(120, 100), count: 1)])
    }

    @Test func twoFingerHoldThenLiftIsNothing() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(300))
        #expect(e.update(touches: [], timestamp: ms(500)).isEmpty)
    }

    @Test func twoReleasingExpiresViaTick() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: [touch(2, 140, 100)], timestamp: ms(100))
        _ = e.tick(ms(400))
        #expect(e.update(touches: [], timestamp: ms(450)).isEmpty)
    }

    @Test func scrollClassificationAndMomentum() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        #expect(e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30)) == [
            .scroll(phase: .began, delta: .zero, at: pt(120, 115)),
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 15), at: pt(120, 115)),
        ])
        #expect(e.update(touches: pair(100, 125, 140, 125), timestamp: ms(60)) == [
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 10), at: pt(120, 125)),
        ])
        let lift = e.update(touches: [], timestamp: ms(90))
        #expect(lift.count == 2)
        #expect(lift[0] == .scroll(phase: .ended, delta: .zero, at: pt(120, 125)))
        guard case .scrollMomentum(let v, let at) = lift[1] else { Issue.record("expected momentum"); return }
        #expect(abs(v.dy - 333.33) < 0.5)
        #expect(v.dx == 0)
        #expect(at == pt(120, 125))
        #expect(e.isIdle)
    }

    @Test func slowScrollHasNoMomentum() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 112, 140, 112), timestamp: ms(500))
        _ = e.update(touches: pair(100, 113, 140, 113), timestamp: ms(1000))   // 2 pt/s
        #expect(e.update(touches: [], timestamp: ms(1100)) == [.scroll(phase: .ended, delta: .zero, at: pt(120, 113))])
    }

    @Test func duplicateTimestampKeepsVelocity() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        _ = e.update(touches: pair(100, 125, 140, 125), timestamp: ms(60))      // 333 pt/s
        #expect(e.update(touches: pair(100, 130, 140, 130), timestamp: ms(60)) == [
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 5), at: pt(120, 130)),
        ])
        let lift = e.update(touches: [], timestamp: ms(50))   // earlier than before: still no crash
        guard case .scrollMomentum(let v, _) = lift[1] else { Issue.record("expected momentum"); return }
        #expect(abs(v.dy - 333.33) < 0.5)
    }

    @Test func newTouchCancelsMomentum() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        _ = e.update(touches: [], timestamp: ms(60))
        #expect(e.update(touches: [touch(5, 300, 300)], timestamp: ms(200)) == [.cancelMomentum, .moveCursor(to: pt(300, 300))])
        _ = e.update(touches: [], timestamp: ms(250))
        #expect(e.update(touches: [touch(6, 300, 300)], timestamp: ms(400)) == [.moveCursor(to: pt(300, 300))])
    }

    @Test func pinchClassification() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))          // distance 40
        let first = e.update(touches: pair(90, 100, 160, 100), timestamp: ms(30))  // distance 70
        #expect(first.count == 2)
        #expect(first[0] == .magnify(phase: .began, delta: 0, at: pt(125, 100)))
        guard case .magnify(.changed, let d1, let at1) = first[1] else { Issue.record("expected magnify"); return }
        #expect(abs(d1 - 0.75) < 1e-9)
        #expect(at1 == pt(125, 100))
        let second = e.update(touches: pair(80, 100, 170, 100), timestamp: ms(60)) // distance 90
        guard case .magnify(.changed, let d2, _) = second[0] else { Issue.record("expected magnify"); return }
        #expect(abs(d2 - (90.0 / 70.0 - 1)) < 1e-9)
        #expect(e.update(touches: [], timestamp: ms(90)) == [.magnify(phase: .ended, delta: 0, at: pt(125, 100))])
    }

    @Test func pinchInIsNegative() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 200, 100), timestamp: ms(0))
        let out = e.update(touches: pair(120, 100, 180, 100), timestamp: ms(30))
        guard case .magnify(.changed, let d, _) = out[1] else { Issue.record("expected magnify"); return }
        #expect(d < 0)
    }

    @Test func rotateClassificationCounterClockwisePositive() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 200, 100), timestamp: ms(0))
        let first = e.update(touches: pair(100, 100, 200, 80), timestamp: ms(30))   // finger 2 moves up on screen
        #expect(first[0] == .rotate(phase: .began, degrees: 0, at: pt(150, 90)))
        guard case .rotate(.changed, let deg1, _) = first[1] else { Issue.record("expected rotate"); return }
        #expect(abs(deg1 - 11.31) < 0.05)
        let second = e.update(touches: pair(100, 100, 200, 60), timestamp: ms(60))
        guard case .rotate(.changed, let deg2, _) = second[0] else { Issue.record("expected rotate"); return }
        #expect(abs(deg2 - 10.49) < 0.05)
        #expect(e.update(touches: [], timestamp: ms(90)) == [.rotate(phase: .ended, degrees: 0, at: pt(150, 80))])
    }

    @Test func pinchWinsWhenBothThresholdsExceeded() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        let out = e.update(touches: pair(80, 120, 160, 120), timestamp: ms(30))   // spread 40 and moved 20
        guard case .magnify = out[0] else { Issue.record("expected magnify first"); return }
    }

    @Test func secondFingerDuringDragEndsDrag() {
        var e = GestureEngine()
        _ = e.update(touches: [touch(1, 100, 100)], timestamp: ms(0))
        _ = e.update(touches: [touch(1, 130, 100)], timestamp: ms(30))
        #expect(e.update(touches: pair(130, 100, 170, 100), timestamp: ms(60)) == [.drag(phase: .ended, to: pt(130, 100))])
        _ = e.update(touches: pair(130, 120, 170, 120), timestamp: ms(90))
        #expect(e.update(touches: pair(130, 130, 170, 130), timestamp: ms(120)) == [
            .scroll(phase: .changed, delta: CGVector(dx: 0, dy: 10), at: pt(150, 130)),
        ])
    }

    @Test func liftingOneFingerDuringScrollConsumesTheOther() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        let out = e.update(touches: [touch(2, 140, 115)], timestamp: ms(60))
        #expect(out[0] == .scroll(phase: .ended, delta: .zero, at: pt(120, 115)))
        #expect(e.update(touches: [touch(2, 140, 300)], timestamp: ms(90)).isEmpty)
        #expect(e.update(touches: [], timestamp: ms(120)).isEmpty)
        #expect(e.isIdle)
    }

    @Test func resetEndsScrollWithoutMomentum() {
        var e = GestureEngine()
        _ = e.update(touches: pair(100, 100, 140, 100), timestamp: ms(0))
        _ = e.update(touches: pair(100, 115, 140, 115), timestamp: ms(30))
        #expect(e.reset() == [.scroll(phase: .ended, delta: .zero, at: pt(120, 115))])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GestureEngineTwoFingerTests`
Expected: `twoFingerTapIsRightClick`, `scrollClassificationAndMomentum`, `pinchClassification`, `rotateClassification…` and others FAIL (stubs return nothing and go to `consumed`).

- [ ] **Step 3: Replace the three two-finger stubs in GestureEngine.swift**

Replace `enterTwoFinger`:
```swift
    private mutating func enterTwoFinger(_ touches: [ActiveTouch], _ timestamp: UInt64) {
        let c = Geometry.centroid(touches)
        state = .twoPending(startCentroid: c,
                            startDistance: Geometry.pairDistance(touches),
                            startAngle: Geometry.pairAngle(touches),
                            startTime: timestamp,
                            last: c)
    }
```

Replace `continueTwoFinger`:
```swift
    private mutating func continueTwoFinger(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        let c = Geometry.centroid(touches)
        let d = Geometry.pairDistance(touches)
        let a = Geometry.pairAngle(touches)
        switch state {
        case .twoPending(let c0, let d0, let a0, let startTime, _):
            if abs(d - d0) >= config.pinchThreshold {
                state = .pinching(prevDistance: d, last: c)
                return [.magnify(phase: .began, delta: 0, at: c),
                        .magnify(phase: .changed, delta: d0 > 0 ? d / d0 - 1 : 0, at: c)]
            }
            let da = Geometry.angleDelta(from: a0, to: a)
            if abs(da) >= config.rotateThreshold {
                state = .rotating(prevAngle: a, last: c)
                return [.rotate(phase: .began, degrees: 0, at: c),
                        .rotate(phase: .changed, degrees: -da, at: c)]
            }
            let move = CGVector(dx: c.x - c0.x, dy: c.y - c0.y)
            if hypot(move.dx, move.dy) >= config.classifyMovement {
                let dt = Geometry.seconds(from: startTime, to: timestamp)
                let v = dt > 0 ? CGVector(dx: move.dx / dt, dy: move.dy / dt) : .zero
                state = .scrolling(prevCentroid: c, prevTime: timestamp, velocity: v)
                return [.scroll(phase: .began, delta: .zero, at: c),
                        .scroll(phase: .changed, delta: move, at: c)]
            }
            state = .twoPending(startCentroid: c0, startDistance: d0, startAngle: a0, startTime: startTime, last: c)
            return []
        case .scrolling(let prev, let prevTime, let v0):
            let delta = CGVector(dx: c.x - prev.x, dy: c.y - prev.y)
            let dt = Geometry.seconds(from: prevTime, to: timestamp)
            let v = dt > 0 ? CGVector(dx: delta.dx / dt, dy: delta.dy / dt) : v0
            state = .scrolling(prevCentroid: c, prevTime: dt > 0 ? timestamp : prevTime, velocity: v)
            return [.scroll(phase: .changed, delta: delta, at: c)]
        case .pinching(let d0, _):
            state = .pinching(prevDistance: d, last: c)
            return [.magnify(phase: .changed, delta: d0 > 0 ? d / d0 - 1 : 0, at: c)]
        case .rotating(let a0, _):
            state = .rotating(prevAngle: a, last: c)
            return [.rotate(phase: .changed, degrees: -Geometry.angleDelta(from: a0, to: a), at: c)]
        default:
            return []
        }
    }
```

Replace `finishTwoFinger`:
```swift
    private mutating func finishTwoFinger(newCount n: Int, timestamp: UInt64) -> ([Action], Bool) {
        switch state {
        case .twoPending(let c, _, _, let startTime, _):
            if n == 0 {
                state = .idle
                let isTap = Geometry.seconds(from: startTime, to: timestamp) <= config.tapMaxDuration
                return (isTap ? [.click(button: .right, at: c, count: 1)] : [], false)
            }
            if n == 1 {
                state = .twoReleasing(startCentroid: c, startTime: startTime)
                return ([], false)
            }
            state = .idle
            return ([], true)
        case .twoReleasing(let c, let startTime):
            if n == 0 {
                state = .idle
                let isTap = Geometry.seconds(from: startTime, to: timestamp) <= config.tapMaxDuration
                return (isTap ? [.click(button: .right, at: c, count: 1)] : [], false)
            }
            state = .idle
            return ([], true)
        case .scrolling(let prev, _, let v):
            var out: [Action] = [.scroll(phase: .ended, delta: .zero, at: prev)]
            if hypot(v.dx, v.dy) >= config.momentumMinVelocity {
                out.append(.scrollMomentum(velocity: v, at: prev))
                momentumMayBeRunning = true
            }
            return settle(after: n, out)
        case .pinching(_, let last):
            return settle(after: n, [.magnify(phase: .ended, delta: 0, at: last)])
        case .rotating(_, let last):
            return settle(after: n, [.rotate(phase: .ended, degrees: 0, at: last)])
        default:
            state = n == 0 ? .idle : .consumed
            return ([], false)
        }
    }

    /// After a two-finger gesture ended with `n` fingers remaining: none → idle, one → consumed, three or more → re-enter.
    private mutating func settle(after n: Int, _ actions: [Action]) -> ([Action], Bool) {
        if n == 0 { state = .idle; return (actions, false) }
        if n == 1 { state = .consumed; return (actions, false) }
        state = .idle
        return (actions, true)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "GestureEngine"`
Expected: all one-finger and two-finger tests pass (10 + 15). If `rotateClassificationCounterClockwisePositive` fails on the sign, the error is in `pairAngle`/`-da`; the convention is: finger 2 moving up on screen (smaller y) with finger 1 to its left is counter-clockwise and must be positive.

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchCore/Gesture/GestureEngine.swift Tests/TouchCoreTests/GestureEngineTwoFingerTests.swift
git commit -m "feat(core): two-finger scroll with momentum, pinch, rotate and two-finger tap"
```

---

### Task 9: Gesture engine, three and four fingers

**Files:**
- Modify: `Sources/TouchCore/Gesture/GestureEngine.swift` (replace `enterMulti`, `continueMulti`, `finishMulti`)
- Test: `Tests/TouchCoreTests/GestureEngineMultiFingerTests.swift`

**Interfaces:**
- Produces: `.swipe(fingers:direction:)` behaviour; no new types.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GestureEngineMultiFingerTests`
Expected: the swipe tests FAIL (stubs produce no `.swipe`).

- [ ] **Step 3: Replace the three multi-finger stubs in GestureEngine.swift**

```swift
    private mutating func enterMulti(_ touches: [ActiveTouch], _ timestamp: UInt64) {
        state = .multiPending(count: touches.count, startCentroid: Geometry.centroid(touches), startTime: timestamp)
    }

    private mutating func continueMulti(_ touches: [ActiveTouch], _ timestamp: UInt64) -> [Action] {
        guard case .multiPending(let count, let c0, let startTime) = state else { return [] }
        if Geometry.seconds(from: startTime, to: timestamp) > config.swipeMaxDuration {
            state = .consumed
            return []
        }
        let c = Geometry.centroid(touches)
        let dx = c.x - c0.x
        let dy = c.y - c0.y
        guard hypot(dx, dy) >= config.swipeDistance else { return [] }
        state = .consumed
        let direction: SwipeDirection
        if abs(dx) >= abs(dy) {
            direction = dx > 0 ? .right : .left
        } else {
            direction = dy > 0 ? .down : .up
        }
        return [.swipe(fingers: count, direction: direction)]
    }

    private mutating func finishMulti(newCount n: Int) -> ([Action], Bool) {
        guard case .multiPending(let count, _, _) = state else { return ([], false) }
        if n == 0 { state = .idle; return ([], false) }
        if n > count { state = .idle; return ([], true) }   // re-enter with more fingers (or consumed for 5+)
        state = .consumed
        return ([], false)
    }
```

- [ ] **Step 4: Run all engine tests**

Run: `swift test --filter "GestureEngine"`
Expected: 10 + 15 + 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchCore/Gesture/GestureEngine.swift Tests/TouchCoreTests/GestureEngineMultiFingerTests.swift
git commit -m "feat(core): three and four finger swipes"
```

---

### Task 10: Action router

**Files:**
- Create: `Sources/TouchCore/Routing/Command.swift`, `Sources/TouchCore/Routing/ActionRouter.swift`
- Test: `Tests/TouchCoreTests/ActionRouterTests.swift`

**Interfaces:**
- Consumes: `Action`, `GesturePhase`, `MouseButton`, `SwipeDirection`.
- Produces: `KeyCommand` (with `.missionControl`, `.appExpose`, `.spaceLeft`, `.spaceRight`), `Command` (consumed by Task 13's injector), `RouterContext`, `ActionRouter(naturalScrolling:)` with `route(_:context:) -> [Command]`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ActionRouterTests`
Expected: compile error "cannot find 'ActionRouter' in scope".

- [ ] **Step 3: Write Command.swift**

```swift
import Foundation
import CoreGraphics

/// A keyboard shortcut. `keyCode` is a macOS virtual key code (kVK_*).
public struct KeyCommand: Equatable, Sendable {
    public var keyCode: UInt16
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var command: Bool

    public init(keyCode: UInt16, control: Bool = false, option: Bool = false, shift: Bool = false, command: Bool = false) {
        self.keyCode = keyCode
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
    }

    public static let missionControl = KeyCommand(keyCode: 126, control: true) // ⌃↑
    public static let appExpose = KeyCommand(keyCode: 125, control: true)      // ⌃↓
    public static let spaceLeft = KeyCommand(keyCode: 123, control: true)      // ⌃←
    public static let spaceRight = KeyCommand(keyCode: 124, control: true)     // ⌃→
}

/// What the injector executes. Produced by `ActionRouter`.
public enum Command: Equatable, Sendable {
    case moveCursor(CGPoint)
    case click(MouseButton, CGPoint, Int)
    case drag(GesturePhase, CGPoint)
    case scroll(GesturePhase, CGVector, CGPoint)
    case scrollMomentum(CGVector, CGPoint)
    case cancelMomentum
    case magnify(GesturePhase, Double, CGPoint)
    case rotate(GesturePhase, Double, CGPoint)
    case key(KeyCommand)
}

public struct RouterContext: Equatable, Sendable {
    public var frontmostBundleID: String?

    public init(frontmostBundleID: String? = nil) {
        self.frontmostBundleID = frontmostBundleID
    }
}
```

- [ ] **Step 4: Write ActionRouter.swift**

```swift
import Foundation
import CoreGraphics

/// Maps gesture actions to commands using the default gesture set.
/// `context.frontmostBundleID` is accepted now so per-application sets can be added without changing callers.
public struct ActionRouter: Sendable {
    public var naturalScrolling: Bool

    public init(naturalScrolling: Bool = true) {
        self.naturalScrolling = naturalScrolling
    }

    public func route(_ action: Action, context: RouterContext) -> [Command] {
        let sign: Double = naturalScrolling ? 1 : -1
        switch action {
        case .moveCursor(let p):
            return [.moveCursor(p)]
        case .click(let button, let p, let count):
            return [.click(button, p, count)]
        case .drag(let phase, let p):
            return [.drag(phase, p)]
        case .scroll(let phase, let delta, let p):
            return [.scroll(phase, CGVector(dx: delta.dx * sign, dy: delta.dy * sign), p)]
        case .scrollMomentum(let v, let p):
            return [.scrollMomentum(CGVector(dx: v.dx * sign, dy: v.dy * sign), p)]
        case .cancelMomentum:
            return [.cancelMomentum]
        case .magnify(let phase, let delta, let p):
            return [.magnify(phase, delta, p)]
        case .rotate(let phase, let degrees, let p):
            return [.rotate(phase, degrees, p)]
        case .swipe(_, let direction):
            switch direction {
            case .up: return [.key(.missionControl)]
            case .down: return [.key(.appExpose)]
            case .left: return [.key(.spaceRight)]   // fingers move left → content moves left → next space
            case .right: return [.key(.spaceLeft)]
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ActionRouterTests`
Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/TouchCore/Routing Tests/TouchCoreTests/ActionRouterTests.swift
git commit -m "feat(core): route actions to commands with default gesture set"
```

---

### Task 11: Settings and settings store

**Files:**
- Create: `Sources/TouchCore/Settings/Settings.swift`, `Sources/TouchCore/Settings/SettingsStore.swift`
- Test: `Tests/TouchCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `GestureConfig`, `Calibration`.
- Produces: `DisplaySelection`, `Settings` (with `init()` defaults), `SettingsStore(directory:)` with `fileURL`, `load() -> Settings`, `save(_:) throws`, `static defaultDirectory() -> URL`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import TouchCore

@Suite struct SettingsStoreTests {
    func temporaryStore() throws -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TouchBridgeTests-\(UUID().uuidString)")
        return SettingsStore(directory: dir)
    }

    @Test func missingFileYieldsDefaultsWithoutCreatingIt() throws {
        let store = try temporaryStore()
        #expect(store.load() == Settings())
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func roundTrip() throws {
        let store = try temporaryStore()
        var s = Settings()
        s.enabled = false
        s.displaySelection = .display(uuid: "ABC-123")
        s.naturalScrolling = false
        s.gesture.tapMaxMovement = 11
        s.calibrations["20231224X1"] = Calibration(orientation: 90, scaleX: 1, scaleY: 1, offsetX: 0.01, offsetY: 0)
        s.launchAtLogin = true
        try store.save(s)
        #expect(store.load() == s)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 1"))
    }

    @Test func partialFileGetsDefaults() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{\"enabled\": false}".utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.enabled == false)
        #expect(s.naturalScrolling == true)
        #expect(s.gesture == GestureConfig())
        #expect(s.displaySelection == .auto)
    }

    @Test func brokenFileIsSetAsideAndDefaultsReturned() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)
        #expect(store.load() == Settings())
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path + ".broken"))
    }

    @Test func defaultDirectoryIsApplicationSupport() {
        let url = SettingsStore.defaultDirectory()
        #expect(url.path.hasSuffix("/Library/Application Support/TouchBridge"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsStoreTests`
Expected: compile error "cannot find 'SettingsStore' in scope".

- [ ] **Step 3: Write Settings.swift**

```swift
import Foundation

public enum DisplaySelection: Codable, Equatable, Sendable {
    case auto
    case display(uuid: String)
}

public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = Settings.currentSchemaVersion
    public var enabled: Bool = true
    public var displaySelection: DisplaySelection = .auto
    public var naturalScrolling: Bool = true
    public var gesture: GestureConfig = GestureConfig()
    /// Keyed by device serial number.
    public var calibrations: [String: Calibration] = [:]
    public var launchAtLogin: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        displaySelection = try c.decodeIfPresent(DisplaySelection.self, forKey: .displaySelection) ?? d.displaySelection
        naturalScrolling = try c.decodeIfPresent(Bool.self, forKey: .naturalScrolling) ?? d.naturalScrolling
        gesture = try c.decodeIfPresent(GestureConfig.self, forKey: .gesture) ?? d.gesture
        calibrations = try c.decodeIfPresent([String: Calibration].self, forKey: .calibrations) ?? d.calibrations
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }
}
```

- [ ] **Step 4: Write SettingsStore.swift**

```swift
import Foundation

/// Reads and writes `settings.json`. Never throws on load: a missing file yields defaults,
/// an unreadable file is moved to `settings.json.broken` and defaults are returned.
public struct SettingsStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TouchBridge", isDirectory: true)
    }

    public var fileURL: URL {
        directory.appendingPathComponent("settings.json")
    }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            let broken = URL(fileURLWithPath: fileURL.path + ".broken")
            try? FileManager.default.removeItem(at: broken)
            try? FileManager.default.moveItem(at: fileURL, to: broken)
            return Settings()
        }
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: 5 tests pass.

- [ ] **Step 6: Run the whole core suite and commit**

Run: `swift test`
Expected: all TouchCore tests pass (≈ 70).

```bash
git add Sources/TouchCore/Settings Tests/TouchCoreTests/SettingsStoreTests.swift
git commit -m "feat(core): settings model and JSON store with broken-file recovery"
```

---

### Task 12: Device manager, hidrecord CLI and the seize spike

**Files:**
- Create: `Sources/TouchCore/HID/ReportFraming.swift`
- Replace: `Sources/TouchDevice/DeviceEvent.swift`, `Sources/hidrecord/main.swift`
- Create: `Sources/TouchDevice/DeviceManager.swift`
- Create (recorded): `Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl`
- Test: `Tests/TouchCoreTests/ReportFramingTests.swift`, `Tests/TouchCoreTests/RecordedReportTests.swift`

**Interfaces:**
- Consumes: `HIDDescriptorParser`, `TouchScreenLayout`, `ReportDecoder`, `TouchFrame`.
- Produces: `ReportFraming.payload(from:reportID:layout:) -> [UInt8]?`; `DeviceID = UInt64`, `DeviceInfo`, `DeviceOpenMode`, `DeviceEvent` (`.attached(id:info:mode:)`, `.openFailed(id:info:status:)`, `.report(id:reportID:raw:timestamp:)`, `.detached(id:)`), `DeviceManager(preferExclusive:sink:)` with `start()`, `stop()`. Used by Task 15.

- [ ] **Step 1: Write the failing framing tests**

`Tests/TouchCoreTests/ReportFramingTests.swift`:
```swift
import Testing
@testable import TouchCore

@Suite struct ReportFramingTests {
    @Test func stripsLeadingReportID() throws {
        let layout = try Fixtures.elanLayout()
        let raw = [UInt8(1)] + ElanReport.payload(contacts: [.init(id: 1, x: 5, y: 5, down: true)], count: 1)
        #expect(ReportFraming.payload(from: raw, reportID: 1, layout: layout)?.count == 55)
        #expect(ReportFraming.payload(from: raw, reportID: 1, layout: layout)?.first == 0x41)
    }

    @Test func keepsPayloadWithoutReportID() throws {
        let layout = try Fixtures.elanLayout()
        let raw = ElanReport.payload(contacts: [.init(id: 1, x: 5, y: 5, down: true)], count: 1)   // first byte 0x41 ≠ 1
        #expect(ReportFraming.payload(from: raw, reportID: 1, layout: layout) == raw)
    }

    @Test func rejectsShortReports() throws {
        let layout = try Fixtures.elanLayout()
        #expect(ReportFraming.payload(from: [UInt8](repeating: 0, count: 10), reportID: 1, layout: layout) == nil)
    }

    @Test func layoutWithoutIDsNeverStrips() throws {
        let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(SyntheticDescriptors.twoFingerNoReportID))
        let raw: [UInt8] = [0x00, 0x23, 0x01, 0x45, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]
        #expect(ReportFraming.payload(from: raw, reportID: 0, layout: layout) == raw)
    }
}
```

- [ ] **Step 2: Run to verify failure, then write ReportFraming.swift**

Run: `swift test --filter ReportFramingTests` → compile error.

`Sources/TouchCore/HID/ReportFraming.swift`:
```swift
import Foundation

/// IOKit delivers the report as sent on the wire. When the descriptor uses report IDs the first byte is the ID.
public enum ReportFraming {
    /// Returns the payload without the report ID byte, or nil when the report is too short for the layout.
    public static func payload(from raw: [UInt8], reportID: UInt8, layout: TouchScreenLayout) -> [UInt8]? {
        if layout.usesReportIDs, raw.count >= layout.payloadByteCount + 1, raw[0] == reportID {
            return Array(raw.dropFirst())
        }
        if raw.count >= layout.payloadByteCount {
            return raw
        }
        return nil
    }
}
```

Run: `swift test --filter ReportFramingTests` → 4 tests pass.

- [ ] **Step 3: Write DeviceEvent.swift (replacing the placeholder)**

```swift
import Foundation
import TouchCore

/// IORegistry entry ID of the HID device; stable while the device stays attached.
public typealias DeviceID = UInt64

public struct DeviceInfo: Equatable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var manufacturer: String
    public var product: String
    public var serial: String
    public var descriptor: [UInt8]
    public var maxInputReportSize: Int

    public init(vendorID: Int, productID: Int, manufacturer: String, product: String, serial: String,
                descriptor: [UInt8], maxInputReportSize: Int) {
        self.vendorID = vendorID
        self.productID = productID
        self.manufacturer = manufacturer
        self.product = product
        self.serial = serial
        self.descriptor = descriptor
        self.maxInputReportSize = maxInputReportSize
    }
}

public enum DeviceOpenMode: Sendable, Equatable {
    case exclusive, shared
}

public enum DeviceEvent: Sendable {
    case attached(id: DeviceID, info: DeviceInfo, mode: DeviceOpenMode)
    case openFailed(id: DeviceID, info: DeviceInfo, status: Int32)
    /// `raw` is the report exactly as IOKit delivered it (report ID byte included when the device uses IDs).
    case report(id: DeviceID, reportID: UInt8, raw: [UInt8], timestamp: UInt64)
    case detached(id: DeviceID)
}
```

- [ ] **Step 4: Write DeviceManager.swift**

```swift
import Foundation
import IOKit
import IOKit.hid
import os
import TouchCore

/// Finds HID touch screens (usage page 0x0D, usage 0x04), opens them exclusively and delivers raw input reports.
/// Runs its own thread with a CFRunLoop; `sink` is called on that thread.
public final class DeviceManager: @unchecked Sendable {
    public typealias Sink = @Sendable (DeviceEvent) -> Void

    private final class Entry {
        let device: IOHIDDevice
        let buffer: UnsafeMutablePointer<UInt8>
        let bufferSize: Int
        let id: DeviceID
        weak var manager: DeviceManager?

        init(device: IOHIDDevice, bufferSize: Int, id: DeviceID, manager: DeviceManager) {
            self.device = device
            self.bufferSize = bufferSize
            self.buffer = .allocate(capacity: bufferSize)
            self.buffer.initialize(repeating: 0, count: bufferSize)
            self.id = id
            self.manager = manager
        }

        deinit { buffer.deallocate() }
    }

    private let sink: Sink
    private let preferExclusive: Bool
    private let logger = Logger(subsystem: "org.touchbridge", category: "device")
    private let lock = NSLock()
    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var entries: [DeviceID: Entry] = [:]

    public init(preferExclusive: Bool = true, sink: @escaping Sink) {
        self.preferExclusive = preferExclusive
        self.sink = sink
    }

    public func start() {
        let thread = Thread { [self] in
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = manager
            self.runLoop = CFRunLoopGetCurrent()
            let matching: [String: Any] = [
                kIOHIDPrimaryUsagePageKey: Int(HIDUsage.touchScreen.page),
                kIOHIDPrimaryUsageKey: Int(HIDUsage.touchScreen.id),
            ]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
                guard let context else { return }
                Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
            }, context)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
                guard let context else { return }
                Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
            }, context)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            // IOHIDManagerOpen is deliberately not called: devices are opened one by one so that each can be seized.
            self.logger.info("HID manager scheduled")
            CFRunLoopRun()
            self.logger.info("HID thread finished")
        }
        thread.name = "org.touchbridge.hid"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    public func stop() {
        guard let runLoop, let manager else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            let current = lock.withLock { entries }
            for (_, entry) in current {
                IOHIDDeviceRegisterInputReportCallback(entry.device, entry.buffer, entry.bufferSize, nil, nil)
                IOHIDDeviceClose(entry.device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            lock.withLock { entries.removeAll() }
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
        self.runLoop = nil
        self.manager = nil
    }

    // MARK: - Callbacks (HID thread)

    private func deviceMatched(_ device: IOHIDDevice) {
        let id = Self.registryID(of: device)
        let info = Self.info(of: device)
        var mode = DeviceOpenMode.exclusive
        var status: IOReturn = kIOReturnUnsupported
        if preferExclusive {
            status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if status != kIOReturnSuccess {
                logger.error("exclusive open of \(info.product, privacy: .public) failed: 0x\(String(status, radix: 16), privacy: .public); falling back to shared")
            }
        }
        if status != kIOReturnSuccess {
            mode = .shared
            status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        guard status == kIOReturnSuccess else {
            logger.error("open of \(info.product, privacy: .public) failed: 0x\(String(status, radix: 16), privacy: .public)")
            sink(.openFailed(id: id, info: info, status: status))
            return
        }
        let entry = Entry(device: device, bufferSize: max(info.maxInputReportSize, 64), id: id, manager: self)
        lock.withLock { entries[id] = entry }
        let context = Unmanaged.passUnretained(entry).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, entry.buffer, entry.bufferSize, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let entry = Unmanaged<Entry>.fromOpaque(context).takeUnretainedValue()
            entry.manager?.deliver(entry: entry, reportID: UInt8(truncatingIfNeeded: reportID), report: report, length: length)
        }, context)
        logger.info("attached \(info.product, privacy: .public) serial \(info.serial, privacy: .public) mode \(mode == .exclusive ? "exclusive" : "shared", privacy: .public)")
        sink(.attached(id: id, info: info, mode: mode))
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let id = Self.registryID(of: device)
        let entry = lock.withLock { entries.removeValue(forKey: id) }
        guard let entry else { return }
        IOHIDDeviceRegisterInputReportCallback(entry.device, entry.buffer, entry.bufferSize, nil, nil)
        IOHIDDeviceClose(entry.device, IOOptionBits(kIOHIDOptionsTypeNone))
        logger.info("detached device \(id, privacy: .public)")
        sink(.detached(id: id))
    }

    private func deliver(entry: Entry, reportID: UInt8, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length > 0 else { return }
        let timestamp = DispatchTime.now().uptimeNanoseconds
        let raw = Array(UnsafeBufferPointer(start: report, count: length))
        sink(.report(id: entry.id, reportID: reportID, raw: raw, timestamp: timestamp))
    }

    // MARK: - Properties

    private static func registryID(of device: IOHIDDevice) -> DeviceID {
        var id: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        if service != IO_OBJECT_NULL {
            IORegistryEntryGetRegistryEntryID(service, &id)
        }
        return id
    }

    private static func info(of device: IOHIDDevice) -> DeviceInfo {
        func int(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        func string(_ key: String) -> String {
            IOHIDDeviceGetProperty(device, key as CFString) as? String ?? ""
        }
        let descriptor = (IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data).map { [UInt8]($0) } ?? []
        return DeviceInfo(
            vendorID: int(kIOHIDVendorIDKey),
            productID: int(kIOHIDProductIDKey),
            manufacturer: string(kIOHIDManufacturerKey),
            product: string(kIOHIDProductKey),
            serial: string(kIOHIDSerialNumberKey),
            descriptor: descriptor,
            maxInputReportSize: int(kIOHIDMaxInputReportSizeKey)
        )
    }
}
```

- [ ] **Step 5: Write hidrecord/main.swift (replacing the placeholder)**

```swift
import Foundation
import TouchCore
import TouchDevice

let usage = """
usage: hidrecord [--shared] [--seconds N] [--out file.jsonl]
  --shared     open the device non-exclusively (default: exclusive / seize)
  --seconds N  stop after N seconds (default: run until Ctrl-C)
  --out FILE   write every raw report as a JSON line {"t":ns,"id":reportID,"hex":"..."}
"""

struct Options {
    var shared = false
    var seconds: Double?
    var out: String?
}

var options = Options()
var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let argument = iterator.next() {
    switch argument {
    case "--shared": options.shared = true
    case "--seconds": options.seconds = iterator.next().flatMap(Double.init)
    case "--out": options.out = iterator.next()
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        print("unknown argument: \(argument)\n\(usage)")
        exit(2)
    }
}

final class Recorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.touchbridge.hidrecord")
    private var layouts: [DeviceID: TouchScreenLayout] = [:]
    private var decoders: [DeviceID: ReportDecoder] = [:]
    private var lastPrint: UInt64 = 0
    private let output: FileHandle?
    private(set) var reportCount = 0

    init(outputPath: String?) {
        if let outputPath {
            FileManager.default.createFile(atPath: outputPath, contents: nil)
            output = FileHandle(forWritingAtPath: outputPath)
        } else {
            output = nil
        }
    }

    func handle(_ event: DeviceEvent) {
        queue.async { self.process(event) }
    }

    func finish() {
        queue.sync { try? output?.close() }
    }

    private func process(_ event: DeviceEvent) {
        switch event {
        case .attached(let id, let info, let mode):
            print("attached: \(info.manufacturer) \(info.product) serial \(info.serial) vid 0x\(String(info.vendorID, radix: 16)) pid 0x\(String(info.productID, radix: 16)) mode=\(mode == .exclusive ? "exclusive" : "shared")")
            do {
                let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(info.descriptor))
                layouts[id] = layout
                decoders[id] = ReportDecoder(layout: layout)
                print("layout: report \(layout.reportID), \(layout.slots.count) slots, logical \(layout.logicalMaxX)×\(layout.logicalMaxY), payload \(layout.payloadByteCount) bytes")
            } catch {
                print("descriptor not usable: \(error)")
            }
        case .openFailed(_, let info, let status):
            print("open failed for \(info.product): 0x\(String(status, radix: 16))")
        case .detached(let id):
            print("detached \(id)")
            layouts[id] = nil
            decoders[id] = nil
        case .report(let id, let reportID, let raw, let timestamp):
            reportCount += 1
            if let output {
                let hex = raw.map { String(format: "%02x", $0) }.joined()
                output.write(Data("{\"t\":\(timestamp),\"id\":\(reportID),\"hex\":\"\(hex)\"}\n".utf8))
            }
            guard let layout = layouts[id], reportID == layout.reportID,
                  let payload = ReportFraming.payload(from: raw, reportID: reportID, layout: layout),
                  let frame = decoders[id]?.decode(payload: payload, timestamp: timestamp) else { return }
            if timestamp - lastPrint > 100_000_000 {
                lastPrint = timestamp
                let contacts = frame.contacts.map { "\($0.id):(\($0.x),\($0.y))\($0.down ? "↓" : "↑")" }.joined(separator: " ")
                print("contacts=\(frame.contacts.count) \(contacts)")
            }
        }
    }
}

let recorder = Recorder(outputPath: options.out)
let manager = DeviceManager(preferExclusive: !options.shared, sink: recorder.handle)
print("waiting for a touch screen (usage page 0x0D / usage 0x04)… Ctrl-C to stop")
manager.start()

signal(SIGINT) { _ in exit(0) }

if let seconds = options.seconds {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        manager.stop()
        recorder.finish()
        print("done after \(seconds)s, \(recorder.reportCount) reports")
        exit(0)
    }
}
RunLoop.main.run()
```

- [ ] **Step 6: Build**

Run: `swift build`
Expected: success. Typical fixes: `IOHIDDeviceGetService` needs `import IOKit.hid` (present); `IORegistryEntryGetRegistryEntryID` needs `import IOKit` (present).

- [ ] **Step 7: Seize spike with the real screen (manual)**

Connect the screen. Run:
```bash
swift run hidrecord --seconds 12 --out Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl
```
First run: macOS asks for **Input Monitoring** for the terminal application (Terminal, or Code when run from the VS Code terminal). Grant it in System Settings → Privacy & Security → Input Monitoring, then run the command again.

During the 12 seconds: touch with one finger and move it (≈3 s), then touch with two fingers and move both (≈4 s), then lift.

Expected console output:
```
attached: hotlotus normal Elan serial 20231224X1 vid 0x712 pid 0xa mode=exclusive
layout: report 1, 10 slots, logical 2976×1680, payload 55 bytes
contacts=1 0:(1234,567)↓
...
contacts=2 0:(…)↓ 1:(…)↓
done after 12.0s, N reports
```
Checks:
1. `mode=exclusive` and the macOS cursor does **not** move while touching → seize works. Continue.
2. `mode=shared` → exclusive failed. Confirm Input Monitoring is granted to the terminal app, re-run. If still shared, note the hex status printed in the log (`log stream --predicate 'subsystem == "org.touchbridge"'`) and write it into `docs/notes/seize-spike.md`; Task 15 then implements Plan B (event tap) instead of relying on seize.
3. No `attached:` line within 3 s → add `IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))` directly after `IOHIDManagerScheduleWithRunLoop` in `DeviceManager.start()`, and in `deviceMatched` call `IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))` before the seize open. Re-run.
4. Report length: look at a line of the fixture; `hex` must be 112 characters (56 bytes, ID byte included) for report 1. If it is 110, IOKit strips the ID; `ReportFraming` handles both.

- [ ] **Step 8: Write the recorded-report test**

`Tests/TouchCoreTests/RecordedReportTests.swift`:
```swift
import Testing
import Foundation
@testable import TouchCore

@Suite struct RecordedReportTests {
    struct Line: Decodable {
        var t: UInt64
        var id: UInt8
        var hex: String
    }

    @Test func recordedElanSessionDecodes() throws {
        let layout = try Fixtures.elanLayout()
        var decoder = ReportDecoder(layout: layout)
        let text = try String(contentsOf: Fixtures.url("elan-two-finger", "jsonl"), encoding: .utf8)
        var frames: [TouchFrame] = []
        var lastTimestamp: UInt64 = 0
        for line in text.split(separator: "\n") where !line.isEmpty {
            let entry = try JSONDecoder().decode(Line.self, from: Data(line.utf8))
            guard entry.id == layout.reportID else { continue }
            let raw = try Fixtures.hexBytes(entry.hex)
            let payload = try #require(ReportFraming.payload(from: raw, reportID: entry.id, layout: layout))
            #expect(entry.t >= lastTimestamp)
            lastTimestamp = entry.t
            if let frame = decoder.decode(payload: payload, timestamp: entry.t) { frames.append(frame) }
        }
        #expect(frames.count > 50)
        #expect(frames.contains { $0.contacts.count >= 2 })
        for frame in frames {
            for c in frame.contacts {
                #expect((0...layout.logicalMaxX).contains(c.x))
                #expect((0...layout.logicalMaxY).contains(c.y))
                #expect(c.id < 64)
            }
        }
    }
}
```

Run: `swift test --filter RecordedReportTests`
Expected: 1 test passes. If `frames.count > 50` fails, the recording was too short; re-record with more touching.

- [ ] **Step 9: Commit**

```bash
git add Sources/TouchCore/HID/ReportFraming.swift Sources/TouchDevice Sources/hidrecord Tests/TouchCoreTests/ReportFramingTests.swift Tests/TouchCoreTests/RecordedReportTests.swift Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl
git commit -m "feat(device): exclusive HID access with hotplug, hidrecord recorder and recorded fixture"
```

---

### Task 13: Event injector

**Files:**
- Replace: `Sources/TouchInject/GestureEventFields.swift`
- Create: `Sources/TouchInject/MomentumGenerator.swift`, `Sources/TouchInject/EventInjector.swift`
- Delete: `Tests/TouchInjectTests/SmokeTests.swift`
- Test: `Tests/TouchInjectTests/MomentumGeneratorTests.swift`, `Tests/TouchInjectTests/EventBuilderTests.swift`

**Interfaces:**
- Consumes: `Command`, `KeyCommand`, `GesturePhase`, `MouseButton`.
- Produces: `MomentumGenerator(decayPerFrame:stopVelocity:frameRate:maxFrames:)` with `frames(initialVelocity:) -> [CGVector]`; `EventInjector(queue:momentum:)` with `perform(_ command: Command)` (call on `queue`), `releaseAll()`, `static marker: Int64`; internal static builders `mouseEvent`, `scrollEvent`, `gestureEvent`, `keyEvents`, `splitWholePoints`. Used by Task 15.

- [ ] **Step 1: Write the failing tests**

`Tests/TouchInjectTests/MomentumGeneratorTests.swift`:
```swift
import Testing
import CoreGraphics
@testable import TouchInject

@Suite struct MomentumGeneratorTests {
    @Test func zeroVelocityHasNoFrames() {
        #expect(MomentumGenerator().frames(initialVelocity: .zero).isEmpty)
    }

    @Test func framesDecayAndStop() {
        let g = MomentumGenerator(decayPerFrame: 0.96, stopVelocity: 20, frameRate: 60)
        let frames = g.frames(initialVelocity: CGVector(dx: 0, dy: 600))
        #expect(!frames.isEmpty)
        #expect(abs(frames[0].dy - 10) < 1e-9)                 // 600 pt/s ÷ 60 Hz
        #expect(frames[1].dy < frames[0].dy)
        #expect(frames.last!.dy * 60 > 20)                      // last emitted frame is still above stop velocity
        #expect(frames.last!.dy * 60 * 0.96 <= 20)              // the next one would not be
        #expect(frames.allSatisfy { $0.dx == 0 })
    }

    @Test func negativeDirectionIsPreserved() {
        let frames = MomentumGenerator().frames(initialVelocity: CGVector(dx: -300, dy: 0))
        #expect(frames.allSatisfy { $0.dx < 0 && $0.dy == 0 })
    }

    @Test func frameCapPreventsInfiniteSequences() {
        let g = MomentumGenerator(decayPerFrame: 1.0, stopVelocity: 20, frameRate: 60, maxFrames: 50)
        #expect(g.frames(initialVelocity: CGVector(dx: 0, dy: 600)).count == 50)
    }
}
```

`Tests/TouchInjectTests/EventBuilderTests.swift`:
```swift
import Testing
import CoreGraphics
import TouchCore
@testable import TouchInject

@Suite struct EventBuilderTests {
    let source = CGEventSource(stateID: .hidSystemState)
    let p = CGPoint(x: 3100, y: 400)

    @Test func mouseEventCarriesClickCountLocationAndMarker() throws {
        let e = try #require(EventInjector.mouseEvent(.leftMouseDown, at: p, button: .left, clickCount: 2, source: source))
        #expect(e.type == .leftMouseDown)
        #expect(e.location == p)
        #expect(e.getIntegerValueField(.mouseEventClickState) == 2)
        #expect(e.getIntegerValueField(.eventSourceUserData) == EventInjector.marker)
    }

    @Test func scrollEventFields() throws {
        let e = try #require(EventInjector.scrollEvent(delta: CGVector(dx: 3, dy: -7), at: p, phase: .changed, momentum: nil, source: source))
        #expect(e.type == .scrollWheel)
        #expect(e.location == p)
        #expect(e.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
        #expect(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -7)
        #expect(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 3)
        #expect(e.getIntegerValueField(.scrollWheelEventScrollPhase) == 2)
        #expect(e.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0)
        let m = try #require(EventInjector.scrollEvent(delta: .zero, at: p, phase: nil, momentum: EventInjector.momentumEnd, source: source))
        #expect(m.getIntegerValueField(.scrollWheelEventMomentumPhase) == 3)
        #expect(m.getIntegerValueField(.scrollWheelEventScrollPhase) == 0)
    }

    @Test func scrollPhaseValues() {
        #expect(EventInjector.scrollPhaseValue(.began) == 1)
        #expect(EventInjector.scrollPhaseValue(.changed) == 2)
        #expect(EventInjector.scrollPhaseValue(.ended) == 4)
        #expect(EventInjector.scrollPhaseValue(.cancelled) == 8)
    }

    @Test func gestureEventFields() throws {
        let z = try #require(EventInjector.gestureEvent(hidType: GestureEventFields.hidTypeZoom, phase: .changed, value: 0.25, at: p, source: source))
        #expect(z.getIntegerValueField(GestureEventFields.eventTypeField) == 29)
        #expect(z.getIntegerValueField(GestureEventFields.hidTypeField) == 8)
        #expect(abs(z.getDoubleValueField(GestureEventFields.zoomValueField) - 0.25) < 1e-9)
        #expect(z.getIntegerValueField(GestureEventFields.phaseField) == 2)
        #expect(z.flags.isEmpty)
        #expect(z.location == p)
        let r = try #require(EventInjector.gestureEvent(hidType: GestureEventFields.hidTypeRotation, phase: .ended, value: 0, at: p, source: source))
        #expect(r.getIntegerValueField(GestureEventFields.hidTypeField) == 5)
        #expect(r.getIntegerValueField(GestureEventFields.phaseField) == 4)
    }

    @Test func keyEventsAreDownUpWithFlags() {
        let events = EventInjector.keyEvents(.missionControl, source: source)
        #expect(events.count == 2)
        #expect(events[0].type == .keyDown)
        #expect(events[1].type == .keyUp)
        #expect(events[0].getIntegerValueField(.keyboardEventKeycode) == 126)
        #expect(events[0].flags.contains(.maskControl))
        #expect(!events[0].flags.contains(.maskCommand))
    }

    @Test func fractionalDeltasAccumulate() {
        var remainder = CGVector.zero
        #expect(EventInjector.splitWholePoints(CGVector(dx: 0.4, dy: -0.4), remainder: &remainder) == .zero)
        #expect(EventInjector.splitWholePoints(CGVector(dx: 0.4, dy: -0.4), remainder: &remainder) == .zero)
        #expect(EventInjector.splitWholePoints(CGVector(dx: 0.4, dy: -0.4), remainder: &remainder) == CGVector(dx: 1, dy: -1))
        #expect(abs(remainder.dx - 0.2) < 1e-9)
        #expect(abs(remainder.dy + 0.2) < 1e-9)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "MomentumGeneratorTests|EventBuilderTests"`
Expected: compile errors (types missing). Delete `Tests/TouchInjectTests/SmokeTests.swift` now (it references the placeholder).

- [ ] **Step 3: Write GestureEventFields.swift (replacing the placeholder)**

```swift
import CoreGraphics

/// Undocumented CGEvent fields used to synthesize trackpad gestures. This is the only file that may contain them.
///
/// Sources:
/// - WebKit, Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h: kCGEventGestureHIDType = 110,
///   kCGEventGestureZoomValue = 113, kCGEventGestureRotationValue = 114, kCGEventGestureSwipeValue = 115,
///   kCGEventGesturePhase = 132.
/// - IOKit, IOHIDEventTypes.h: kIOHIDEventTypeRotation = 5, kIOHIDEventTypeZoom = 8.
/// - Touch-Up (RWTH Aachen, MIT), TouchUpCore/TUCCursorUtilities.m: builds the event from a mouse-moved event and
///   additionally sets field 55 = 29 (NSEventTypeGesture), field 50 = 248 and field 101 = 4. The meaning of 50 and 101
///   is not documented; they are set because the Touch-Up recipe is known to work.
enum GestureEventFields {
    static let gestureEventType: Int64 = 29

    static let eventTypeField = field(55)
    static let subtypeField = field(50)
    static let subtypeValue: Int64 = 248
    static let field101 = field(101)
    static let field101Value: Int64 = 4
    static let hidTypeField = field(110)
    static let zoomValueField = field(113)
    static let rotationValueField = field(114)
    static let phaseField = field(132)

    static let hidTypeRotation: Int64 = 5
    static let hidTypeZoom: Int64 = 8

    static let phaseBegan: Int64 = 1
    static let phaseChanged: Int64 = 2
    static let phaseEnded: Int64 = 4
    static let phaseCancelled: Int64 = 8

    static func field(_ raw: UInt32) -> CGEventField {
        CGEventField(rawValue: raw) ?? unsafeBitCast(raw, to: CGEventField.self)
    }
}
```

- [ ] **Step 4: Write MomentumGenerator.swift**

```swift
import Foundation
import CoreGraphics

/// Produces the per-frame scroll deltas that follow a two-finger lift-off, like a trackpad's inertia.
public struct MomentumGenerator: Sendable {
    public var decayPerFrame: Double
    /// Points per second below which the sequence stops.
    public var stopVelocity: Double
    public var frameRate: Double
    public var maxFrames: Int

    public init(decayPerFrame: Double = 0.96, stopVelocity: Double = 20, frameRate: Double = 60, maxFrames: Int = 600) {
        self.decayPerFrame = decayPerFrame
        self.stopVelocity = stopVelocity
        self.frameRate = frameRate
        self.maxFrames = maxFrames
    }

    /// `initialVelocity` in points per second; result in points per frame.
    public func frames(initialVelocity: CGVector) -> [CGVector] {
        var velocity = initialVelocity
        var frames: [CGVector] = []
        while hypot(velocity.dx, velocity.dy) > stopVelocity && frames.count < maxFrames {
            frames.append(CGVector(dx: velocity.dx / frameRate, dy: velocity.dy / frameRate))
            velocity = CGVector(dx: velocity.dx * decayPerFrame, dy: velocity.dy * decayPerFrame)
        }
        return frames
    }
}
```

- [ ] **Step 5: Write EventInjector.swift**

```swift
import Foundation
import CoreGraphics
import os
import TouchCore

/// Turns `Command`s into CGEvents posted at the HID event tap. All methods must be called on `queue`.
public final class EventInjector: @unchecked Sendable {
    /// Written to `eventSourceUserData` of every posted event ("TBRG"), so an event tap can recognise our own events.
    public static let marker: Int64 = 0x5442_5247

    static let momentumBegin: Int64 = 1
    static let momentumContinue: Int64 = 2
    static let momentumEnd: Int64 = 3

    public var momentum: MomentumGenerator

    private let queue: DispatchQueue
    private let source: CGEventSource?
    private let logger = Logger(subsystem: "org.touchbridge", category: "inject")
    private var momentumTimer: DispatchSourceTimer?
    private var momentumFrames: [CGVector] = []
    private var momentumIndex = 0
    private var momentumLocation = CGPoint.zero
    private var scrollRemainder = CGVector.zero
    private var leftButtonDown = false

    public init(queue: DispatchQueue, momentum: MomentumGenerator = MomentumGenerator()) {
        self.queue = queue
        self.momentum = momentum
        self.source = CGEventSource(stateID: .hidSystemState)
    }

    public func perform(_ command: Command) {
        switch command {
        case .moveCursor(let p):
            post(Self.mouseEvent(.mouseMoved, at: p, button: .left, clickCount: 0, source: source))
        case .click(let button, let p, let count):
            let down: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
            let up: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
            let cgButton: CGMouseButton = button == .left ? .left : .right
            post(Self.mouseEvent(.mouseMoved, at: p, button: .left, clickCount: 0, source: source))
            post(Self.mouseEvent(down, at: p, button: cgButton, clickCount: count, source: source))
            post(Self.mouseEvent(up, at: p, button: cgButton, clickCount: count, source: source))
        case .drag(let phase, let p):
            switch phase {
            case .began:
                post(Self.mouseEvent(.mouseMoved, at: p, button: .left, clickCount: 0, source: source))
                post(Self.mouseEvent(.leftMouseDown, at: p, button: .left, clickCount: 1, source: source))
                leftButtonDown = true
            case .changed:
                post(Self.mouseEvent(.leftMouseDragged, at: p, button: .left, clickCount: 1, source: source))
            case .ended, .cancelled:
                post(Self.mouseEvent(.leftMouseUp, at: p, button: .left, clickCount: 1, source: source))
                leftButtonDown = false
            }
        case .scroll(let phase, let delta, let p):
            if phase == .began {
                stopMomentum(sendEnd: true)
                scrollRemainder = .zero
            }
            let whole = Self.splitWholePoints(delta, remainder: &scrollRemainder)
            post(Self.scrollEvent(delta: whole, at: p, phase: phase, momentum: nil, source: source))
        case .scrollMomentum(let velocity, let p):
            startMomentum(velocity: velocity, at: p)
        case .cancelMomentum:
            stopMomentum(sendEnd: true)
        case .magnify(let phase, let delta, let p):
            post(Self.gestureEvent(hidType: GestureEventFields.hidTypeZoom, phase: phase, value: delta, at: p, source: source))
        case .rotate(let phase, let degrees, let p):
            post(Self.gestureEvent(hidType: GestureEventFields.hidTypeRotation, phase: phase, value: degrees, at: p, source: source))
        case .key(let key):
            for event in Self.keyEvents(key, source: source) { post(event) }
        }
    }

    /// Releases a held mouse button and stops momentum. Used on device loss, sleep and shutdown.
    public func releaseAll() {
        stopMomentum(sendEnd: true)
        if leftButtonDown {
            let location = CGEvent(source: nil)?.location ?? .zero
            post(Self.mouseEvent(.leftMouseUp, at: location, button: .left, clickCount: 1, source: source))
            leftButtonDown = false
        }
    }

    // MARK: - Momentum

    private func startMomentum(velocity: CGVector, at p: CGPoint) {
        stopMomentum(sendEnd: false)
        momentumFrames = momentum.frames(initialVelocity: velocity)
        guard !momentumFrames.isEmpty else { return }
        momentumIndex = 0
        momentumLocation = p
        scrollRemainder = .zero
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / momentum.frameRate, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.momentumTick() }
        momentumTimer = timer
        timer.resume()
    }

    private func momentumTick() {
        guard momentumIndex < momentumFrames.count else {
            stopMomentum(sendEnd: true)
            return
        }
        let phase = momentumIndex == 0 ? Self.momentumBegin : Self.momentumContinue
        let whole = Self.splitWholePoints(momentumFrames[momentumIndex], remainder: &scrollRemainder)
        post(Self.scrollEvent(delta: whole, at: momentumLocation, phase: nil, momentum: phase, source: source))
        momentumIndex += 1
    }

    private func stopMomentum(sendEnd: Bool) {
        guard let timer = momentumTimer else { return }
        timer.cancel()
        momentumTimer = nil
        momentumFrames = []
        if sendEnd {
            post(Self.scrollEvent(delta: .zero, at: momentumLocation, phase: nil, momentum: Self.momentumEnd, source: source))
        }
    }

    // MARK: - Builders (static for testability)

    static func mouseEvent(_ type: CGEventType, at p: CGPoint, button: CGMouseButton, clickCount: Int, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return nil }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        return event
    }

    static func scrollEvent(delta: CGVector, at p: CGPoint, phase: GesturePhase?, momentum: Int64?, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(delta.dy), wheel2: Int32(delta.dx), wheel3: 0) else { return nil }
        event.location = p
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if let phase { event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhaseValue(phase)) }
        if let momentum { event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum) }
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        return event
    }

    static func scrollPhaseValue(_ phase: GesturePhase) -> Int64 {
        switch phase {
        case .began: return 1
        case .changed: return 2
        case .ended: return 4
        case .cancelled: return 8
        }
    }

    static func gesturePhaseValue(_ phase: GesturePhase) -> Int64 {
        switch phase {
        case .began: return GestureEventFields.phaseBegan
        case .changed: return GestureEventFields.phaseChanged
        case .ended: return GestureEventFields.phaseEnded
        case .cancelled: return GestureEventFields.phaseCancelled
        }
    }

    static func gestureEvent(hidType: Int64, phase: GesturePhase, value: Double, at p: CGPoint, source: CGEventSource?) -> CGEvent? {
        // A mouse event supplies a valid timestamp and location; the fields below turn it into a gesture event.
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left) else { return nil }
        event.flags = []
        event.setIntegerValueField(GestureEventFields.eventTypeField, value: GestureEventFields.gestureEventType)
        event.setIntegerValueField(GestureEventFields.subtypeField, value: GestureEventFields.subtypeValue)
        event.setIntegerValueField(GestureEventFields.field101, value: GestureEventFields.field101Value)
        event.setIntegerValueField(GestureEventFields.hidTypeField, value: hidType)
        if hidType == GestureEventFields.hidTypeZoom {
            event.setDoubleValueField(GestureEventFields.zoomValueField, value: value)
        } else {
            event.setDoubleValueField(GestureEventFields.rotationValueField, value: value)
        }
        event.setIntegerValueField(GestureEventFields.phaseField, value: gesturePhaseValue(phase))
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        return event
    }

    static func keyEvents(_ key: KeyCommand, source: CGEventSource?) -> [CGEvent] {
        var flags: CGEventFlags = []
        if key.control { flags.insert(.maskControl) }
        if key.option { flags.insert(.maskAlternate) }
        if key.shift { flags.insert(.maskShift) }
        if key.command { flags.insert(.maskCommand) }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: false) else { return [] }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: marker)
        up.setIntegerValueField(.eventSourceUserData, value: marker)
        return [down, up]
    }

    /// Returns the whole-point part of `delta` plus the carried remainder; keeps the fraction for the next call.
    static func splitWholePoints(_ delta: CGVector, remainder: inout CGVector) -> CGVector {
        let total = CGVector(dx: delta.dx + remainder.dx, dy: delta.dy + remainder.dy)
        let whole = CGVector(dx: total.dx.rounded(.towardZero), dy: total.dy.rounded(.towardZero))
        remainder = CGVector(dx: total.dx - whole.dx, dy: total.dy - whole.dy)
        return whole
    }

    private func post(_ event: CGEvent?) {
        guard let event else {
            logger.error("could not create event")
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter "MomentumGeneratorTests|EventBuilderTests"`
Expected: 10 tests pass. If `gestureEventFields` fails on `eventTypeField == 29`, CoreGraphics refused the write to field 55; keep the test for field 110/113/132 and drop the field-55 assertion, and note it in the commit message: the Gesture Identifier in Task 16 is the authoritative check.

- [ ] **Step 7: Commit**

```bash
git rm -q Tests/TouchInjectTests/SmokeTests.swift
git add Sources/TouchInject Tests/TouchInjectTests
git commit -m "feat(inject): CGEvent synthesis for mouse, phased scroll with momentum, magnify, rotate and keys"
```

---

### Task 14: App shell, permissions onboarding, bundle and scripts

**Files:**
- Delete: `Sources/TouchBridge/main.swift` (placeholder)
- Create: `Sources/TouchBridge/TouchBridgeApp.swift`, `Sources/TouchBridge/AppState.swift`, `Sources/TouchBridge/PermissionCoordinator.swift`, `Sources/TouchBridge/Windows.swift`, `Sources/TouchBridge/Views/MenuContent.swift`, `Sources/TouchBridge/Views/PermissionsView.swift`
- Create: `App/Info.plist`, `Scripts/build-app.sh`, `Scripts/install.sh`

**Interfaces:**
- Consumes: `Settings`, `SettingsStore`.
- Produces: `AppState.shared` (`@MainActor @Observable`; properties `settings`, `inputMonitoringGranted`, `accessibilityGranted`, `deviceStatus`, `allPermissionsGranted`; methods `start()`, `setEnabled(_:)`, `setNaturalScrolling(_:)`, `setLaunchAtLogin(_:)`, `showPermissions()`, `openSettingsFile()`, `saveSettings()`), `AppState.DeviceStatus`, `PermissionCoordinator`, `Windows.shared.show(_:title:id:)`. Task 15 extends `AppState` with display selection and the pipeline; Task 16 adds the identifier window.

- [ ] **Step 1: Write App/Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>TouchBridge</string>
    <key>CFBundleIdentifier</key><string>org.touchbridge.TouchBridge</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>TouchBridge</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
```

- [ ] **Step 2: Write the scripts**

`Scripts/build-app.sh`:
```bash
#!/bin/zsh
# Builds dist/TouchBridge.app from the SPM product and signs it.
# Usage: Scripts/build-app.sh [debug|release]   (SIGN_IDENTITY env var overrides the identity)
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
IDENTITY="${SIGN_IDENTITY:-Apple Development: Frederic Garsolke (LLLQH7PQW7)}"
APP="dist/TouchBridge.app"

swift build -c "$CONFIG" --product TouchBridge
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/TouchBridge" "$APP/Contents/MacOS/TouchBridge"
cp App/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
echo "built $APP ($CONFIG, signed as '$IDENTITY')"
```

`Scripts/install.sh`:
```bash
#!/bin/zsh
# Copies dist/TouchBridge.app to ~/Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d dist/TouchBridge.app ] || Scripts/build-app.sh release
mkdir -p "$HOME/Applications"
pkill -x TouchBridge || true
rm -rf "$HOME/Applications/TouchBridge.app"
cp -R dist/TouchBridge.app "$HOME/Applications/TouchBridge.app"
open "$HOME/Applications/TouchBridge.app"
echo "installed and launched ~/Applications/TouchBridge.app"
```

Run: `chmod +x Scripts/build-app.sh Scripts/install.sh`

- [ ] **Step 3: Write PermissionCoordinator.swift**

```swift
import AppKit
import ApplicationServices
import IOKit.hid

/// Checks and requests Input Monitoring (HID access) and Accessibility (event posting).
@MainActor
final class PermissionCoordinator {
    private var timer: Timer?

    func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openPane("Privacy_ListenEvent")
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPane("Privacy_Accessibility")
    }

    func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Calls `onChange` every two seconds until `stopPolling()`.
    func startPolling(_ onChange: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in onChange() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
```

- [ ] **Step 4: Write Windows.swift**

```swift
import AppKit
import SwiftUI

/// Creates and shows auxiliary windows for a menu-bar app without a main window.
@MainActor
final class Windows {
    static let shared = Windows()
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(_ content: Content, title: String, id: String) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(controller.view.fittingSize)
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 5: Write AppState.swift**

```swift
import AppKit
import Observation
import ServiceManagement
import TouchCore
import os

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    enum DeviceStatus: Equatable {
        case none
        case attached(name: String, exclusive: Bool)
        case openFailed(name: String)
    }

    var settings: Settings
    var inputMonitoringGranted = false
    var accessibilityGranted = false
    var deviceStatus: DeviceStatus = .none
    var lastError: String?

    let store: SettingsStore
    let permissions = PermissionCoordinator()
    private let logger = Logger(subsystem: "org.touchbridge", category: "permissions")
    private var started = false

    private init() {
        store = SettingsStore(directory: SettingsStore.defaultDirectory())
        settings = store.load()
    }

    var allPermissionsGranted: Bool { inputMonitoringGranted && accessibilityGranted }

    var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    var menuIcon: String {
        if !allPermissionsGranted { return "hand.raised.slash" }
        if case .attached = deviceStatus, settings.enabled { return "hand.tap.fill" }
        return "hand.tap"
    }

    var statusLine: String {
        if !allPermissionsGranted { return "Permissions missing" }
        switch deviceStatus {
        case .none: return "No touch screen connected"
        case .attached(let name, let exclusive): return exclusive ? "\(name): exclusive" : "\(name): shared (cursor is also moved by macOS)"
        case .openFailed(let name): return "\(name): could not open"
        }
    }

    func start() {
        guard !started else { return }
        started = true
        refreshPermissions()
        if !allPermissionsGranted { showPermissions() }
        permissions.startPolling { [weak self] in self?.refreshPermissions() }
    }

    func refreshPermissions() {
        let input = permissions.inputMonitoringGranted()
        let ax = permissions.accessibilityGranted()
        if input != inputMonitoringGranted || ax != accessibilityGranted {
            logger.info("permissions: input monitoring \(input), accessibility \(ax)")
        }
        inputMonitoringGranted = input
        accessibilityGranted = ax
    }

    func setEnabled(_ enabled: Bool) {
        settings.enabled = enabled
        saveSettings()
    }

    func setNaturalScrolling(_ natural: Bool) {
        settings.naturalScrolling = natural
        saveSettings()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = enabled
            saveSettings()
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
    }

    func saveSettings() {
        do { try store.save(settings) } catch { lastError = "Could not save settings: \(error.localizedDescription)" }
    }

    func showPermissions() {
        Windows.shared.show(PermissionsView(state: self), title: "TouchBridge Permissions", id: "permissions")
    }

    func openSettingsFile() {
        if !FileManager.default.fileExists(atPath: store.fileURL.path) { saveSettings() }
        NSWorkspace.shared.open(store.fileURL)
    }
}
```

- [ ] **Step 6: Write the views**

`Sources/TouchBridge/Views/MenuContent.swift`:
```swift
import SwiftUI

struct MenuContent: View {
    @Bindable var state: AppState

    var body: some View {
        Text(state.statusLine)
        if let error = state.lastError {
            Text(error).foregroundStyle(.red)
        }
        Divider()
        Toggle("Touch active", isOn: Binding(get: { state.settings.enabled }, set: { state.setEnabled($0) }))
        Toggle("Natural scrolling", isOn: Binding(get: { state.settings.naturalScrolling }, set: { state.setNaturalScrolling($0) }))
        Toggle("Launch at login", isOn: Binding(get: { state.launchAtLoginEnabled }, set: { state.setLaunchAtLogin($0) }))
        Divider()
        Button("Permissions…") { state.showPermissions() }
        Button("Open settings file") { state.openSettingsFile() }
        Divider()
        Button("Quit TouchBridge") { NSApp.terminate(nil) }
    }
}
```

`Sources/TouchBridge/Views/PermissionsView.swift`:
```swift
import SwiftUI

struct PermissionsView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TouchBridge needs two permissions").font(.title2)
            row(granted: state.inputMonitoringGranted,
                title: "Input Monitoring",
                detail: "Lets TouchBridge open the touch screen exclusively so macOS stops moving the cursor itself.") {
                state.permissions.requestInputMonitoring()
            }
            row(granted: state.accessibilityGranted,
                title: "Accessibility",
                detail: "Lets TouchBridge post mouse events and gestures.") {
                state.permissions.requestAccessibility()
            }
            Text("The status updates automatically after you grant a permission in System Settings.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 460)
    }

    private func row(granted: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant…", action: action)
            }
        }
    }
}
```

- [ ] **Step 7: Write TouchBridgeApp.swift and delete main.swift**

```swift
import AppKit
import SwiftUI

@main
struct TouchBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: AppState.shared)
        } label: {
            Image(systemName: AppState.shared.menuIcon)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.start()
    }
}
```

Run: `git rm -q Sources/TouchBridge/main.swift`

- [ ] **Step 8: Build, bundle and verify manually**

Run: `swift build && Scripts/build-app.sh debug && open dist/TouchBridge.app`
Expected:
1. A hand icon appears in the menu bar, no Dock icon.
2. The permissions window opens with two red crosses.
3. "Grant…" next to Input Monitoring opens System Settings at Input Monitoring; TouchBridge is listed (or can be added with "+" from `dist/`). Enable it.
4. "Grant…" next to Accessibility opens the Accessibility pane; enable TouchBridge.
5. Within two seconds both rows show green checkmarks and the menu icon changes from `hand.raised.slash` to `hand.tap`.
6. "Open settings file" creates and opens `~/Library/Application Support/TouchBridge/settings.json`.
7. Quit from the menu.

If codesign fails with "no identity found", list identities with `security find-identity -v -p codesigning` and pass the exact name via `SIGN_IDENTITY=... Scripts/build-app.sh debug`.

- [ ] **Step 9: Commit**

```bash
git add App Scripts Sources/TouchBridge
git commit -m "feat(app): menu bar app with permissions onboarding, bundle build and install scripts"
```

---

### Task 15: Pipeline wiring, display mapping, hotplug — milestone 1 acceptance

**Files:**
- Create: `Sources/TouchBridge/DisplayResolver.swift`, `Sources/TouchBridge/DevicePipeline.swift`, `Sources/TouchBridge/PipelineController.swift`
- Modify: `Sources/TouchBridge/AppState.swift`, `Sources/TouchBridge/Views/MenuContent.swift`
- Create only if Task 12 reported `mode=shared`: `Sources/TouchBridge/EventTapFilter.swift`

**Interfaces:**
- Consumes: `DeviceManager`, `DeviceEvent`, `HIDDescriptorParser`, `TouchScreenLayout`, `ReportFraming`, `ReportDecoder`, `DisplayMapper`, `MappingConfig`, `TouchTracker`, `GestureEngine`, `ActionRouter`, `EventInjector`, `MomentumGenerator`, `Settings`, `AppState`.
- Produces: `DisplayResolver` (`DisplayDescription`, `allDisplays()`, `resolve(_:)`, `startObserving(_:)`), `DevicePipeline` (`handle(reportID:raw:timestamp:)`, `updateMapping(_:)`, `updateSettings(_:)`, `cancelGestures()`, `shutdown()`, `onContacts`), `PipelineController` (`start()`, `restart()`, `updateSettings(_:)`, `availableDisplays()`, `onStatus`, `onContacts`), `AppState.liveContacts`, `AppState.displays`, `AppState.selectDisplay(_:)`.

- [ ] **Step 1: Write DisplayResolver.swift**

```swift
import AppKit
import CoreGraphics
import TouchCore

/// Resolves which display the touch panel maps to and reports display configuration changes (debounced).
@MainActor
final class DisplayResolver {
    struct DisplayDescription: Identifiable, Equatable {
        var id: CGDirectDisplayID
        var uuid: String
        var name: String
        var frame: CGRect
        var rotation: Int
        var isBuiltin: Bool
    }

    private var onChange: (() -> Void)?
    private var pending: DispatchWorkItem?

    func allDisplays() -> [DisplayDescription] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { id in
            DisplayDescription(id: id,
                               uuid: Self.uuid(of: id),
                               name: Self.name(of: id),
                               frame: CGDisplayBounds(id),
                               rotation: Int(CGDisplayRotation(id).rounded()),
                               isBuiltin: CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// `.auto` = first display that is not built in, else the first display at all.
    func resolve(_ selection: DisplaySelection) -> DisplayDescription? {
        let displays = allDisplays()
        if case .display(let uuid) = selection, let match = displays.first(where: { $0.uuid == uuid }) {
            return match
        }
        return displays.first { !$0.isBuiltin } ?? displays.first
    }

    func startObserving(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, _, context in
            guard let context else { return }
            let resolver = Unmanaged<DisplayResolver>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in resolver.scheduleChange() }
        }, context)
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private static func uuid(of id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "display-\(id)" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func name(of id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }
        return screen?.localizedName ?? "Display \(id)"
    }
}
```

- [ ] **Step 2: Write DevicePipeline.swift**

```swift
import Foundation
import CoreGraphics
import os
import TouchCore
import TouchDevice
import TouchInject

/// The processing chain of one touch screen. Everything after `handle` runs on `queue`.
final class DevicePipeline: @unchecked Sendable {
    let id: DeviceID
    let info: DeviceInfo
    let layout: TouchScreenLayout
    let queue: DispatchQueue
    var onContacts: (@Sendable ([Contact]) -> Void)?

    private let logger = Logger(subsystem: "org.touchbridge", category: "pipeline")
    private var decoder: ReportDecoder
    private var mapper: DisplayMapper
    private var tracker: TouchTracker
    private var engine: GestureEngine
    private var router: ActionRouter
    private let injector: EventInjector
    private var tickTimer: DispatchSourceTimer?
    private var enabled: Bool
    private var lastContactsPublish: UInt64 = 0

    init(id: DeviceID, info: DeviceInfo, layout: TouchScreenLayout, mapping: MappingConfig, settings: Settings) {
        self.id = id
        self.info = info
        self.layout = layout
        queue = DispatchQueue(label: "org.touchbridge.pipeline.\(id)", qos: .userInteractive)
        decoder = ReportDecoder(layout: layout)
        mapper = DisplayMapper(config: mapping)
        tracker = TouchTracker(stuckTimeout: UInt64(settings.gesture.stuckTimeout * 1_000_000_000))
        engine = GestureEngine(config: settings.gesture)
        router = ActionRouter(naturalScrolling: settings.naturalScrolling)
        injector = EventInjector(queue: queue, momentum: MomentumGenerator(
            decayPerFrame: settings.gesture.momentumDecayPerFrame,
            stopVelocity: settings.gesture.momentumStopVelocity))
        enabled = settings.enabled
    }

    // MARK: - Input (any thread)

    func handle(reportID: UInt8, raw: [UInt8], timestamp: UInt64) {
        queue.async { self.process(reportID: reportID, raw: raw, timestamp: timestamp) }
    }

    func updateMapping(_ mapping: MappingConfig) {
        queue.async {
            self.mapper = DisplayMapper(config: mapping)
            self.finishGestures()
        }
    }

    func updateSettings(_ settings: Settings) {
        queue.async {
            self.engine.config = settings.gesture
            self.router = ActionRouter(naturalScrolling: settings.naturalScrolling)
            self.tracker.stuckTimeout = UInt64(settings.gesture.stuckTimeout * 1_000_000_000)
            self.injector.momentum = MomentumGenerator(decayPerFrame: settings.gesture.momentumDecayPerFrame,
                                                       stopVelocity: settings.gesture.momentumStopVelocity)
            if self.enabled && !settings.enabled { self.finishGestures() }
            self.enabled = settings.enabled
        }
    }

    func cancelGestures() {
        queue.async { self.finishGestures() }
    }

    /// Synchronous: ends gestures, releases buttons, stops timers. Call before dropping the pipeline.
    func shutdown() {
        queue.sync {
            self.finishGestures()
            self.tickTimer?.cancel()
            self.tickTimer = nil
        }
    }

    // MARK: - Processing (queue)

    private func process(reportID: UInt8, raw: [UInt8], timestamp: UInt64) {
        guard reportID == layout.reportID,
              let payload = ReportFraming.payload(from: raw, reportID: reportID, layout: layout),
              let frame = decoder.decode(payload: payload, timestamp: timestamp) else { return }
        let screen = mapper.map(frame)
        publishContacts(screen)
        _ = tracker.process(screen)
        guard enabled else { return }
        run(engine.update(touches: tracker.touches, timestamp: timestamp))
        updateTickTimer()
    }

    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        let expired = tracker.tick(now)
        if !expired.isEmpty {
            logger.info("ended \(expired.count) stuck contact(s)")
            run(engine.update(touches: tracker.touches, timestamp: now))
        }
        run(engine.tick(now))
        updateTickTimer()
    }

    private func updateTickTimer() {
        let needed = !tracker.touches.isEmpty || !engine.isIdle
        if needed, tickTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20), leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in self?.tick() }
            tickTimer = timer
            timer.resume()
        } else if !needed, let timer = tickTimer {
            timer.cancel()
            tickTimer = nil
        }
    }

    private func finishGestures() {
        run(engine.reset())
        injector.releaseAll()
    }

    private func run(_ actions: [Action]) {
        guard !actions.isEmpty else { return }
        let context = RouterContext(frontmostBundleID: nil)
        for action in actions {
            logger.debug("action \(String(describing: action), privacy: .public)")
            for command in router.route(action, context: context) {
                injector.perform(command)
            }
        }
    }

    private func publishContacts(_ screen: ScreenFrame) {
        guard let onContacts else { return }
        let down = screen.contacts.filter(\.down)
        if down.isEmpty || screen.timestamp &- lastContactsPublish > 33_000_000 {
            lastContactsPublish = screen.timestamp
            onContacts(down)
        }
    }
}
```

- [ ] **Step 3: Write PipelineController.swift**

```swift
import AppKit
import os
import TouchCore
import TouchDevice

/// Thread-safe lookup of pipelines by device, used from the HID thread for the hot path.
private final class PipelineRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var pipelines: [DeviceID: DevicePipeline] = [:]

    func pipeline(for id: DeviceID) -> DevicePipeline? { lock.withLock { pipelines[id] } }
    func set(_ pipeline: DevicePipeline, for id: DeviceID) { lock.withLock { pipelines[id] = pipeline } }
    func remove(_ id: DeviceID) -> DevicePipeline? { lock.withLock { pipelines.removeValue(forKey: id) } }
    func removeAll() -> [DevicePipeline] { lock.withLock { let all = Array(pipelines.values); pipelines.removeAll(); return all } }
    var all: [DevicePipeline] { lock.withLock { Array(pipelines.values) } }
}

/// Owns the DeviceManager and one DevicePipeline per attached touch screen.
@MainActor
final class PipelineController {
    var onStatus: ((AppState.DeviceStatus) -> Void)?
    var onContacts: ((DeviceID, [Contact]) -> Void)?

    private let logger = Logger(subsystem: "org.touchbridge", category: "pipeline")
    private let registry = PipelineRegistry()
    private let displays = DisplayResolver()
    private var deviceManager: DeviceManager?
    private var settings: Settings
    private var wakeObserver: NSObjectProtocol?

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        guard deviceManager == nil else { return }
        displays.startObserving { [weak self] in self?.remapAll() }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.restart() }
            }
        }
        let registry = self.registry
        let manager = DeviceManager(preferExclusive: true) { [weak self] event in
            if case .report(let id, let reportID, let raw, let timestamp) = event {
                registry.pipeline(for: id)?.handle(reportID: reportID, raw: raw, timestamp: timestamp)
                return
            }
            Task { @MainActor in self?.handle(event) }
        }
        deviceManager = manager
        manager.start()
        logger.info("controller started")
    }

    func restart() {
        logger.info("restarting after wake")
        deviceManager?.stop()
        deviceManager = nil
        for pipeline in registry.removeAll() { pipeline.shutdown() }
        onStatus?(.none)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.start() }
    }

    func updateSettings(_ settings: Settings) {
        self.settings = settings
        for pipeline in registry.all { pipeline.updateSettings(settings) }
        remapAll()
    }

    func availableDisplays() -> [DisplayResolver.DisplayDescription] {
        displays.allDisplays()
    }

    // MARK: - Device events (main actor)

    private func handle(_ event: DeviceEvent) {
        switch event {
        case .attached(let id, let info, let mode):
            do {
                let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(info.descriptor))
                let pipeline = DevicePipeline(id: id, info: info, layout: layout,
                                              mapping: mapping(for: info, layout: layout), settings: settings)
                pipeline.onContacts = { [weak self] contacts in
                    Task { @MainActor in self?.onContacts?(id, contacts) }
                }
                registry.set(pipeline, for: id)
                onStatus?(.attached(name: info.product, exclusive: mode == .exclusive))
                logger.info("pipeline ready for \(info.product, privacy: .public) (\(layout.slots.count) slots)")
            } catch {
                logger.error("descriptor of \(info.product, privacy: .public) unusable: \(String(describing: error), privacy: .public)")
                onStatus?(.openFailed(name: "\(info.product) (descriptor)"))
            }
        case .openFailed(_, let info, let status):
            logger.error("open failed 0x\(String(status, radix: 16), privacy: .public)")
            onStatus?(.openFailed(name: info.product))
        case .detached(let id):
            registry.remove(id)?.shutdown()
            if registry.all.isEmpty { onStatus?(.none) }
        case .report:
            break
        }
    }

    private func mapping(for info: DeviceInfo, layout: TouchScreenLayout) -> MappingConfig {
        let display = displays.resolve(settings.displaySelection)
        let frame = display?.frame ?? CGDisplayBounds(CGMainDisplayID())
        let calibration = settings.calibrations[info.serial] ?? Calibration(orientation: display?.rotation ?? 0)
        return MappingConfig(logicalMaxX: layout.logicalMaxX, logicalMaxY: layout.logicalMaxY,
                             displayFrame: frame, calibration: calibration)
    }

    private func remapAll() {
        for pipeline in registry.all {
            pipeline.updateMapping(mapping(for: pipeline.info, layout: pipeline.layout))
        }
    }
}
```

- [ ] **Step 4: Extend AppState.swift**

Add stored properties and wire the controller. Add after `var lastError: String?`:
```swift
    var displays: [DisplayResolver.DisplayDescription] = []
    var liveContacts: [Contact] = []
    private var controller: PipelineController?
```
Replace `start()` and `refreshPermissions()` with:
```swift
    func start() {
        guard !started else { return }
        started = true
        refreshPermissions()
        if !allPermissionsGranted { showPermissions() }
        permissions.startPolling { [weak self] in self?.refreshPermissions() }
    }

    func refreshPermissions() {
        let input = permissions.inputMonitoringGranted()
        let ax = permissions.accessibilityGranted()
        if input != inputMonitoringGranted || ax != accessibilityGranted {
            logger.info("permissions: input monitoring \(input), accessibility \(ax)")
        }
        inputMonitoringGranted = input
        accessibilityGranted = ax
        if allPermissionsGranted, controller == nil {
            startController()
        }
    }

    private func startController() {
        let controller = PipelineController(settings: settings)
        controller.onStatus = { [weak self] status in self?.deviceStatus = status }
        controller.onContacts = { [weak self] _, contacts in self?.liveContacts = contacts }
        self.controller = controller
        displays = controller.availableDisplays()
        controller.start()
    }

    func refreshDisplays() {
        displays = controller?.availableDisplays() ?? []
    }

    func selectDisplay(_ selection: DisplaySelection) {
        settings.displaySelection = selection
        saveSettings()
    }
```
Replace `saveSettings()` so every change reaches the pipelines:
```swift
    func saveSettings() {
        do { try store.save(settings) } catch { lastError = "Could not save settings: \(error.localizedDescription)" }
        controller?.updateSettings(settings)
    }
```
Add `import TouchCore` is already present; `Contact` and `DisplaySelection` come from it.

- [ ] **Step 5: Add the display menu to MenuContent.swift**

Insert after the "Launch at login" toggle:
```swift
        Menu("Touch screen display") {
            Button(state.settings.displaySelection == .auto ? "Automatic ✓" : "Automatic") {
                state.selectDisplay(.auto)
            }
            ForEach(state.displays) { display in
                let selected = state.settings.displaySelection == .display(uuid: display.uuid)
                Button(selected ? "\(display.name) ✓" : display.name) {
                    state.selectDisplay(.display(uuid: display.uuid))
                }
            }
        }
        .onAppear { state.refreshDisplays() }
```

- [ ] **Step 6: Plan B, only if Task 12 reported `mode=shared` on this macOS**

Create `Sources/TouchBridge/EventTapFilter.swift` and start it from `PipelineController.start()` (`EventTapFilter.shared.start()`), and set `EventTapFilter.shared.touchActive` from `DevicePipeline.process` (`true` when `tracker.touches` is non-empty, `false` otherwise). It drops every mouse event that did not come from TouchBridge while a finger is down, so macOS's own pointer for the same panel cannot fight the injected events:

```swift
import CoreGraphics
import Foundation
import TouchInject

/// Session-level event tap that swallows non-TouchBridge mouse events while a touch is active.
final class EventTapFilter: @unchecked Sendable {
    static let shared = EventTapFilter()
    private var tap: CFMachPort?
    private let lock = NSLock()
    private var active = false

    var touchActive: Bool {
        get { lock.withLock { active } }
        set { lock.withLock { active = newValue } }
    }

    func start() {
        guard tap == nil else { return }
        let mask: CGEventMask = [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                 .rightMouseDown, .rightMouseUp, .rightMouseDragged]
            .reduce(0) { $0 | (1 << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, _, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let filter = Unmanaged<EventTapFilter>.fromOpaque(context).takeUnretainedValue()
            if filter.touchActive, event.getIntegerValueField(.eventSourceUserData) != EventInjector.marker {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: context) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
```

- [ ] **Step 7: Build and run milestone 1 acceptance (manual)**

Run: `swift build && Scripts/build-app.sh debug && open dist/TouchBridge.app`

Checklist (all on the external touch display, Finder open):
1. Menu status reads `normal Elan: exclusive`; icon is the filled hand.
2. Tap a Finder icon: the cursor jumps under the finger and the icon is selected. If the hit point is mirrored or rotated, quit the app, set `"orientation"` for serial `20231224X1` in `settings.json` to 0, 90, 180 or 270 (`"calibrations": {"20231224X1": {"orientation": 270}}`) until taps land under the finger; the Task 5 definition and `CGDisplayRotation` may differ by 180°.
3. Press and move: drags a window by its title bar; lift releases it.
4. Hold 0.6 s without moving: context menu opens.
5. Double-tap a folder: it opens.
6. Two quick taps far apart: two single clicks, no double-click.
7. Unplug the USB cable during a drag: the window stops following; move the trackpad: nothing is stuck. Menu status shows "No touch screen connected". Re-plug: status returns within 2 s and taps work.
8. "Touch active" off: touches do nothing; on: they work again.
9. "Touch screen display → Color LCD": taps land on the built-in display; "Automatic": back on the external one.
10. Close the lid / sleep, wake: touches work without relaunch.
11. `log stream --predicate 'subsystem == "org.touchbridge"' --level info` shows attach/detach lines and no errors.

- [ ] **Step 8: Commit**

```bash
git add Sources/TouchBridge
git commit -m "feat(app): per-device pipeline with display mapping, hotplug and wake handling (milestone 1)"
```

---

### Task 16: Gesture Identifier window, permission revocation — milestone 2 acceptance

**Files:**
- Create: `Sources/TouchBridge/Views/GestureIdentifierView.swift`
- Modify: `Sources/TouchBridge/AppState.swift` (identifier window, revocation handling), `Sources/TouchBridge/PipelineController.swift` (`pause()`), `Sources/TouchBridge/Views/MenuContent.swift` (menu item)

**Interfaces:**
- Consumes: `AppState.liveContacts`, `Windows.shared.show`, `Contact`.
- Produces: `GestureIdentifierView`, `IdentifierLog`, `AppState.showIdentifier()`, `PipelineController.pause()`.

- [ ] **Step 1: Permission revocation (spec section 9)**

Add to `PipelineController`:
```swift
    /// Stops the device manager and all pipelines; `start()` brings them back.
    func pause() {
        deviceManager?.stop()
        deviceManager = nil
        for pipeline in registry.removeAll() { pipeline.shutdown() }
        onStatus?(.none)
    }
```
and make `restart()` call `pause()` then schedule `start()`:
```swift
    func restart() {
        logger.info("restarting after wake")
        pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.start() }
    }
```
In `AppState.refreshPermissions()` replace the last `if` with:
```swift
        if allPermissionsGranted {
            if controller == nil { startController() } else { controller?.start() }
        } else if let controller {
            controller.pause()
            showPermissions()
        }
```
(`PipelineController.start()` is idempotent while running because of the `deviceManager == nil` guard.)

- [ ] **Step 2: Write GestureIdentifierView.swift**

```swift
import AppKit
import SwiftUI
import TouchCore

@MainActor
@Observable
final class IdentifierLog {
    var entries: [String] = []

    func add(_ text: String) {
        let stamp = String(format: "%8.3f", Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000))
        entries.append("\(stamp)  \(text)")
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
    }
}

/// Receives the events TouchBridge injects and draws the live contacts of the panel.
final class ProbeNSView: NSView {
    var onEvent: ((String) -> Void)?
    var contacts: [Contact] = [] { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func magnify(with event: NSEvent) {
        onEvent?("magnify \(Self.describe(event.phase)) \(String(format: "%+.3f", event.magnification))")
    }

    override func rotate(with event: NSEvent) {
        onEvent?("rotate \(Self.describe(event.phase)) \(String(format: "%+.1f°", event.rotation))")
    }

    override func scrollWheel(with event: NSEvent) {
        onEvent?("scroll phase=\(Self.describe(event.phase)) momentum=\(Self.describe(event.momentumPhase)) dx=\(Int(event.scrollingDeltaX)) dy=\(Int(event.scrollingDeltaY)) precise=\(event.hasPreciseScrollingDeltas)")
    }

    override func swipe(with event: NSEvent) {
        onEvent?("swipe dx=\(event.deltaX) dy=\(event.deltaY)")
    }

    override func mouseDown(with event: NSEvent) { onEvent?("mouseDown clicks=\(event.clickCount)") }
    override func mouseUp(with event: NSEvent) { onEvent?("mouseUp clicks=\(event.clickCount)") }
    override func rightMouseDown(with event: NSEvent) { onEvent?("rightMouseDown") }
    override func rightMouseUp(with event: NSEvent) { onEvent?("rightMouseUp") }
    override func mouseDragged(with event: NSEvent) {
        onEvent?("drag \(Int(event.locationInWindow.x)),\(Int(event.locationInWindow.y))")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard let window, let primary = NSScreen.screens.first else { return }
        for contact in contacts {
            // Global CG coordinates (origin top-left of the primary display) → Cocoa screen → window → view.
            let cocoa = NSPoint(x: contact.position.x, y: primary.frame.height - contact.position.y)
            let inWindow = window.convertPoint(fromScreen: cocoa)
            let p = convert(inWindow, from: nil)
            let radius: CGFloat = 22
            let circle = NSBezierPath(ovalIn: NSRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius))
            NSColor.systemBlue.withAlphaComponent(0.35).setFill()
            circle.fill()
            NSColor.systemBlue.setStroke()
            circle.lineWidth = 2
            circle.stroke()
            let label = NSAttributedString(string: "\(contact.id)", attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
            label.draw(at: NSPoint(x: p.x - 4, y: p.y - 7))
        }
    }

    static func describe(_ phase: NSEvent.Phase) -> String {
        var parts: [String] = []
        if phase.contains(.mayBegin) { parts.append("mayBegin") }
        if phase.contains(.began) { parts.append("began") }
        if phase.contains(.stationary) { parts.append("stationary") }
        if phase.contains(.changed) { parts.append("changed") }
        if phase.contains(.ended) { parts.append("ended") }
        if phase.contains(.cancelled) { parts.append("cancelled") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }
}

struct EventProbe: NSViewRepresentable {
    let log: IdentifierLog
    let contacts: [Contact]

    func makeNSView(context: Context) -> ProbeNSView {
        let view = ProbeNSView()
        view.onEvent = { [log] text in log.add(text) }
        return view
    }

    func updateNSView(_ view: ProbeNSView, context: Context) {
        view.contacts = contacts
    }
}

struct GestureIdentifierView: View {
    @Bindable var state: AppState
    @State private var log = IdentifierLog()

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Text("Perform gestures on this area. It must lie on the touch display.")
                    .font(.callout).foregroundStyle(.secondary).padding(8)
                EventProbe(log: log, contacts: state.liveContacts)
            }
            .frame(minWidth: 560, minHeight: 480)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Received events").font(.headline)
                    Spacer()
                    Button("Clear") { log.entries.removeAll() }
                }
                .padding(8)
                List(log.entries.reversed(), id: \.self) { entry in
                    Text(entry).font(.system(.caption, design: .monospaced))
                }
            }
            .frame(minWidth: 380)
        }
        .frame(minWidth: 960, minHeight: 520)
    }
}
```

- [ ] **Step 3: Wire the window into AppState and the menu**

Add to `AppState`:
```swift
    func showIdentifier() {
        Windows.shared.show(GestureIdentifierView(state: self), title: "Gesture Identifier", id: "identifier")
    }
```
Add to `MenuContent` next to "Permissions…":
```swift
        Button("Gesture Identifier…") { state.showIdentifier() }
```

- [ ] **Step 4: Build and run milestone 2 acceptance (manual)**

Run: `swift build && Scripts/build-app.sh debug && open dist/TouchBridge.app`

1. Menu → "Gesture Identifier…". Drag the window onto the touch display and enlarge it. Touching the left area shows blue circles under the fingers with their contact IDs.
2. Two-finger scroll on the probe area: log shows `scroll phase=began … changed … ended` followed by `momentum=began … changed … ended`, `precise=true`. Lift with a flick: the momentum lines continue after lifting.
3. Spread two fingers: `magnify began`, several `magnify changed +0.0xx`, `magnify ended`. Pinch: negative values.
4. Rotate counter-clockwise: `rotate changed +x°`; clockwise: negative.
5. Two-finger tap: `rightMouseDown`, `rightMouseUp`.
6. Safari on the touch display: pinch zooms the page; two-finger flick scrolls with inertia; two-finger tap opens the context menu. Fingers moving down must move the content down (earlier content appears). If the page moves the other way, toggle "Natural scrolling" in the menu.
7. Preview with an image: pinch zooms, rotate rotates.
8. Three-finger swipe up: Mission Control. Down: App Exposé. Left/right with a second Space present: Space changes. (System Settings → Keyboard → Keyboard Shortcuts → Mission Control: the ⌃↑ ⌃↓ ⌃← ⌃→ shortcuts must be enabled, which is the default.)
9. Unplug the panel during a pinch: log shows `magnify ended`; the trackpad works normally afterwards.
10. Revoke Accessibility in System Settings while running: within 2 s the menu icon turns to the crossed hand, the permissions window opens, touching does nothing. Grant again: touches work without relaunch.

If `magnify`/`rotate` never appear while `scroll` and mouse events do: in `GestureEventFields.swift` try, in this order, rebuilding after each change: (a) drop `subtypeField` and `field101` writes in `EventInjector.gestureEvent`; (b) additionally set `event.type = CGEventType(rawValue: 29)!` before the field writes. Keep the first combination that works and record it in the file's header comment.

- [ ] **Step 5: Commit**

```bash
git add Sources/TouchBridge
git commit -m "feat(app): gesture identifier window, permission revocation handling (milestone 2)"
```

---

### Task 17: Documentation and release tag

**Files:**
- Modify: `README.md`, `CLAUDE.md`

- [ ] **Step 1: Write the README**

Replace `README.md` with:
```markdown
# TouchBridge

Multitouch for USB touch screens on macOS. macOS treats a HID touch screen as a single-touch pointer. TouchBridge takes exclusive control of the screen, tracks all contacts itself and injects mouse events and trackpad gestures system-wide, so every app receives pinch, rotate, scroll with momentum and multi-finger swipes as if they came from a trackpad.

Open source, MIT, no license keys.

## Requirements

- macOS 14 or newer (developed on macOS 26)
- A touch screen that works on Windows without a driver (HID digitizer, usage page 0x0D / usage 0x04). Reference device: Elan 10-finger controller, 24" 1080p panel.
- Xcode 16 or newer to build

## Install

```
git clone <repo>
cd TouchBridge
Scripts/build-app.sh          # builds and signs dist/TouchBridge.app
Scripts/install.sh            # copies to ~/Applications and launches
```

On first launch grant **Input Monitoring** and **Accessibility** in the window that opens. The status updates by itself.

## Gestures (default set)

| Gesture | Result |
| --- | --- |
| Tap | Left click |
| Double tap | Double click |
| Press and move | Drag |
| Hold 0.6 s | Right click |
| Two-finger tap | Right click |
| Two-finger move | Scroll with momentum (natural direction, switchable) |
| Pinch / spread | Zoom (magnify) |
| Two-finger rotate | Rotate |
| Three/four-finger swipe up | Mission Control |
| Three/four-finger swipe down | App Exposé |
| Three/four-finger swipe left/right | Next / previous Space |

## Settings

`~/Library/Application Support/TouchBridge/settings.json`, editable while the app runs ("Open settings file" in the menu). Keys: `enabled`, `displaySelection` (`{"auto":{}}` or `{"display":{"uuid":"…"}}`), `naturalScrolling`, `gesture` (thresholds in seconds and points), `calibrations` (per device serial: `orientation` 0/90/180/270, `scaleX`, `scaleY`, `offsetX`, `offsetY`), `launchAtLogin`.

## Troubleshooting

- Menu says "shared": exclusive access failed; check Input Monitoring for TouchBridge. In shared mode macOS also moves the cursor.
- Taps land mirrored or rotated: set `calibrations.<serial>.orientation` to 90, 180 or 270.
- Pinch does nothing in an app: open "Gesture Identifier…" from the menu and perform the gesture on it; if `magnify` lines appear there, the app does not support trackpad zoom.
- Logs: `log stream --predicate 'subsystem == "org.touchbridge"' --level info`

## Development

```
swift build
swift test
swift run hidrecord --seconds 10 --out capture.jsonl   # record raw reports of your screen
```

Design: `docs/superpowers/specs/`. Plan: `docs/superpowers/plans/`. The undocumented CGEvent fields used for magnify/rotate live in `Sources/TouchInject/GestureEventFields.swift` only.

## License

MIT
```

- [ ] **Step 2: Update CLAUDE.md**

Append to `CLAUDE.md`:
```markdown
- Milestones 1 and 2 are complete: core, gestures, identifier window. Next: console/calibration UI, per-app gesture sets, local touch API, TUIO (see spec section 12).
- Manual acceptance checklists: plan Task 15 (M1) and Task 16 (M2). Re-run them after changes to TouchInject or DevicePipeline.
- The seize spike result and the working gesture field combination are documented in Sources/TouchInject/GestureEventFields.swift and docs/notes/ (if present).
```

- [ ] **Step 3: Full verification**

Run: `swift test && Scripts/build-app.sh release && Scripts/install.sh`
Expected: all tests pass; the installed app runs from `~/Applications`, "Launch at login" can be enabled, and after a logout/login the app is running.

- [ ] **Step 4: Commit and tag**

```bash
git add README.md CLAUDE.md
git commit -m "docs: README with install, gestures, settings and troubleshooting"
git tag -a v0.1.0 -m "TouchBridge 0.1.0: milestones 1 and 2"
```
