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

`~/Library/Application Support/TouchBridge/settings.json`, editable while the app runs ("Open settings file" in the menu). Keys: `schemaVersion` (always 1, written by the app), `enabled`, `displaySelection` (`{"auto":{}}` or `{"display":{"uuid":"…"}}`), `naturalScrolling`, `gesture` (thresholds in seconds and points), `calibrations` (per device serial: `orientation` 0/90/180/270, `scaleX`, `scaleY`, `offsetX`, `offsetY`), `launchAtLogin`. Out-of-range gesture values are clamped when the file is read (durations to 0–10 s, `momentumDecayPerFrame` to 0–0.999, `rotateThreshold` to 0–180°, distances and velocities to ≥ 0); `orientation` is reduced modulo 360 and becomes 0 unless it is 0, 90, 180 or 270.

## Troubleshooting

- Menu says "shared": exclusive access failed; check Input Monitoring for TouchBridge. In shared mode macOS also moves the cursor.
- Taps land mirrored or rotated: set `calibrations.<serial>.orientation` to 90, 180 or 270.
- Pinch does nothing in an app: open "Gesture Identifier…" from the menu and perform the gesture on it; if `magnify` lines appear there, the app does not support trackpad zoom.
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

Look for `mode=exclusive` and for the macOS cursor no longer moving while you touch the screen. If `shared (seize failed 0x…)` appears, either Input Monitoring is missing for the terminal app, or exclusive access is not possible on this macOS; the latter needs the event-tap fallback described in the plan. Recording this fixture also enables the currently skipped test `RecordedReportTests.recordedElanSessionDecodes`.

Design: `docs/superpowers/specs/`. Plan: `docs/superpowers/plans/`. The undocumented CGEvent fields used for magnify/rotate live in `Sources/TouchInject/GestureEventFields.swift` only.

## License

MIT
