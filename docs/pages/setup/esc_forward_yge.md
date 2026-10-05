---
title: "YGE"
sidebar_label: "YGE"
sidebar_position: 90
documentation_status: draft
source: app/pages/esc_forward_yge.lua
---

# YGE

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *ESC & Motors* → *ESC Prog.* → *YGE*

Requires a running background task and a flight controller connection. Lit only while the flight controller reports this ESC telemetry protocol (Protocol ID: 9). If that read fails, it is retried every 5 seconds.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

- *Motor Timing* is shown in the ESC's own terms, not as a list position: the
  four automatic modes (*Auto Norm*, *Auto Eff*, *Auto Power*, *Auto Extr*) and
  the six fixed advance angles (*0 deg* .. *30 deg*) are translated to and from
  the word the ESC actually uses, and a row you did not touch is written back
  with the word it was read with.
- *BEC Voltage* goes up to **12.0 V** on the models that have an HV BEC, and stays
  at **8.4 V** on the ones that do not. The ceiling follows the ESC that answered;
  an ESC this page has no entry for is treated as an 8.4 V one.
- The *BEC Voltage* row is **hidden** on an Opto model, which has no BEC.
- The line under the title names the model, the firmware version and the ESC's
  own **serial number**, so two ESCs of the same model can be told apart --
  which is what you want when one of four behaves differently. An ESC that
  reports `0` for it shows no serial at all: a printed `S/N 0` would read like
  data and identify nothing. Ported from rotorflight-lua-ethos-suite#2469.

### 12 V BEC and the HV-BEC flag

The HV-BEC flag is not a row of its own. It follows the BEC Voltage, in one
direction only:

| You do | The flag becomes |
| --- | --- |
| move the voltage **to 12.0 V** | set |
| move the voltage **to anything below 12.0 V** | cleared |
| do not touch the voltage | left exactly as the ESC reported it |

So selecting 11.9 V clears the flag, and a save that changed some other setting
leaves it alone.

Models with a **12 V** BEC (not only v2 models; the HVTs are among them):
*YGE 165 HVT*, *YGE 205 HVT v2*, *YGE 205 HVT BEC*, *YGE Aureus 105v2*,
*YGE Aureus 135v2*, *YGE Saphir 125v2*, *YGE Saphir 155v2*.

Models with **no BEC**, where the row is hidden: *YGE 90 HVT Opto*,
*YGE 120 HVT Opto*, *YGE Opto 135*, *YGE Opto 255*, *YGE Opto 405*.

Every other YGE model has a BEC and is offered up to 8.4 V.

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

[Page implementation](../../../src/wfsuite/app/pages/esc_forward_yge.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
