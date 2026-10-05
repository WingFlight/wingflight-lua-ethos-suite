---
title: "Angle Mode"
sidebar_label: "Angle Mode"
sidebar_position: 20
documentation_status: reviewed
source: app/pages/autolevel_angle.lua
---

# Angle Mode

Sets how Angle mode levels the model: how hard it drives toward the stick
angle, how much it damps that return, and the largest bank and pitch angle
the sticks can ask for. Failsafe and the GPS modes level through the same
settings.

## Where to find it

*Configuration* → *Flight Tuning* → *Flight Modes* → *Angle Mode*

Requires a running background task and a flight controller connection. The
values belong to the current PID profile.

## Settings

| Setting | What it does |
| --- | --- |
| Gain | Leveling strength (`angle_level_strength`, 0–200, default 40): degrees per second of rotation per degree of error, ×10. |
| Damping | Percent of the measured roll and pitch rate taken off the leveling command (`angle_level_damping`, 0–100 %, default 25). Higher settles with less overshoot but levels more slowly; 0 turns it off. |
| Bank | Largest roll angle at full stick (`angle_roll_limit`, 10–90°). |
| Pitch | Largest pitch angle at full stick (`angle_pitch_limit`, 10–75°). |

## Notes

Angle mode never asks for more roll or pitch rate than the rate profile's
full-stick rate. When it engages, the target starts at the model's current
attitude and moves toward the stick angle at that rate, so the model levels
smoothly instead of snapping.

Damping needs firmware with MSP API 22.13 or later; the suite requires it.

## Source

[Page implementation](../../../src/wfsuite/app/pages/autolevel_angle.lua). Menu conditions come from `app/tool.lua`.

*Checked against WFSuite Ethos 2.3.1.*
