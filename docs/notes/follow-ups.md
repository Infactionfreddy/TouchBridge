# Follow-ups after the milestone 1/2 implementation

State (2026-10-21): all 17 plan tasks implemented, reviewed and merged to `main`; 109 unit tests green including the recorded-panel test. The seize spike passed on the reference panel and uncovered that the panel needs its Feature reports read after every open (`docs/notes/seize-spike.md`); Plan B is not needed. Part A (gesture profiles and settings window) is implemented and awaits acceptance on the panel; Parts B (multi-finger taps/drags) and C (edge swipes, squeeze/splay, discrete pinch/rotate) are next. This file lists what is still open, in the order it should happen.

## 1. Hardware acceptance (needs the Elan panel and a person)

1. Done: seize spike (`mode=exclusive`, fixture recorded, Plan B not needed).
2. Done: `swift test` with the fixture (`RecordedReportTests.recordedElanSessionDecodes` passes).
3. `Scripts/build-app.sh` then `Scripts/install.sh`; grant both permissions. macOS may ask to Quit & Reopen after the Input Monitoring grant.
4. Milestone 1 checklist: plan Task 15 step 7 (tap, drag, long press, double tap, unplug during drag, display selection, sleep/wake, log stream).
5. Milestone 2 checklist: plan Task 16 step 4 (Gesture Identifier signs: fingers down → positive dy, spread → positive magnify, counter-clockwise → positive rotate, three-finger left → next Space; Safari, Preview, Mission Control; unplug during pinch; revoke Accessibility at runtime).
6. If taps land mirrored or rotated, set `calibrations.<serial>.orientation` in `settings.json` (0/90/180/270). The default comes from `CGDisplayRotation`, whose sign relative to `DisplayMapper` is unverified.
7. If `magnify`/`rotate` never arrive while scroll and clicks do, follow the fallback order in plan Task 16 step 4 (drop fields 50/101, then set the event type directly) and record the working combination in `GestureEventFields.swift`.
8. Tag `v0.1.0` only after the checklists pass.

## Part A acceptance (needs the panel)

1. Launch: the old settings.json is migrated; `settings.json.v1` sits next to it; natural scrolling and tuning from before still apply.
2. Settings… → "+" → Safari. Gestures: set "Three finger swipe left" to the keyboard shortcut ⌘[. In Safari a three-finger swipe left goes back; in Finder it still switches Spaces. The header shows "active profile: Safari" while Safari is frontmost.
3. Tuning in the Safari profile: tick Override on "Long press duration", set 1.0. A long press opens the context menu later in Safari, unchanged in Finder.
4. Set "Two finger tap" to Mouse click → Middle in the Safari profile: a two-finger tap on a link opens it in a new tab.
5. Default profile: switch "Natural scrolling" off in the Gestures row of "Two finger drag"; the menu toggle follows, and scrolling inverts everywhere without a profile.
6. Remove the Safari profile ("−", confirm): Safari uses the default profile again.
7. Quit and relaunch: all settings persist; `log stream --predicate 'subsystem == "org.touchbridge"'` shows no errors.

## 2. Code follow-ups found in review (none blocks acceptance)

Device layer
- `DeviceManager.release(_:)` closes a device whose descriptor cannot be parsed; a later unplug of that device emits no `.detached`, so the "(descriptor)" status stays until re-plug. Keep a released-id set and still emit `.detached`.
- Control events queued while `PipelineController.stopAll()` runs are handled afterwards; a generation counter in the sink would drop them.
- Two concurrent `stop()` calls would hang the second caller; a `DispatchGroup` fixes it (single caller today).
- With `preferExclusive == false` the attach event reports `.shared(seizeStatus: kIOReturnUnsupported)` although no seize was attempted.
- `TouchScreenLayout` assumes one touch-screen collection, Contact Count as an Input item in the fingers' report, and one logical range for all slots; other devices get a clear `LayoutError`. Hardening pass if a second panel is supported.

Gesture engine
- Momentum velocity comes from the last frame only; add 2–3-frame smoothing if flings feel jumpy on hardware.
- A contact replaced within one frame while two fingers are pending can emit a right click with a finger still down.
- `.twoReleasing` ignores how far the remaining finger moves before the tap decision.
- One-finger taps do not check `tapMaxDuration` (ruling R4); a stationary lift before `longPressDuration` is a click.

App
- `launchAtLoginEnabled` is computed from `SMAppService` and not observable; `lastError` is never cleared.
- The display submenu refreshes via `.onAppear`; an `onDisplaysChanged` callback would keep it current.
- The permission poll keeps running after both grants (this is what detects revocation).
- `build-app.sh`: iCloud's File Provider can re-add Finder attributes between `xattr -cr` and `codesign`; rerun, or sign in a temp directory outside `~/Documents`.
- Release signing (Developer ID, notarization) is not scripted yet (spec 4.3).

Tests
- Add boundary tests (exactly 60 pt / 0.5 s swipes, `dx == dy` tie), decoder edge cases, framing guards with reports one byte longer than the payload, all four key codes, the `DisplaySelection` JSON shape, a descriptor fuzz test.
- A `CommandSink` protocol behind `EventInjector` would allow end-to-end tests from raw Elan bytes to `Command`s without CoreGraphics; the app layer has no automated coverage.

Settings
- `schemaVersion` is pinned to 1 on save; a future v2 needs real migration logic.
- A single wrong-typed key sets the whole file aside as `.broken` (spec 7 behaviour); per-key lenient decoding with logging is an option.

## 3. Decisions that deviate from the plan text

- Settings values are clamped on decode so a hand-edited file cannot crash the pipeline.
- The gesture engine restarts classification when the contact id set changes at the same finger count, and keeps one remaining finger inert (`.oneRemaining`) after a two-finger gesture until the count changes again.
- Lifting one of three or four fingers consumes the rest until all lift; a swipe never turns into a scroll.
- Swipe left maps to Ctrl+→ (next Space), the trackpad convention; verify at acceptance.
- `DeviceManager.stop()` is synchronous and must never be called from the sink.
- Permission revocation pauses once and shows the onboarding once; wake while paused does not reopen devices.
