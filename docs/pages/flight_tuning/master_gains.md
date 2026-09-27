---
title: "Flight Feel"
sidebar_label: "Flight Feel"
sidebar_position: 30
documentation_status: draft
source: app/pages/master_gains.lua
---

# Flight Feel

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Flight Feel*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |
| Lock (per axis) | How long that axis holds on to a correction after a gust or bump before letting it go (the I-term decay time), in seconds (0.01-1.00, default 0.60). Longer feels more locked in; shorter feels freer and suits 3D flying. Gain sets how hard the axis pushes back, Lock sets for how long. Also an in-flight adjustment function per axis. |
| Bounce Back (per axis) | Bounce Back, 1-10 (default 5): how strongly the axis stops a fast roll, loop or snap from bouncing back when you centre the stick. Higher = less bounce-back; lower keeps more hold through long, sustained rolls and loops. Most airframes end up between 5 and 9; raise it a step at a time if the model bounces back. Also an in-flight adjustment function per axis. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/master_gains.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
