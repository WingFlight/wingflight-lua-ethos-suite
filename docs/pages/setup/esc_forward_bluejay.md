---
title: "Bluejay"
sidebar_label: "Bluejay"
sidebar_position: 40
documentation_status: draft
source: app/pages/esc_forward_bluejay.lua
---

# Bluejay

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *ESC & Motors* → *ESC Prog.* → *Bluejay*

Requires a running background task and a flight controller connection. Lit only while the flight controller reports this ESC telemetry protocol (Protocol ID: 1).

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/esc_forward_bluejay.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
