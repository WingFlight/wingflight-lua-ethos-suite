---
title: "PID Controller"
sidebar_label: "PID Controller"
sidebar_position: 30
documentation_status: draft
source: app/pages/thrust_vector_pid_controller.lua
---

# PID Controller

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Thrust Vector* → *PID Controller*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| In-flight Error Decay (Time) | TODO: explain behaviour, displayed units, range and conditions. |
| In-flight Error Decay (Limit) | TODO: explain behaviour, displayed units, range and conditions. |
| Iterm Relax: Type | TODO: explain behaviour, displayed units, range and conditions. |
| Iterm Relax Level (R) | TODO: explain behaviour, displayed units, range and conditions. |
| Iterm Relax Level (P) | TODO: explain behaviour, displayed units, range and conditions. |
| Iterm Relax Level (Y) | TODO: explain behaviour, displayed units, range and conditions. |
| Iterm Relax Cutoff (R) | TODO: explain behaviour, displayed units, range and conditions. |
| Iterm Relax Cutoff (P) | TODO: explain behaviour, displayed units, range and conditions. |
| Iterm Relax Cutoff (Y) | TODO: explain behaviour, displayed units, range and conditions. |
| Error Limit (R) | TODO: explain behaviour, displayed units, range and conditions. |
| Error Limit (P) | TODO: explain behaviour, displayed units, range and conditions. |
| Error Limit (Y) | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/thrust_vector_pid_controller.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
