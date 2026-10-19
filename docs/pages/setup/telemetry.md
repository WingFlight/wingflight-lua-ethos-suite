---
title: "Telemetry"
sidebar_label: "Telemetry"
sidebar_position: 30
documentation_status: draft
source: app/pages/telemetry.lua
---

# Telemetry

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Telemetry*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

- **Native CRSF sensors are locked while the flight controller is in native
  mode.** The flight controller's built-in native CRSF set includes *Altitude*,
  *Attitude (Combined)*, their parent/child conflicts, the native *Flight
  mode*, and the per-axis children *Pitch Attitude*, *Roll Attitude* and *Yaw
  Attitude*. The flight controller sends those as whole CRSF frames in that
  mode whether a slot selects them or not, so their switches read as on, stay
  greyed out and ignore taps. Beside each of these switches, the word *native*
  shows while the flight controller is in native mode. This is not a fault —
  those sensors really are being sent. The lock applies only in native mode: in custom mode all of them
  are ordinary selectable sensors, and the page gives them back.
- **Save keeps sensors this page has no switch for.** The flight controller
  has 40 telemetry slots. A slot holding a sensor the page doesn't list (for
  example GPS, a second ESC, or a temperature sensor set from the
  configurator) keeps its sensor and its position when you save. The switches
  you turn on fill the remaining slots. Before this, saving cleared those
  slots.
- **No more than 40 sensors in total**, counting the kept slots. Turning on a
  switch that would go over is refused with a dialog. If the default set from
  the Tool button would go over, saving shows the same dialog and leaves the
  flight controller's sensor slots as they were. The save counts the same slots,
  so the tap and the save agree on the number. One case is still refused at the
  tap: a switch that turns off a conflicting child while all 40 slots are in use,
  even when the save would accept the result.
- **Saving sets the flight controller's CRSF telemetry mode to Custom.** The
  suite reads custom CRSF telemetry only, so in Native mode it would see no
  sensors. This page has no control for the mode.

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/telemetry.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
