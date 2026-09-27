---
title: "Master Gains"
sidebar_label: "Master Gains"
sidebar_position: 30
documentation_status: draft
source: app/pages/master_gains.lua
---

# Master Gains

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Master Gains*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |
| Decay (per axis) | I-term decay time: how long that axis remembers a disturbance before letting it go, in seconds (0.01-1.00, default 0.60). Longer feels more locked in; shorter feels freer and suits 3D flying. Master gain sets how hard the axis pushes back, this sets for how long. Also available as an in-flight adjustment function per axis. |
| Relax (per axis) | I-term relax cutoff in Hz (1-100, default 10): bounce-back suppression. Lower values suppress more bounce-back at the end of rolls and other fast moves; higher values keep more I-term through sustained high-rate turns. About 15-30 for small, light aircraft, 10-15 for mid-size, below 10 for large, heavy aircraft. Relax is always on for every axis. Also available as an in-flight adjustment function per axis. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/master_gains.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
