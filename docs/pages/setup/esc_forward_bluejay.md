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

Requires a running background task and a flight controller connection. Lit only while the flight controller reports this ESC telemetry protocol (Protocol ID: 1). If that read fails, it is retried every 5 seconds.

## What Save writes

Save writes the ESC's whole 66-byte parameter block, and only the rows you moved
are changed in it.

The block carries more than this page has a row for: vendor bytes, reserved flags
and legacy encodings that a configurator app wrote. Those are read back from the
ESC and sent straight back out again, byte for byte, so a save that changed one
row leaves every other byte exactly as the ESC reported it. A row the page *does*
show is handled the same way — if you did not move it, its byte goes back
unchanged, even where the number on screen is not a direct copy of the byte.

Two rows are one decision: *96→48 % Threshold* must not sit above
*48→24 % Threshold*. Lowering *48→24 %* pulls *96→48 %* down with it, and
*96→48 %* is capped at *48→24 %*.

The bytes beyond those 66 are the flight controller's own business and are left
alone.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

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

[Page implementation](../../../src/wfsuite/app/pages/esc_forward_bluejay.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
