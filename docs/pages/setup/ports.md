---
title: "Ports"
sidebar_label: "Ports"
sidebar_position: 60
documentation_status: draft
source: app/pages/ports.lua
---

# Ports

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Ports*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Load error: | TODO: explain behaviour, displayed units, range and conditions. |
| Loading serial ports... | TODO: explain behaviour, displayed units, range and conditions. |
| Save error: | TODO: explain behaviour, displayed units, range and conditions. |
| Saved; written to flash on disarm | Shown after saving while armed: the port settings were sent, but the flight controller refuses the EEPROM write while armed and commits them when you disarm. Not an error. |
| No serial ports reported by FC. | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

- A *Save* or *Reload* confirmation that is still on screen when you leave the
  page (Back, or closing the tool) is closed with the page, rather than staying
  up over the next screen with an OK button that no longer does anything.

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/ports.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
