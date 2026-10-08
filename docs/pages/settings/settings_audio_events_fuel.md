---
title: "Fuel"
sidebar_label: "Fuel"
sidebar_position: 30
documentation_status: reviewed
source: app/pages/settings_audio_events_fuel.lua
---

# Fuel

SmartFuel callouts and low-fuel repeat cadences based on battery telemetry.

## Where to find it

*System* → *Settings* → *Audio* → *Events* → *Fuel*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| *Fuel* | Master switch. When on, enables SmartFuel percentage callouts and low-fuel alerts. |
| *Callout percent* | Interval between periodic fuel callouts (default, 5%, 10%, 20%, 25%, 50%). |
| *Repeats below* | How many times the low-fuel warning repeats when fuel drops below the low threshold (1 to 10, default 1). |
| *Haptic below* | Vibrate the transmitter along with the audible low-fuel alert. |

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

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_audio_events_fuel.lua). Menu conditions come from `app/tool.lua`.
