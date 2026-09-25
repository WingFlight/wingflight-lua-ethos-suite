---
title: "Filters"
sidebar_label: "Filters"
sidebar_position: 10
documentation_status: draft
source: app/pages/filters.lua
---

# Filters

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Filters*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| LPF1 Type | TODO: explain behaviour, displayed units, range and conditions. |
| LPF1 Cutoff | TODO: explain behaviour, displayed units, range and conditions. |
| LPF1 Dynamic (Min) | TODO: explain behaviour, displayed units, range and conditions. |
| LPF1 Dynamic (Max) | TODO: explain behaviour, displayed units, range and conditions. |
| LPF2 Type | TODO: explain behaviour, displayed units, range and conditions. |
| LPF2 Cutoff | TODO: explain behaviour, displayed units, range and conditions. |
| Notch 1 (Center) | TODO: explain behaviour, displayed units, range and conditions. |
| Notch 1 (Cutoff) | TODO: explain behaviour, displayed units, range and conditions. |
| Notch 2 (Center) | TODO: explain behaviour, displayed units, range and conditions. |
| Notch 2 (Cutoff) | TODO: explain behaviour, displayed units, range and conditions. |
| Dyn Notch (Count) | TODO: explain behaviour, displayed units, range and conditions. |
| Dyn Notch (Q) | TODO: explain behaviour, displayed units, range and conditions. |
| Dyn Notch Range (Min) | TODO: explain behaviour, displayed units, range and conditions. |
| Dyn Notch Range (Max) | TODO: explain behaviour, displayed units, range and conditions. |
| RPM Preset | TODO: explain behaviour, displayed units, range and conditions. |
| RPM Min Hz | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/filters.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
