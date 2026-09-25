---
title: "MSP Speed"
sidebar_label: "MSP Speed"
sidebar_position: 10
documentation_status: draft
source: app/pages/developer_msp_speed.lua
---

# MSP Speed

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*System* → *Tools* → *Developer* → *MSP Speed*

Requires a running background task and a flight controller connection. Hidden until *System* → *Settings* → *Developer* mode is active.

## Settings

| Setting | What it does |
| --- | --- |
| RF protocol | TODO: explain behaviour, displayed units, range and conditions. |
| Test length | TODO: explain behaviour, displayed units, range and conditions. |
| Total queries | TODO: explain behaviour, displayed units, range and conditions. |
| Successful queries | TODO: explain behaviour, displayed units, range and conditions. |
| Timeouts | TODO: explain behaviour, displayed units, range and conditions. |
| Retries | TODO: explain behaviour, displayed units, range and conditions. |
| Checksum errors | TODO: explain behaviour, displayed units, range and conditions. |
| Minimum query time | TODO: explain behaviour, displayed units, range and conditions. |
| Maximum query time | TODO: explain behaviour, displayed units, range and conditions. |
| Average query time | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/developer_msp_speed.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
