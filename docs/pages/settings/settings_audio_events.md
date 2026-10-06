---
title: "Events"
sidebar_label: "Events"
sidebar_position: 10
documentation_status: draft
source: app/pages/settings_audio_events.lua
---

# Events

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*System* → *Settings* → *Audio* → *Events*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

- **SmartFuel waits for one reading before it speaks.** After connecting, the
  first fuel reading is only recorded, so a reading of 0 from telemetry that
  hasn't settled yet doesn't announce "low fuel" or vibrate the radio.
- **No SmartFuel callouts while the flight controller reports no battery.**
  While it is still detecting the pack after power-up, or has none (for example
  on USB at the bench), its fuel reading is 0 and means "no battery", so
  nothing is announced. Once it detects the pack, the first reading is recorded
  again.
- **An empty pack is still announced**, from the second reading after the pack
  is detected: one reading later than before, not silenced.
- Percentage callouts are unchanged: one per step of the callout range, as the
  reading falls past it.
- **Battery profile** announces the newly selected pack as "Battery, 2200
  milliamp hours, 4 cells". The cell count is left out when the profile has none
  set (auto-detect).

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_audio_events.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
