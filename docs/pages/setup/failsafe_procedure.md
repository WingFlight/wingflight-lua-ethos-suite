---
title: "Stage 2"
sidebar_label: "Stage 2"
sidebar_position: 20
documentation_status: reviewed
source: app/pages/failsafe_procedure.lua
---

# Stage 2

Choose the Stage 2 response and its timing after receiver fallback. Per-channel fallback is configured separately.

## Where to find it

*Configuration* → *Setup* → *Controls* → *Failsafe* → *Stage 2*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Procedure | Land, Drop or GPS Rescue. |
| Switch Mode | Select Stage 1, Kill or Stage 2 for the failsafe switch behaviour. |
| Guard Delay | Delay before Stage 2, 2–200 units of 0.1 s. |
| Land Delay | Landing delay, 0–200 units of 0.1 s. |
| Low Thr. Delay | Low-throttle delay setting, 0–300 units of 0.1 s. |
| Land Throttle | Throttle value, 750–2250 µs in steps of 5 µs. |
| Recovery Delay | Recovery delay setting, 0–200 units of 0.1 s. |

## Notes

The delay fields display counts of 0.1 seconds: a value of 10 means one second.
Save writes the complete failsafe configuration and commits to EEPROM; the page does not request a reboot or select a PID/rate profile.

See [Channel Fallback](failsafe.md) for Stage 1 and [GPS Navigation](gps_nav_config.md) for GPS Rescue navigation parameters. Actual procedure support depends on the connected Wingflight firmware.

## Source

[Page implementation](../../../src/wfsuite/app/pages/failsafe_procedure.lua). Menu conditions come from `app/tool.lua`.

*Reviewed against WFSuite Ethos 2.3.1 page and shared-runtime source; not radio-tested.*
