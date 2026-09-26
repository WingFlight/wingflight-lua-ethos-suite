---
title: "Curves"
sidebar_label: "Curves"
sidebar_position: 100
documentation_status: reviewed
source: app/pages/curves.lua
---

# Curves

Choose Mixer, Gain or Servo, select a slot, then edit its points. The graph previews changes; use the number fields to edit it.

## Where to find it

*Configuration* → *Setup* → *Curves*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Category / slot | Mixer and Gain each have eight slots. Servo has one curve per servo returned by the FC. |
| Points | Active point count: 2–9 for Mixer and Servo, 2–6 for Gain. Fields beyond the active count are disabled. |
| X / Y: Mixer | Input/output point coordinates, each −1000 to 1000. |
| X / Y: Gain | Input 0–1000 and gain 0–500. |
| X / Y: Servo | Input −1000 to 1000 and corrective output delta −100 to 100. |

## Notes

Save writes the selected curve and commits to EEPROM. Curves are not scoped to the selected PID profile, and this page does not request a reboot.

[Mixer Rules](mixer_rules.md) selects Mixer curve slots. [Master Gains](../flight_tuning/master_gains.md) selects Gain curve slots. Servo curves apply to their corresponding servo without a separate slot assignment.

## Source

[Page implementation](../../../src/wfsuite/app/pages/curves.lua). Menu conditions come from `app/tool.lua`.

*Reviewed against WFSuite Ethos 2.3.1 page and shared-runtime source; not radio-tested.*
