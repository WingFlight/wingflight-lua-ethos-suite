---
title: "Settings"
sidebar_label: "Settings"
sidebar_position: 20
documentation_status: draft
source: app/pages/settings_dashboard_settings.lua
---

# Settings

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*System* → *Settings* → *Dashboard* → *Settings*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

- If the settings file cannot be written, a *Save failed* dialog is shown and the page
  stays unsaved, so *Save* remains available for a second attempt (rotorflight-lua-ethos-suite
  Issue #2500).

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## KSE5

**KSE5** sets the value at which each of its rings is full. A zero or missing
value falls back to the default.

- **RPM → Max**: 500 to 20000 rpm, default 3000.
- **Current → Max**: 10 to 500 A, default 150. The ring turns to the warning
  colour above 70 % of this value and to the critical colour above 90 %.
- **ESC Temp → Max**: 40 to 150 °C, default 100, with the same colour steps.

Values are stored in the `dashboard.kse5` section of `settings.ini`.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_dashboard_settings.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
