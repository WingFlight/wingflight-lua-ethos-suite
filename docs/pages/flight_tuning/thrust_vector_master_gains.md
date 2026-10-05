---
title: "Flight Feel"
sidebar_label: "Flight Feel"
sidebar_position: 20
documentation_status: draft
source: app/pages/thrust_vector_master_gains.lua
---

# Flight Feel

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Flight Tuning* → *Thrust Vector* → *Flight Feel*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |
| Gain (per axis) | Master gain, 0-200 % (default 100): scales that axis's P, I and D, so how hard it pushes back against a gust or bump. 0 % turns the stabilizer off on that axis; the sticks still move the surfaces. Also an in-flight adjustment function per axis, so a pot can turn it down to 0 %. |
| Decay (per axis) | How long that axis holds on to a correction after a gust or bump before letting it go (I-term decay time), in seconds (0.01-1.00, default 0.60). Longer feels more locked in; shorter feels freer and suits 3D flying. Master Gain sets how hard the axis pushes back, I-term Decay sets for how long. Also an in-flight adjustment function per axis. |
| Relax (per axis) | I-term Relax, 1-10 (default 5): how strongly the axis stops a fast roll, loop or snap from bouncing back when you centre the stick. Higher = more relax, so less bounce-back; lower keeps more hold through long, sustained rolls and loops. Most airframes end up between 5 and 9; raise it a step at a time if the model bounces back. Also an in-flight adjustment function per axis. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/thrust_vector_master_gains.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
