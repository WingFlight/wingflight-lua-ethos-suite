---
title: "Att Hold"
sidebar_label: "Att Hold"
sidebar_position: 50
documentation_status: draft
source: app/pages/autolevel_attitude_hold.lua
---

# Att Hold

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Flight Modes* → *Att Hold*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Att Hold (Gain) | TODO: explain behaviour, displayed units, range and conditions. |
| Att Hold (Deadband) | TODO: explain behaviour, displayed units, range and conditions. |
| Rate | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/autolevel_attitude_hold.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
