---
title: "GPS Navigation"
sidebar_label: "GPS Navigation"
sidebar_position: 110
documentation_status: reviewed
source: app/pages/gps_nav_config.lua
---

# GPS Navigation

Set the navigation parameters used by fixed-wing RTH, Loiter and the failsafe GPS Rescue procedure.

## Where to find it

*Configuration* → *Setup* → *GPS Navigation*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| RTH Altitude | Return altitude setting, 10–500 m. |
| Loiter Radius | Loiter circle radius, 20–500 m. |
| Loiter Dir. | Clockwise or Counter-CW. |
| Min Satellites | Satellite-count threshold, 5–50. |
| Max Bank / Max Pitch | Navigation attitude limits, each 5–45 degrees. |
| Nav Throttle | Navigation throttle setting, 0–100%. |
| Bearing Gain | Bearing controller gain, 0–1000. |
| Altitude Gain | Altitude controller gain, 0–1000. |
| Altitude Damp | Altitude damping gain, 0–1000. |
| Turn Coord. | Turn coordination setting, 0–200%. |

## Notes

Save writes the complete navigation configuration and then commits to EEPROM. The page does not request a reboot or select a PID/rate profile.

Older firmware may omit the appended altitude-damping, navigation-throttle and turn-coordination fields. The page supplies fallback values, but older firmware ignores unsupported values on write. Seeing a control does not establish firmware support.

See [Failsafe Stage 2](failsafe_procedure.md) for selection of GPS Rescue.

## Source

[Page implementation](../../../src/wfsuite/app/pages/gps_nav_config.lua). Menu conditions come from `app/tool.lua`.

*Reviewed against WFSuite Ethos 2.3.1 page and shared-runtime source; not radio-tested.*
