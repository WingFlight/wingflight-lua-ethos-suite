---
title: "Logs"
sidebar_label: "Logs"
sidebar_position: 10
documentation_status: draft
source: app/pages/logs.lua
---

# Logs

> Draft scaffold. Extracted labels may be incomplete or out of order. Behaviour,
> displayed units, defaults and save effects require source review.

TODO: Explain what this page controls and when a pilot would use it.

## Where to find it

*System* → *Logs*

Available without a flight controller connection; the background task must be running.

## One flight, one log

A log opens when the model arms and closes when it disarms. A short loss of
telemetry while the model is still armed (behind an obstacle, or on a fast
pass) no longer splits the flight into two logs, so the peaks the viewer shows
are those of the whole flight. The time without a link isn't counted as flight
time.

Two things still end a log and start a new one:

* **Disarming.** A log always ends when you disarm, whether the link stayed up
  or not, so landing, disarming and arming again always gives a separate log.
* **A gap longer than 30 seconds.** If the link is gone for longer than that,
  the flight is closed rather than resumed.

The flight timer and the flight count in the model statistics follow the same
rule, so a flight that briefly loses the link is counted once.

## Settings

| Setting | What it does |
| --- | --- |
| TODO | Inspect the page and its helpers; automatic extraction found no controls. |

## Notes

TODO: Verify persistence, reboot behaviour, profile scope and any restrictions in
this page and its shared helpers. Codec defaults may be UI fallbacks rather than
firmware defaults; wire values may need scaling before display.

## Source

[Page implementation](../../src/wfsuite/app/pages/logs.lua). Menu conditions come from `app/tool.lua`.

*Scaffolded against WFSuite Ethos 2.3.1; content awaiting review.*
