---
title: "Adjustments"
sidebar_label: "Adjustments"
sidebar_position: 20
documentation_status: draft
source: app/pages/adjustments.lua
---

# Adjustments

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Controls* → *Adjustments*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Loading adjustment data... | TODO: explain behaviour, displayed units, range and conditions. |
| Active ranges: | TODO: explain behaviour, displayed units, range and conditions. |
| Save error: | TODO: explain behaviour, displayed units, range and conditions. |
| Unsaved changes | TODO: explain behaviour, displayed units, range and conditions. |
| Auto-detect active: toggle desired AUX channel | TODO: explain behaviour, displayed units, range and conditions. |
| Range | TODO: explain behaviour, displayed units, range and conditions. |
| Type | TODO: explain behaviour, displayed units, range and conditions. |
| Function | TODO: explain behaviour, displayed units, range and conditions. |
| Enable Channel | TODO: explain behaviour, displayed units, range and conditions. |
| Value Channel | TODO: explain behaviour, displayed units, range and conditions. |
| Step Size | TODO: explain behaviour, displayed units, range and conditions. |
| Value Range | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/adjustments.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
