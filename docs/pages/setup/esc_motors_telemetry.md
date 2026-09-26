---
title: "Telemetry"
sidebar_label: "Telemetry"
sidebar_position: 20
documentation_status: draft
source: app/pages/esc_motors_telemetry.lua
---

# Telemetry

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *ESC & Motors* → *Telemetry*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Telemetry Protocol | TODO: explain behaviour, displayed units, range and conditions. |
| Half Duplex | TODO: explain behaviour, displayed units, range and conditions. |
| Pin Swap | TODO: explain behaviour, displayed units, range and conditions. |
| Voltage Correction | TODO: explain behaviour, displayed units, range and conditions. |
| Current Correction | TODO: explain behaviour, displayed units, range and conditions. |
| Consumption Correction | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/esc_motors_telemetry.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
