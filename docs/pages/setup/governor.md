---
title: "Governor"
sidebar_label: "Governor"
sidebar_position: 70
documentation_status: reviewed
source: app/pages/governor.lua
---

# Governor

Configure Wingflight’s Throttle Range Governor. Mode controls which RPM, response and idle settings can be edited.

## Where to find it

*Configuration* → *Setup* → *Governor*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Mode | Off, RPM, Throttle or RPM Range. Off disables the remaining controls. |
| Target RPM | RPM mode target, 0–50,000 RPM. |
| Min RPM / Max RPM | Lower and upper targets for RPM Range mode, each 0–50,000 RPM. |
| Gain / I Gain | Governor response gains, available in RPM and RPM Range modes. Ranges: 0–20,000 and 0–200 respectively. |
| Idle floor | Powered idle floor in RPM mode, or fixed idle output in Throttle mode; 0–100%. |
| Handover | Throttle threshold for idle control in RPM and Throttle modes; 0–100%. |
| Ceiling | Governor output ceiling; 0–100%, available in all enabled modes. |

## Notes

Save writes aircraft-wide governor settings, commits to EEPROM and requests an FC reboot. The shared runtime skips the reboot request if its armed state is true; this is not a general read-only lock on the page.

Values are read from the connected FC. The control ranges describe what this editor accepts, not recommended tuning values.

## Source

[Page implementation](../../../src/wfsuite/app/pages/governor.lua). Menu conditions come from `app/tool.lua`.

*Reviewed against WFSuite Ethos 2.3.1 page and shared-runtime source; not radio-tested.*
