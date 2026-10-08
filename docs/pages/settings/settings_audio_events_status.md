---
title: "Status alerts"
sidebar_label: "Status alerts"
sidebar_position: 50
documentation_status: reviewed
source: app/pages/settings_audio_events_status.lua
---

# Status alerts

Callouts for flight controller health flags decoded from System Status and System Config sensors.

## Where to find it

*System* → *Settings* → *Audio* → *Events* → *Status alerts*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| *RX input backup* | Calls out when receiver input falls back to the secondary receiver link. |
| *Gyro failure* | Calls out sensor or communication overflow on the flight controller gyro. |
| *GPS warning* | Calls out when the GPS unit stops communicating or reports failure. |
| *Blackbox full* | Calls out when on-board flash logging space is exhausted. |
| *Autotrim completed* | Calls out when automatic trim computation completes. |
| *Control limits* | Calls out when actuator command reaches mechanical or configured saturation limits (disabled by default). |

## Notes

- Changes are saved to the radio's settings store, not to the flight controller.
- These callouts evaluate telemetry words transmitted by the flight controller.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_audio_events_status.lua). Menu conditions come from `app/tool.lua`.
