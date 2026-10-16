---
title: "Battery"
sidebar_label: "Battery"
sidebar_position: 10
documentation_status: draft
source: app/pages/power_battery.lua
---

# Battery

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Power* → *Battery*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Profiles | TODO: explain behaviour, displayed units, range and conditions. |
| @i18n(app.modules.power.selected)@ | TODO: explain behaviour, displayed units, range and conditions. |
| @i18n(app.modules.power.edit_battery)@ | Chooses the profile whose capacity, cell count and cell voltages the rows below show and edit. It does not change the active profile. |
| @i18n(app.modules.power.capacity)@ | TODO: explain behaviour, displayed units, range and conditions. |
| Battery | TODO: explain behaviour, displayed units, range and conditions. |
| @i18n(app.modules.power.consumption_warning_percentage)@ | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

- The capacity, the cell count and the four cell voltage thresholds follow
  *Edit Battery*, not the active profile. Editing another profile's values therefore
  does not make that profile active when you save (rotorflight-lua-ethos-suite
  Issue #2502). *Profiles* stays on the active profile.
- *Edit Battery* starts on the active profile when the page loads, and when the
  active profile changes.

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/power_battery.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
