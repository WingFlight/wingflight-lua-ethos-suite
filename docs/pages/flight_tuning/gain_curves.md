---
title: "Gain Curves"
sidebar_label: "Gain Curves"
sidebar_position: 30
documentation_status: draft
source: app/pages/gain_curves.lua
---

# Gain Curves

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

Assigns a gain curve to each axis's Flight Feel Gain, and to Throttle. A curve shapes Gain by stick deflection on Roll, Pitch and Yaw, and by throttle on the Throttle row. Curves are an advanced shaping tool, so they live here rather than on *Flight Feel*; the curve shapes themselves are edited on *Curves*.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Gain Curves*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Roll / Pitch / Yaw | Gain curve slot (None, Curve 1-8) that shapes that axis's Flight Feel Gain by stick deflection. None applies Gain as set. |
| Throttle | Gain curve slot that shapes the Throttle gain by throttle position. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/gain_curves.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
