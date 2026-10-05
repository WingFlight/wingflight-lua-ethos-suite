---
title: "Gain Curves"
sidebar_label: "Gain Curves"
sidebar_position: 30
documentation_status: draft
source: app/pages/thrust_vector_gain_curves.lua
---

# Gain Curves

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

Assigns a gain curve to each axis's thrust-vector Flight Feel Gain, from the same shared pool as the main loop (*Curves*). The thrust-vector Gain also scales F, so its curve does too. The thrust-vector loop has no throttle curve.

## Where to find it

*Configuration* → *Flight Tuning* → *Thrust Vector* → *Gain Curves*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Roll / Pitch / Yaw | Gain curve slot (None, Curve 1-8) that shapes that axis's thrust-vector Gain by stick deflection. None applies Gain as set. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/thrust_vector_gain_curves.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
