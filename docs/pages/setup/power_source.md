---
title: "Sources"
sidebar_label: "Sources"
sidebar_position: 30
documentation_status: draft
source: app/pages/power_source.lua
---

# Sources

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Power* → *Sources*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Voltage Source | TODO: explain behaviour, displayed units, range and conditions. |
| Current Source | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/power_source.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
