---
title: "Servos"
sidebar_label: "Servos"
sidebar_position: 120
documentation_status: reviewed
source: app/pages/servos.lua
---

# Servos

Set up each servo's center, travel limits, scale, speed and direction, and trim a
center live.

A servo is a servo, however it is connected. There are 24 servos. Servo N is sent on
PWM output N where the board has one, and on channel N of a bus output (SBUS or F.Bus)
when one is set up, and it is set up the same way either way. There are no separate
PWM and BUS pages any more.

## Where to find it

*Configuration* → *Setup* → *Servos*

Requires a running background task and a flight controller connection. The flight
controller firmware must support MSP API 22.16 or newer; the suite refuses older
firmware when it connects.

## The list

One tile per servo in use, **SERVO 1** first. The servos in use are servo 1 up to the
larger of the board's PWM servo outputs and the servos a bus output sends: the bus
channel count (8, 12 or 24), or 18 with a 16-channel frame, where servos 17 and 18
drive the frame's two digital channels. Tap a tile to edit that servo.

The Tool button in the header switches servo override on for every servo: all of them
go to their configured center, for setting up linkages. Switching it off, or leaving
the page, returns the servos to the flight controller and saves the servo settings.

## Settings

Each servo has the same settings and the same ranges.

| Setting | What it does |
| --- | --- |
| Center | Pulse width at the middle of the travel, 1000–2000 µs. Default 1500. |
| Minimum | Travel limit below the center, as an offset from it: −1000 to 0 µs. Default −600. |
| Maximum | Travel limit above the center, as an offset from it: 0 to 1000 µs. Default 600. |
| Scale Negative | Travel in µs for a full negative mixer output, 50–1000. Default 500. |
| Scale Positive | Travel in µs for a full positive mixer output, 50–1000. Default 500. |
| Speed | Speed limit of the servo, 0–60000 ms. 0 is no limit. |
| Reverse | Reverses the servo's direction. |

The servo signal always stays between 880 and 2159 µs, on a PWM output and on a bus
alike. Minimum and Maximum are stored as set, and the flight controller shortens the
travel it uses where center plus the limit would leave that range. With the center at
1500, a Maximum above 659 has no further effect.

Narrow-pulse (760 µs) servos are not supported. There is no update rate per servo.

The PWM update rate of the servo outputs is one setting for all of them, 50 Hz by
default, which suits any servo. This page does not offer it. The setup wizard's servo
type step sets it (analog 50 Hz, digital 333 Hz), and so does the Configurator's
Servos tab.

## Notes

- Save in a servo's editor writes that servo and commits it to EEPROM. It does not
  restart the flight controller. Servo settings are aircraft-wide, independent of
  the selected PID or rate profile.
- The Tool button is disabled until the page has loaded its values.
- In the servo editor, the Tool button switches servo override on for that servo
  alone, and only after the page has read its values; until then, confirming the
  enable dialog does not enable an override (rotorflight-lua-ethos-suite PR #2552,
  Issue #2496). While it is on, Center is written to the flight controller as you
  change it, so the servo follows, and the other fields are locked.
- An override lapses on the flight controller by itself if the radio is switched off
  or the link drops.
- Geometry correction is kept as stored; the page has no field for it.
- Settings stored by firmware older than MSP API 22.16 are reset by the firmware
  upgrade, so the servos need setting up again after it. On that firmware S9 and above
  were bus channels 1 and up; now servo 9 is bus channel 9.

## Source

[Page implementation](../../../src/wfsuite/app/pages/servos.lua). Menu conditions come from `app/tool.lua`.

*Reviewed against WFSuite Ethos 2.3.1 page and shared-runtime source and the
wingflight-firmware MSP API 22.16 servo messages; not radio-tested.*
