---
title: "PID Controller"
sidebar_label: "PID Controller"
sidebar_position: 20
documentation_status: draft
source: app/pages/pid_controller.lua
---

# PID Controller

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Flight Tuning* → *PID Controller*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| In-flight Error Decay (Limit) | Maximum speed, in °/s, at which accumulated I-term error bleeds off. Only matters for large accumulated errors; leave at the default. The decay time is on the *Master Gains* page. |
| Error Limit (R) | TODO: explain behaviour, displayed units, range and conditions. |
| Error Limit (P) | TODO: explain behaviour, displayed units, range and conditions. |
| Error Limit (Y) | TODO: explain behaviour, displayed units, range and conditions. |
| Iterm Relax Level (R) | I-term relax level in °/s (10-250, default 22): the stick movement at which I-term build-up is fully suppressed during a fast move. Lower suppresses more strongly. The main bounce-back setting is Relax on *Master Gains*; leave level at the default unless that is not enough. |
| Iterm Relax Level (P) | Same as roll, for pitch. |
| Iterm Relax Level (Y) | Same as roll, for yaw. |
| Cross Axis Relax (R) | TODO: explain behaviour, displayed units, range and conditions. |
| Cross Axis Relax (P) | TODO: explain behaviour, displayed units, range and conditions. |
| (Level) | TODO: explain behaviour, displayed units, range and conditions. |
| (Cutoff) | TODO: explain behaviour, displayed units, range and conditions. |
| Snap Relax (Strength) | Percent (0-100, default 100) of roll, pitch and yaw feedback taken off when it pushes against a pop top, pinwheel or snap. These start with roll, pitch and yaw slammed in together, and the airframe then rotates faster than the stick asks for. Feedback that helps the rotation is not touched; yaw usually lags the stick, so the rudder is only relaxed if the airframe yaws faster than asked. 0 turns it off. |
| Snap Relax (Threshold) | Stick deflection, percent (20-100, default 60), that roll, pitch and yaw must all reach to count as a snap. |
| (Window) | Entry window in ms (0-1000, default 400): all three sticks must pass the threshold within this time of each other, so a slow build-up such as a rolling harrier does not count. |
| (Fade-out) | Time in ms (0-1000, default 350) over which full feedback returns after any of the three sticks drops below the threshold. Reversing the stick against the snap brings full feedback back at once. |
| Prop Hang (Strength) | Percent (0-100, default 100) of the roll I-term held back in a prop hang, so the prop torque can roll the model instead of the gyro holding it still. P and the stick still work. Roll only. Needs an altitude estimate (a barometer) to tell a hang from an up-line. Firmware without prop-hang relax leaves these fields disabled. 0 turns it off. |
| (Angle) | Degrees (5-45, default 20) the nose can be from straight up and still count as a hang. The model must also be climbing or sinking at no more than 2 m/s, for half a second. |
| (Fade-out) | Time in ms (0-2000, default 500) over which the roll I-term comes back after the hang ends. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/pid_controller.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
