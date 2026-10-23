# TouchBridge

Status: milestones 1 (core) and 2 (gestures) are implemented and unit-tested; hardware acceptance on the reference panel is pending.

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

On first launch grant **Input Monitoring** and **Accessibility** in the window that opens. The status updates by itself. macOS may ask you to Quit & Reopen the app after granting Input Monitoring.

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

Open "Settings…" from the menu bar icon. The sidebar lists the **Default** profile and one profile per application (add one with "+", choosing the app in /Applications). The profile of the frontmost application applies; TouchBridge itself and apps without a profile use Default.

- **Gestures**: every gesture has an on/off switch and an action: pass through (the built-in behaviour), none, a mouse click (left, right, middle, back, forward; single to triple), a keyboard shortcut (recorded by pressing it), a system action (Mission Control, App Exposé, Space left/right, Show desktop) or a file/application to open. Two-finger drag additionally has natural scrolling and momentum switches. Rows marked "Default" in an application profile inherit from the default profile; "Reset to default" in the context menu removes an override. Greyed-out gestures are not recognized yet (they come with later versions).
- **Tuning**: all engine thresholds and durations (tap and double-tap timing, long-press duration, scroll classification, pinch and rotate thresholds, momentum, swipe distance and duration, stuck-contact timeout). In an application profile, tick "Override" to give the app its own value.
- **Advanced**: opens `~/Library/Application Support/TouchBridge/settings.json` (schema 2). The file holds `enabled`, `displaySelection` (`{"auto":{}}` or `{"display":{"uuid":"…"}}`), `calibrations` (per device serial: `orientation` 0/90/180/270, `scaleX`, `scaleY`, `offsetX`, `offsetY`), `launchAtLogin`, `defaultProfile` and `appProfiles` (each with `bundleID`, `displayName`, `bindings` keyed by gesture name, `config` overrides). A schema-1 file from an earlier version is migrated on launch and kept as `settings.json.v1`.

## Troubleshooting

- Menu says "shared": exclusive access failed; check Input Monitoring for TouchBridge. In shared mode macOS also moves the cursor.
- Taps land mirrored or rotated: set `calibrations.<serial>.orientation` to 90, 180 or 270.
- Pinch does nothing in an app: open "Gesture Identifier…" from the menu and perform the gesture on it; if `magnify` lines appear there, the app does not support trackpad zoom.
- Touching does nothing although the status says exclusive: check the log for `read feature report` lines. The panel switches to multitouch reporting only after its Feature reports were read; without them it sends mouse reports only (see `docs/notes/seize-spike.md`).
- A gesture does nothing in one app only: open Settings… and check that app's profile; "Restore defaults" resets it. The header shows which profile is active for the frontmost app.
- A shortcut without a modifier (e.g. "A") types into the frontmost app; use ⌘/⌥/⌃ combinations.
- Logs: `log stream --predicate 'subsystem == "org.touchbridge"' --level info`
- `swift test` fails at codesign with "resource fork, Finder information, or similar detritus not allowed": run `swift test --scratch-path /tmp/touchbridge-build` or `xattr -cr .build` first (Finder attributes under ~/Documents).

## Development

```
swift build
swift test
swift run hidrecord --seconds 10 --out capture.jsonl   # record raw reports of your screen
```

First run on new hardware: run the seize spike with the panel connected. Quit TouchBridge first (two seizers make the spike report `shared`).

```
swift run hidrecord --seconds 12 --out Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl
```

Look for `mode=exclusive` and for the macOS cursor no longer moving while you touch the screen. If `shared (seize failed 0x…)` appears, either Input Monitoring is missing for the terminal app, or exclusive access is not possible on this macOS; the latter needs the event-tap fallback described in the plan. The repository ships a recording from the reference panel (`RecordedReportTests.recordedElanSessionDecodes` checks it); re-record it for a different device. Note that the reference panel reports only mouse events until the host has read its Feature reports; `DeviceManager` does that after every open (see `docs/notes/seize-spike.md`).

Design: `docs/superpowers/specs/`. Plan: `docs/superpowers/plans/`. The undocumented CGEvent fields used for magnify/rotate live in `Sources/TouchInject/GestureEventFields.swift` only.

## License

MIT
