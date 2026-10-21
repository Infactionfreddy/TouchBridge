# Scroll feel tuning (2026-10-21)

Symptom reported after the first hardware session: two-finger scrolling felt jerky ("hakelig").

## Measurements on the recorded session

`Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl`, 25 s, one and two fingers, decoded offline:

| Quantity | Value |
| --- | --- |
| Report interval | median 8.0 ms (125 Hz), p90 9.1 ms, p99 10.1 ms; no bursts |
| Digitizer resolution on the 1920 × 1080 display | 0.645 px per unit in x, 0.643 px in y |
| Two-finger centroid step per report | median 5.5 px, p90 11.3 px |
| Small sign flips in consecutive dy (noise) | 0.6 % |
| Mean fractional part of per-report dy | 0.48 px (lost by integer pixel deltas) |
| Dead time before a scroll classified at 10 pt | 33–60 ms, then a first delta of 10.7–15.2 px |
| Dead time at 4 pt | 17–33 ms, first delta 4–6 px; finger distance changed ≤ 4 px by then |
| Lift-off velocity, last report vs 6-report window | 601 vs 910 pt/s (fingers slow down before leaving) |

The panel data is smooth and regular; the roughness came from the processing.

## Changes

1. `GestureConfig.classifyMovement` 10 → 4 pt (spec 5.6 said 10). Removes the "sticks, then jumps" start.
   User feedback: start follows the finger immediately, no jump.
2. `GestureConfig.velocityWindow` (new, 0.05 s): the momentum velocity is measured over the scroll centroids
   of the last 50 ms before lift-off (at least two samples) instead of the last report interval.
3. `EventInjector.scrollEvent` writes the exact fractional delta into `scrollWheelEventFixedPtDeltaAxis1/2`
   (what `NSEvent.scrollingDeltaX/Y` reads) and keeps the carried whole-point delta in the integer fields.

Momentum decay (0.96 per 60 Hz frame) and stop velocity (20 pt/s) are unchanged; both are settings keys
(`momentumDecayPerFrame`, `momentumStopVelocity`) for further tuning by feel.
