---
title: "Tune Advisor"
sidebar_label: "Tune Advisor"
sidebar_position: 40
documentation_status: reviewed
source: app/pages/tune_advisor.lua
---

# Tune Advisor

While you fly in rate mode, the flight controller measures how the model answers the sticks. Each time you
disarm, the radio saves that flight's measurements. This page combines your last flights and suggests one change
at a time for each axis. It changes nothing by itself: make the change on *PIDs*, *Rates* or *Flight Feel*, fly
again and come back.

The flight controller counts only armed, airborne rate flight. Time in ANGLE, ATT HOLD, TRAINER, the GPS modes,
failsafe, MANUAL or PASSTHROUGH is left out. The page combines up to the last 5 flights flown with the same tune
as the newest one: a flight before a change to P, F, B, Relax or RC Rate on that axis is left out, because the
advice is worked out against the tune you fly now. A useful set is about ten seconds of rolls and pitch inputs
with the stick centred after each one, which one flight may or may not give.

## Where to find it

*Configuration* → *Flight Tuning* → *Tune Advisor*

Requires a running background task. The page works from the flights saved for the connected model, and
updates when you disarm while it is open. Without a model connected since the page opened it shows "Connect to
a model first"; once known, the model stays on screen through a link loss. On opening (and on Reload) the page
asks the flight controller once whether its firmware has the Tune Advisor: firmware from before it shows "Needs
newer firmware".

## Settings

| Line | What it shows |
| --- | --- |
| Axis | Roll, Pitch or Yaw. Everything below is for the chosen axis. On a wing the rudder response is often too uneven to judge. |
| Changes / Why | Only on 480-pixel-wide radios (X18, X18R, X10 and similar), beside Axis. *Changes* shows the suggested changes and as many reasons as fit, ending in "More under Why" when some are left out; *Why* shows all the reasons. Larger radios show everything. |
| Flight data | Minutes and seconds of rate flight in the flights combined, and how many of the last 5 that is, for example "1m 53s, 2/5 flights". |
| Response | How fast the model turns compared with the rate the stick asks for, for example "53% faster than asked". "Needs more flying" shows how much data is still needed; "Too uneven to judge" is common on pitch in 3D flying. |
| Stops | How much the model bounces back after you centre the stick, as a share of the turn rate. Needs 10 stops. |
| Suggested changes | Up to three changes, each named by the page and setting to change and in the units that page shows, for example *PIDs > Roll > F: 100 -> 80* and *Rates > Roll > RC Rate: 350 -> 440*. Make them, fly again and come back. |
| Why | The reason for each change, and a fact worth knowing when there is room (for example how much faster the model turns at high throttle). |
| Tool button | Erases this model's saved flights, and the flight controller's current measurements, after asking to confirm. |

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
- Each time you disarm, the background task reads all three axes from the flight controller, saves them as
  one flight, then clears the flight controller so the next flight is measured on its own. This happens
  whether or not this page is open. The flights are kept in `LOGS:/wfsuite/tune/<model>/history.csv` on the
  radio's SD card, one row per axis, newest last; only the last 5 flights are kept. `<model>` is the same
  flight controller ID that names the flight log folders, and a `logs.ini` beside the history holds the model
  name.
- A flight without rate flight is not saved. A disarm while the link is down is saved once the radio
  reconnects, provided the flight controller has not been powered off in between.
- Combining flights adds up the counts and averages each measurement weighted by how much data it came from.
  The flight controller weights its own figures slightly differently, so the combined response is a close
  estimate rather than exact; the stop figures combine exactly.
- Built on flight controllers with more than 128 KB of flash.

## Source

[Page implementation](../../../src/wfsuite/app/pages/tune_advisor.lua). Menu conditions come from `app/tool.lua`.
Firmware side: `src/main/flight/tune_advisor.c` in wingflight-firmware.

*Checked against WFSuite Ethos 2.3.1.*
