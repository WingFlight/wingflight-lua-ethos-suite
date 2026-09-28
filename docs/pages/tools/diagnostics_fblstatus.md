---
title: "FBL Status"
sidebar_label: "FBL Status"
sidebar_position: 30
documentation_status: draft
source: app/pages/diagnostics_fblstatus.lua
---

# FBL Status

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*System* → *Tools* → *Diagnostics* → *FBL Status*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Arming flags

*Arming Flags* shows **OK** in green while nothing stops the model arming.
When the flight controller reports reasons, it shows how many in red (for
example "3 active"), and lists the reasons one per line at the bottom of the
page, under *Active reasons:*, lowest flag first.

The reasons get lines of their own because the value column is only the right
half of a row and doesn't wrap: with a few reasons joined there, the one
blocking arming could be cut off the right edge, especially on 480×320 radios.

- **Arm Switch** is listed only when it is the only reason: the arm switch was
  on at power-up or after disarming, and has to be switched off. Next to
  another reason it just means the switch is on, so it is left out.
- A reason this version of the suite has no name for is shown as its raw flag
  value (for example `0x40000000`) rather than hidden.
- A reason cleared while the page is open leaves an empty line until you leave
  and re-open the page.

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/diagnostics_fblstatus.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
