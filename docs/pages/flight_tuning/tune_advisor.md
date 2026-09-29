---
title: "Tune Advisor"
sidebar_label: "Tune Advisor"
sidebar_position: 40
documentation_status: reviewed
source: app/pages/tune_advisor.lua
---

# Tune Advisor

While you fly in rate mode, the flight controller measures how the model answers the sticks. This page reads
those measurements and suggests one change at a time for each axis. It changes nothing by itself: make the
change on *PIDs*, *Rates* or *Flight Feel*, fly again and come back.

The flight controller counts only armed, airborne rate flight. Time in ANGLE, ATT HOLD, TRAINER, the GPS modes,
failsafe, MANUAL or PASSTHROUGH is left out. The data builds up over several flights and clears on its own when
you change the PIDs, master gains, I-term Relax, PID mode, rates or the active profile. A useful set is about
ten seconds of rolls and pitch inputs with the stick centred after each one.

## Where to find it

*Configuration* → *Flight Tuning* → *Tune Advisor*

Requires a running background task and a flight controller connection. Firmware from before the Tune Advisor
shows "Needs newer firmware". The page refreshes every 2 seconds.

## Settings

| Line | What it shows |
| --- | --- |
| Data | Minutes and seconds of rate flight measured, and whether measuring is happening now (collecting) or not (paused). |
| Roll / Pitch / Yaw | How fast the model rolls compared with the rate the stick asks for (1.00x = exactly as asked), and the delay before it answers. Yaw is not judged. |
| F line | **F hot**: the model rolls faster than asked, so F sends too much surface. It suggests a lower F and a higher rate by the same amount, so the stick feels the same but asks for the rate the model really flies. **F low** is the reverse. One step changes F by at most 20%. **F matches** needs no change. "Fly more" shows how much data is still needed; "too irregular" means the response varies too much to judge, which is common on pitch in 3D flying. |
| Second line | A fact, when there is one: full stick asks for more rate than the model can reach with its surfaces at their limit (lower the rate or add surface throw); or the response changes with throttle; or big inputs get less rate than small ones. |
| Stops line | How much the model bounces back after you centre the stick, as a share of the roll rate. **Clean** needs no change. If the I-term is pushing back, raise *I-term Relax* on *Flight Feel*. If F does not match yet, fix F first. Otherwise the controller is barely braking the stop: raise P (the suggested step is 20%) or add B. |
| Tool button | Clears the measurements after asking to confirm. |

## Notes

- The flight controller only measures. The suggestions are worked out on the radio from those measurements,
  so they can be improved without a firmware update.
- The measurements live in the flight controller's memory and are lost at power-off.
- Built on flight controllers with more than 128 KB of flash.

## Source

[Page implementation](../../../src/wfsuite/app/pages/tune_advisor.lua). Menu conditions come from `app/tool.lua`.
Firmware side: `src/main/flight/tune_advisor.c` in wingflight-firmware.

*Checked against WFSuite Ethos 2.3.1.*
