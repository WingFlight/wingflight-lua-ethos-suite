---
title: "Modes"
sidebar_label: "Modes"
sidebar_position: 10
documentation_status: draft
source: app/pages/modes.lua
---

# Modes

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Controls* → *Modes*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Range | TODO: explain behaviour, displayed units, range and conditions. |
| Loading mode data... | TODO: explain behaviour, displayed units, range and conditions. |
| Load error: | TODO: explain behaviour, displayed units, range and conditions. |
| No modes reported by FC. | TODO: explain behaviour, displayed units, range and conditions. |
| Mode | TODO: explain behaviour, displayed units, range and conditions. |
| Active ranges: | TODO: explain behaviour, displayed units, range and conditions. |
| Auto-detect active: toggle desired AUX channel | TODO: explain behaviour, displayed units, range and conditions. |
| Save error: | TODO: explain behaviour, displayed units, range and conditions. |
| No ranges configured for this mode. | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/modes.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
