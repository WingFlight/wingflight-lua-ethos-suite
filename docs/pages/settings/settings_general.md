---
title: "General"
sidebar_label: "General"
sidebar_position: 10
documentation_status: draft
source: app/pages/settings_general.lua
---

# General

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*System* → *Settings* → *General*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| *Display* → *Tx Battery Options* | How the dashboard shows the radio's own battery. |
| *Display* → *Temperature Unit* | Celsius or Fahrenheit for temperatures on the dashboard. |
| *Display* → *Dashboard armed warning* | While the model is armed, the dashboard shows a red bar across the top with an "Armed" label. On by default. |
| *Developer* → *Developer mode* | Shows the developer tools. |
| *Safety Prompts* → *Save confirm* / *Reload confirm* | Ask before a page saves to or reloads from the flight controller. |
| *Integration* → *Sync model name* | Sets the Ethos model name to the flight controller's craft name. |
| *Integration* → *Battery profile on connect* | Offers the battery profile chooser on connect when more than one profile is set up. |

## Notes

- If the settings file cannot be written, a *Save failed* dialog is shown and the page
  stays unsaved, so *Save* remains available for a second attempt (rotorflight-lua-ethos-suite
  Issue #2500).

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_general.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
