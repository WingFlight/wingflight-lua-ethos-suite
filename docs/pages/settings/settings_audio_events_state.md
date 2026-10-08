---
title: "State callouts"
sidebar_label: "State callouts"
sidebar_position: 40
documentation_status: reviewed
source: app/pages/settings_audio_events_state.lua
---

# State callouts

Callouts triggered when a discrete state or mode changes on the model or transmitter.

## Where to find it

*System* → *Settings* → *Audio* → *Events* → *State callouts*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| *Arming flags* | Calls out reasons why the model cannot arm when arming is attempted. |
| *Governor state* | Calls out governor status transitions. |
| *Flight mode* | Calls out flight mode switches (Angle, Horizon, Acro, Trainer, etc.). |
| *GPS fix* | Calls out when GPS lock is acquired or lost. |
| *PID profile* | Calls out changes to the active PID profile index. |
| *Rate profile* | Calls out changes to the active Rate profile index. |
| *Thrust vector profile* | Calls out changes to the active Thrust Vectoring profile index. |
| *Battery profile* | Announces the selected battery profile (capacity and cell count). |
| *Adjustment function* | Calls out the selected in-flight adjustment function when switched. |
| *Adjustment value* | Calls out the current adjustment value when changed. |

## Notes

- Changes are saved to the radio's settings store, not to the flight controller.
- These events are triggered on transition edges rather than periodically.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_audio_events_state.lua). Menu conditions come from `app/tool.lua`.
