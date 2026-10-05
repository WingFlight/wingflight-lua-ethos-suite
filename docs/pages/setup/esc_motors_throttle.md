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
| Throttle Protocol | Which signal the flight controller uses to command the ESCs. See *Throttle Protocol* below. |
| Update frequency | TODO: explain behaviour, displayed units, range and conditions. |
| Motor Stop PWM Value | TODO: explain behaviour, displayed units, range and conditions. |
| 0% Throttle PWM Value | TODO: explain behaviour, displayed units, range and conditions. |
| 100% Throttle PWM value | TODO: explain behaviour, displayed units, range and conditions. |
| Unsynced ESC Update | TODO: explain behaviour, displayed units, range and conditions. |

## Throttle Protocol

| Protocol | Notes |
| --- | --- |
| PWM, ONESHOT125, ONESHOT42, MULTISHOT | Pulse protocols with a PWM rate and a throttle window. |
| DSHOT150, DSHOT300, DSHOT600, PROSHOT | Digital protocols. |
| CASTLE | Castle Link. |
| SRXL2 | Spektrum SRXL2 ESC. |
| DISABLED | No motor output. |

Every protocol is offered on every flight controller this suite works with. Whether a
protocol is actually available depends on how the firmware was built (DSHOT, CASTLE
and SRXL2 each sit behind a build option), and nothing tells the radio which options
are set. If a protocol is unavailable on your flight controller, the firmware refuses
it when you try to arm.

`BRUSHED` is not offered. Its number in the firmware's protocol list is a reserved
placeholder, kept so the numbers after it do not move, and the firmware does not accept
it. A flight controller that already has it stored keeps it: the row then names nothing,
and saving without touching the row writes the same value back.

*Update frequency* and the three throttle-window rows apply to PWM, ONESHOT125,
ONESHOT42, MULTISHOT, CASTLE and SRXL2, which the firmware drives as pulses. They are
greyed out for the digital protocols and for DISABLED. *Unsynced ESC Update* applies to
ONESHOT125, ONESHOT42 and MULTISHOT only.

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/esc_motors_throttle.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
