---
title: "Throttle"
sidebar_label: "Throttle"
sidebar_position: 10
documentation_status: draft
source: app/pages/esc_motors_throttle.lua
---

# Throttle

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *ESC & Motors* → *Throttle*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Throttle Protocol | Which signal the FC uses to command the ESCs. The list follows the flight controller's own enum - see below. |
| Update frequency | TODO: explain behaviour, displayed units, range and conditions. |
| Motor Stop PWM Value | TODO: explain behaviour, displayed units, range and conditions. |
| 0% Throttle PWM Value | TODO: explain behaviour, displayed units, range and conditions. |
| 100% Throttle PWM value | TODO: explain behaviour, displayed units, range and conditions. |
| Unsynced ESC Update | TODO: explain behaviour, displayed units, range and conditions. |

## Throttle Protocol

Every value on this row comes from the flight controller's own enum
(`drivers/motor.h`), not from a table in the transmitter suite:

| Protocol | Value |
| --- | --- |
| PWM | 0 |
| ONESHOT125 | 1 |
| ONESHOT42 | 2 |
| MULTISHOT | 3 |
| DSHOT150 | 5 |
| DSHOT300 | 6 |
| DSHOT600 | 7 |
| PROSHOT | 8 |
| CASTLE | 9 |
| SRXL2 | 10 |
| DISABLED | 11 |

`DISABLED` switches the motor output off. It is the last entry in the enum.

**The firmware decides what is actually supported by how it was built**, not by its
version number: DSHOT, CASTLE and SRXL2 are each behind a build flag
(`USE_DSHOT`, `USE_TELEMETRY_CASTLE`, `USE_SRXL2_ESC`). Nothing in the protocol tells the
transmitter which flags are set, so if a protocol turns out to be unavailable on your
flight controller the firmware says so when you try to arm.

`BRUSHED` is **not** offered. That slot was removed from the firmware years ago and
kept as a placeholder so the numbers after it would not move; a flight controller
configured with it reports the motor output as not enabled.

> A pilot whose flight controller still has the old reserved value stored sees a
> Throttle Protocol row that names nothing. Nothing is lost by saving - the value comes
> back unchanged - but it cannot be read on that row.

*Update frequency* and the three throttle-window rows (*Motor Stop PWM Value*,
*0% Throttle PWM Value*, *100% Throttle PWM value*) apply to PWM, ONESHOT125, ONESHOT42,
MULTISHOT, CASTLE and SRXL2, which the firmware drives as pulses - CASTLE and SRXL2 as
standard 1 ms PWM. They are greyed out for the digital protocols (DSHOT150, DSHOT300,
DSHOT600, PROSHOT) and for DISABLED. *Unsynced ESC Update* applies to ONESHOT125,
ONESHOT42 and MULTISHOT only.

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/esc_motors_throttle.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
