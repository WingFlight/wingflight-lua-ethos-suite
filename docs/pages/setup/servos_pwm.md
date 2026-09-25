---
title: "PWM Output"
sidebar_label: "PWM Output"
sidebar_position: 10
documentation_status: draft
source: app/pages/servos_pwm.lua
---

# PWM Output

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Servos* → *PWM Output*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Center | TODO: explain behaviour, displayed units, range and conditions. |
| Minimum | TODO: explain behaviour, displayed units, range and conditions. |
| Maximum | TODO: explain behaviour, displayed units, range and conditions. |
| Scale Negative | TODO: explain behaviour, displayed units, range and conditions. |
| Scale Positive | TODO: explain behaviour, displayed units, range and conditions. |
| Rate | TODO: explain behaviour, displayed units, range and conditions. |
| Speed | TODO: explain behaviour, displayed units, range and conditions. |
| Reverse | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/servos_pwm.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
