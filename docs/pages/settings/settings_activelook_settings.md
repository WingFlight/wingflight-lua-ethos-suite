---
title: "Settings"
sidebar_label: "Settings"
sidebar_position: 10
documentation_status: draft
source: app/pages/settings_activelook_settings.lua
---

# Settings

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*System* → *Settings* → *ActiveLook* → *Settings*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| ETHOS Glasses menu | Registers the ETHOS Model → Glasses menu at startup (default off). Only shown on ETHOS 26.2.0 or newer when the firmware provides `system.registerGlasses()`. Changing it in either direction shows a restart reminder dialog. Save and restart the transmitter to apply either direction. Stored as `register_glasses`, separately from the display preference; disabling it leaves the icon visible until a transmitter restart, and another installed script can still register the menu. |
| Wingflight ActiveLook | Enables the Wingflight glasses display. Disabled while the visible ETHOS Glasses menu switch is off; existing display preferences are retained. If the ETHOS Glasses menu switch is unavailable, this restriction does not apply. Switching it on shows a setup reminder: in Model → Glasses → Screen, select the Full-Screen layout and assign Wingflight ActiveLook. |
| Hide Display | TODO: explain behaviour, displayed units, range and conditions. |
| Offset X | TODO: explain behaviour, displayed units, range and conditions. |
| Offset Y | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_activelook_settings.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
