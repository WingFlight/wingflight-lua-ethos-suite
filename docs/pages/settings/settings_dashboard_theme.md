---
title: "Themes"
sidebar_label: "Themes"
sidebar_position: 10
documentation_status: draft
source: app/pages/settings_dashboard_theme.lua
---

# Themes

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*System* → *Settings* → *Dashboard* → *Themes*

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

## KSE4 and KSE5

**KSE4** (`system/kse4`) and **KSE5** (`system/kse5`) follow the layouts of
Kyle Stacy's [KSE dashboards](https://github.com/kylestacy2/KSE-Dashboards).
They draw every tile in the Ethos theme's colours, so the radio's theme picks
the palette. Each has its own preflight, inflight and postflight screen.

**KSE4** is a tile dashboard.

- **Preflight**: model image and flight count, a large RPM tile beside the
  flight timer, and a strip with current, pack voltage, BEC voltage and ESC
  temperature. The bottom row has the governor and a battery or fuel bar.
- **Inflight**: large RPM and timer tiles, a strip with current, cell voltage,
  ESC temperature and throttle, then the governor and the fuel bar.
- **Postflight**: flight time, consumed mAh and remaining fuel across the top,
  then the flight's peaks and lows: maximum RPM, current, power, throttle and
  ESC temperature, and minimum cell voltage, BEC voltage and link.

**KSE5** is a ring dashboard.

- **Preflight**: four rings for battery or fuel, RPM, current and ESC
  temperature. Below them are the model image, the flight count, and tiles for
  the governor, BEC voltage, cell voltage and consumed mAh.
- **Inflight**: a large battery or fuel ring, smaller RPM and ESC temperature
  rings with the timer and governor below them, and a row with current, cell
  voltage, BEC voltage and throttle.
- **Postflight**: rings for the lowest fuel and the highest RPM, current and
  ESC temperature, then flight time, consumed mAh, minimum cell and BEC
  voltage, maximum power and minimum link.

Set the full-scale RPM, current and ESC temperature of the KSE5 rings in
[Dashboard Settings](settings_dashboard_settings.md). Postflight figures fill
in once a flight has been recorded.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_dashboard_theme.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
