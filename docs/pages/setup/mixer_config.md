---
title: "Mixer"
sidebar_label: "Mixer"
sidebar_position: 80
documentation_status: reviewed
source: app/pages/mixer_config.lua
---

# Mixer

Scale or invert stabilized roll, pitch and yaw before mixer rules use them. This changes every rule that reads the selected stabilized axis.

## Where to find it

*Configuration* → *Setup* → *Mixer*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Roll / Pitch / Yaw: Gain | Axis input gain, 0–200%, adjusted in steps of 5%. |
| Roll / Pitch / Yaw: Invert | Select Normal or Inverted to change the sign of the axis input. |

## Notes

Save writes all three axis input settings and commits them to EEPROM. These are aircraft-wide settings, independent of the selected PID or rate profile. This page does not request a reboot.

The stored input limits are preserved when saving. To edit which outputs receive an input, use [Mixer Rules](mixer_rules.md).

## Source

[Page implementation](../../../src/wfsuite/app/pages/mixer_config.lua). Menu conditions come from `app/tool.lua`.

*Reviewed against WFSuite Ethos 2.3.1 page and shared-runtime source; not radio-tested.*
