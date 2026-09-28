---
title: "Self-Level"
sidebar_label: "Self-Level"
sidebar_position: 20
documentation_status: reviewed
source: app/pages/autolevel_angle.lua
---

# Self-Level

Sets how the flight controller levels the aircraft when Failsafe, GPS Rescue, RTH or Loiter is flying it. Angle is no longer a flight mode you can put on a switch (firmware API 22.12), but these settings still control that self-leveling.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Flight Modes* → *Self-Level*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Gain | How firmly the aircraft is brought back to level, or to the bank and pitch GPS navigation asks for. 0–200, default 40. Higher corrects faster. |
| Bank | The most roll the self-leveling may command, 10–90°. GPS navigation turns never bank past this. |
| Pitch | The most pitch the self-leveling may command, 10–75°. |

## Notes

The settings are per PID profile. Save writes them to the flight controller with the rest of the PID profile. Bank and Pitch default to the shared angle limit (55°).

In-flight adjustment function 45 (Self-Level Gain) tunes Gain from a transmitter knob.

## Source

[Page implementation](../../../src/wfsuite/app/pages/autolevel_angle.lua). Menu conditions come from `app/tool.lua`.

*Reviewed against WFSuite Ethos 2.3.1 page and codec source and wingflight-firmware API 22.12; not radio-tested.*
