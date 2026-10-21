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
- Milestones 1 and 2 are code-complete (core, gestures, identifier window); the seize spike passed (docs/notes/seize-spike.md: the panel needs its Feature reports read after every open); the Task 15/16 acceptance checklists are pending. Next after acceptance: console/calibration UI, per-app gesture sets, local touch API, TUIO (spec section 12).
- Manual acceptance checklists: plan Task 15 (M1) and Task 16 (M2). Re-run them after changes to TouchInject or DevicePipeline.
- The seize spike result and the working gesture field combination are documented in docs/notes/seize-spike.md and Sources/TouchInject/GestureEventFields.swift.
- Build/test here with `--scratch-path /tmp/touchbridge-build` if codesign complains about Finder attributes; the plan's briefs used /private/tmp/claude-501/tb-build.
