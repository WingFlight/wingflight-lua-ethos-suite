---
title: "Status"
sidebar_label: "Status"
sidebar_position: 30
documentation_status: draft
source: app/pages/blackbox_status.lua
---

# Status

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*Configuration* → *Setup* → *Controls* → *Blackbox* → *Status*

Requires a running background task and a flight controller connection.

## Erasing the dataflash

The Tool button erases the dataflash after a confirmation. It is off on a board
without dataflash, until the board reports the dataflash as ready, and while an
erase runs. The erase dialog closes once the dataflash summary taken after the
erase answers: the flash is ready, or the board reports no dataflash. A failed
dataflash read does not end the wait, and an erase that reports an error leaves
the flash not ready until a read says otherwise, so the page never reports an
erase as finished on a reading from before it.

## Settings

| Setting | What it does |
| --- | --- |
| Dataflash | TODO: explain behaviour, displayed units, range and conditions. |
| SD Card | TODO: explain behaviour, displayed units, range and conditions. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../../src/wfsuite/app/pages/blackbox_status.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
