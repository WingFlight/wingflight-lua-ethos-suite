---
title: "PID Bandwidth"
sidebar_label: "PID Bandwidth"
sidebar_position: 40
documentation_status: draft
source: app/pages/thrust_vector_pid_bandwidth.lua
---

# PID Bandwidth

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Thrust Vector* → *PID Bandwidth*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Gyro Cutoff (R) | TODO: explain behaviour, displayed units, range and conditions. |
| Gyro Cutoff (P) | TODO: explain behaviour, displayed units, range and conditions. |
| Gyro Cutoff (Y) | TODO: explain behaviour, displayed units, range and conditions. |
| D-term Cutoff (R) | TODO: explain behaviour, displayed units, range and conditions. |
| D-term Cutoff (P) | TODO: explain behaviour, displayed units, range and conditions. |
| D-term Cutoff (Y) | TODO: explain behaviour, displayed units, range and conditions. |
| B-term Cutoff (R) | TODO: explain behaviour, displayed units, range and conditions. |
| B-term Cutoff (P) | TODO: explain behaviour, displayed units, range and conditions. |
| B-term Cutoff (Y) | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/thrust_vector_pid_bandwidth.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
