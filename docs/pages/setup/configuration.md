---
title: "Configuration"
sidebar_label: "Configuration"
sidebar_position: 10
documentation_status: draft
source: app/pages/configuration.lua
---

# Configuration

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Configuration*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Craft name | TODO: explain behaviour, displayed units, range and conditions. |
| PID loop speed | TODO: explain behaviour, displayed units, range and conditions. |
| LED_STRIP | TODO: explain behaviour, displayed units, range and conditions. |
| THRUST_VECTORING | TODO: explain behaviour, displayed units, range and conditions. |
| ARM_WIGGLE | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

- Saving changes on this page reboots the flight controller.
- There is no GPS switch. GPS runs when the GPS source matches a port on *Ports*: NMEA or UBLOX with a GPS port, FBUS with an FBUS or S.Port master port, CRSF with a CRSF sensors port, or MSP with no port.
- While the model is armed, or while its armed state is *unknown after having been armed*, Save stays greyed out. The reboot after a save is skipped in that state.
- Changes are written to the flight controller EEPROM upon Save.

## Source

[Page implementation](../../../src/wfsuite/app/pages/configuration.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
