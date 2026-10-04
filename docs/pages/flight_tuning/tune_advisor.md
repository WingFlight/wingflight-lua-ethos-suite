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

Requires a running background task and a flight controller connection. The page refreshes every 2 seconds.
Firmware from before the Tune Advisor shows "Needs newer firmware" and the page stops asking; Reload asks again.
When the link drops for a moment, the last measurements stay on screen until the next answer.

## Settings

| Line | What it shows |
| --- | --- |
| Axis | Roll, Pitch or Yaw. Everything below is for the chosen axis. On a wing the rudder response is often too uneven to judge. |
| Changes / Why | Only on 480-pixel-wide radios (X18, X18R, X10 and similar), beside Axis. *Changes* shows the suggested changes and as many reasons as fit, ending in "More under Why" when some are left out; *Why* shows all the reasons. Larger radios show everything. |
| Flight data | Minutes and seconds of rate flight measured, and whether measuring is happening now (collecting) or not (paused). |
| Response | How fast the model turns compared with the rate the stick asks for, for example "53% faster than asked". "Needs more flying" shows how much data is still needed; "Too uneven to judge" is common on pitch in 3D flying. |
| Stops | How much the model bounces back after you centre the stick, as a share of the turn rate. Needs 10 stops. |
| Suggested changes | Up to three changes, each named by the page and setting to change and in the units that page shows, for example *PIDs > Roll > F: 100 -> 80* and *Rates > Roll > RC Rate: 350 -> 440*. Make them, fly again and come back. |
| Why | The reason for each change, and a fact worth knowing when there is room (for example how much faster the model turns at high throttle). |
| Tool button | Clears the measurements after asking to confirm. |

The suggestions follow these rules:

- **Turns faster or slower than asked** (more than 15% off): change F and RC Rate by the same amount in
  opposite directions. The stick moves the surfaces as far as before, but now asks for the rate the model
  really flies. One step changes F by at most 20%.
- **Full stick asks for more roll rate than the model reaches** (roll only), with the surfaces at their limit: lower RC Rate
  to what the model reaches, or add surface throw.
- **Stops bounce back 12% or more**: if the I-term pushes back, raise *Flight Feel > Relax* by one. If F does not
  match yet, fix F first. Otherwise the controller is barely braking the stop: raise P by 20% (or add B).

## Notes

- The flight controller only measures. The suggestions are worked out on the radio from those measurements,
  so they can be improved without a firmware update.
- The measurements live in the flight controller's memory and are lost at power-off.
- Built on flight controllers with more than 128 KB of flash.

## Source

[Page implementation](../../../src/wfsuite/app/pages/tune_advisor.lua). Menu conditions come from `app/tool.lua`.
Firmware side: `src/main/flight/tune_advisor.c` in wingflight-firmware.

*Checked against WFSuite Ethos 2.3.1.*
