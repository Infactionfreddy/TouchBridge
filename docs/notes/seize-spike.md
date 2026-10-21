# Seize spike result (2026-10-21)

Reference panel: hotlotus "normal Elan", VID 0x0712 / PID 0x000A, serial 20231224X1, macOS 26.6.2.

## Exclusive access works

`hidrecord` opens the device with `kIOHIDOptionsTypeSeizeDevice` and gets `mode=exclusive` without any
permission prompt for the terminal. While seized, the system cursor does not follow the finger. The
descriptor parses to the expected layout: report 1, 10 slots, logical 2976 × 1680, 55 payload bytes.
IOKit delivers report 1 with the report-ID byte included (56 bytes), so `ReportFraming` strips it.

Plan B (session event tap) is not needed on this macOS.

## The panel starts in mouse mode

Freshly opened, the panel sends only report 7 (mouse emulation, 7 bytes) — 1651 reports in 25 s of
touching, not a single report 1. It switches to multitouch reporting (report 1, ~100 Hz while touching)
only after the host reads its Feature reports:

| Run | Feature reports read after open | Result in 25–30 s of touching |
| --- | --- | --- |
| hidrecord, first run | none | 1651 × report 7, 0 × report 1 |
| experiment `kick --kick` | 2 (Contact Count Maximum = 10) and 3 (257-byte certification blob) | 2747 × report 1 |
| hidrecord again, no read | none | 0 reports of any ID |
| hidrecord with the fix below | all Feature reports of the descriptor | 2587 × report 1, up to 2 contacts |

The switch holds only for the current open: the third run shows that after the kick the mouse
emulation stays off, but report 1 does not come back until the Feature reports are read again.
Windows reads these reports during enumeration, which is why the panel "just works" there; Linux has
the `MT_QUIRK_FORCE_GET_FEATURE` quirk for the same behaviour.

Which of the two reads matters was not isolated; reading every Feature report is cheap, mirrors
Windows and is device-agnostic.

## Fix

`DeviceManager.readFeatureReports(_:info:)` runs after every successful open (exclusive or shared):
it parses the descriptor, collects the Feature report IDs and issues `IOHIDDeviceGetReport` for each,
logging the result at info level. Failures are ignored so devices without Feature reports keep working.

The recorded fixture `Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl` (2587 reports, 25 s, one
and two fingers) enables `RecordedReportTests.recordedElanSessionDecodes`, which now passes.
