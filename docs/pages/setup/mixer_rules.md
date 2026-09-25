---
title: "Mixer Rules"
sidebar_label: "Mixer Rules"
sidebar_position: 90
documentation_status: reviewed
source: app/pages/mixer_rules.lua
---

# Mixer Rules

Edit how inputs contribute to outputs. Select a rule from the list to change its operation, routing and response.

## Where to find it

*Configuration* → *Setup* → *Mixer Rules*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Operation | None marks an unused rule; Set, Add and Multiply select how the rule combines with its output. |
| Input | Select a stabilized axis, RC command or receiver channel. Logical receiver-axis labels include the physical channel when the channel map is available. |
| Output | Destination output for the rule. |
| Offset | Rule offset, −2500 to 2500. |
| Weight / Weight (-) | Separate weights for positive and negative input, each −10,000 to 10,000 in the editor's raw scale. |
| Speed | Rule speed parameter, 0–60,000 in the editor's raw scale. |
| Curve | None or one of the eight Mixer curve slots. Edit its points under Curves. |
| Condition | None or one of the offered condition slots. |
| Role | None, Flap Compensation or Differential Thrust Yaw. |

## Notes

Saving an individual rule commits its changes to EEPROM. Rules are aircraft-wide, not PID-profile settings. No reboot is requested by this page.

**Move and Delete act immediately:** moving writes both affected slots and queues an EEPROM commit; confirming Delete clears the slot and queues an EEPROM commit. They do not wait for the editor's Save action. Rule order affects how operations combine.

Use [Mixer](mixer_config.md) for shared stabilized-axis scaling and [Curves](curves.md) for curve shapes.

## Source

[Page implementation](../../../src/wfsuite/app/pages/mixer_rules.lua). Menu conditions come from `app/tool.lua`.

*Reviewed against WFSuite Ethos 2.3.1 page and shared-runtime source; not radio-tested.*
