---
title: "Alignment"
sidebar_label: "Alignment"
sidebar_position: 50
documentation_status: draft
source: app/pages/alignment.lua
---

# Alignment

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Alignment*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

Below the settings, a 3D aircraft shows the live attitude from the flight
controller with the offsets in the fields applied, including edits not yet
saved. It is the same aerobatic plane the Configurator shows: red body, dark
ailerons, elevator and rudder, white spinner and landing gear. The view is from
behind and slightly above, so the top of the wing shows when the model is level.
The tool button turns the view so the tail faces you again.

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/alignment.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
