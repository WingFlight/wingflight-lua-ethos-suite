---
title: "Info"
sidebar_label: "Info"
sidebar_position: 50
documentation_status: draft
source: app/pages/diagnostics_info.lua
---

# Info

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*System* → *Tools* → *Diagnostics* → *Info*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Background task

The three rows at the bottom show the health of the background task, which owns the link to the flight controller, the session and the telemetry.

| Row | What it shows |
| --- | --- |
| *Background task* | *Running* while the task reports a heartbeat, *Not reporting* once the last heartbeat is more than 3 seconds old, and a dash before the first heartbeat. |
| *Heartbeat* | The age of the last heartbeat in seconds. A value that keeps growing means the task has stopped. |
| *Revivals* | How often the suite has rebuilt the task's message queue and scheduler after a stalled tick. A number that rises during a flight means the watchdog is catching a fault. |

The Lua heap and free RAM are on *Diagnostics / Status*.

## Source

[Page implementation](../../../src/wfsuite/app/pages/diagnostics_info.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
