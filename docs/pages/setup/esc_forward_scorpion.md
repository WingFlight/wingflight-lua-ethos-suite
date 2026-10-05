---
title: "Scorpion"
sidebar_label: "Scorpion"
sidebar_position: 70
documentation_status: draft
source: app/pages/esc_forward_scorpion.lua
---

# Scorpion

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *ESC & Motors* → *ESC Prog.* → *Scorpion*

Requires a running background task and a flight controller connection. Lit only while the flight controller reports this ESC telemetry protocol (Protocol ID: 4). If that read fails, it is retried every 5 seconds.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

- The line under the title names the model, the firmware version and the ESC's
  own **serial number**, so two ESCs of the same model can be told apart. An ESC
  that reports `0` for it shows no serial at all: a printed `S/N 0` would read
  like data and identify nothing. Ported from rotorflight-lua-ethos-suite#2469.

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Choosing the ESC

If the flight controller reports more than one ESC, this page lists them and you
pick the one to program. The list has one entry per ESC that is actually there.

With a single ESC there is nothing to choose, so the list is skipped and the page
goes straight to that ESC.

If the flight controller does not say how many ESCs there are, all four entries are
listed and only *ESC 1* can be opened. The page does not guess.

## Source

[Page implementation](../../../src/wfsuite/app/pages/esc_forward_scorpion.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
