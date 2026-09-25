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
| Wingflight ActiveLook | TODO: explain behaviour, displayed units, range and conditions. |
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
