---
title: "ESC temperature"
sidebar_label: "ESC temperature"
sidebar_position: 20
documentation_status: reviewed
source: app/pages/settings_audio_events_esc.lua
---

# ESC temperature

Alert and threshold for speed-controller over-temperature telemetry callouts.

## Where to find it

*System* → *Settings* → *Audio* → *Events* → *ESC temperature*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| *ESC temperature* | Master switch. When on, calls out whenever the ESC telemetry temperature reaches or exceeds the threshold. |
| *ESC threshold* | Temperature threshold in degrees Celsius (60 to 300, default 90). Greyed out while *ESC temperature* is off. |

## Notes

- Changes are saved to the radio's settings store, not to the flight controller.
- The ESC threshold is greyed out while the alert is disabled.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_audio_events_esc.lua). Menu conditions come from `app/tool.lua`.
