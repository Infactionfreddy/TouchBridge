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
