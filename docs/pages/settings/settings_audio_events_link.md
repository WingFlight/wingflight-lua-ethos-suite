---
title: "Link"
sidebar_label: "Link"
sidebar_position: 55
documentation_status: reviewed
source: app/pages/settings_audio_events_link.lua
---

# Link

Callouts for the flight controller link going away and coming back.

## Where to find it

*System* → *Settings* → *Audio* → *Events* → *Link*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| *Telemetry lost* | Calls out the link when it drops **while the model is armed**, and again when it comes back. On by default. |

## Notes

- One switch governs both halves, because the recovery is gated on the loss: the link coming
  back is only announced if the loss was announced, and only while that loss is still the same
  flight.
- The armed state is read from the tick *before* the link went. Unplugging the pack on the
  bench, or powering down after landing, is the normal end of a session and stays completely
  silent; the same drop with the rotors turning is the one event here a pilot must not have to
  notice for himself.
- A model that answers again more than 120 seconds later gets no recovery callout — that is a
  new flight, and "telemetry recovered" belongs to the one that was interrupted.
- The dedicated *Telemetry lost* / *Telemetry recovered* sounds are not in the packs yet, and
  neither has a neighbour worth borrowing: every shipped alert word names a different event, and
  saying a lost link in the words of an empty battery is worse than saying nothing. Until a
  pack carries them the haptic is what sounds, and the words follow as soon as a pack has them.
- Changes are saved to the radio's settings store, not to the flight controller. Nothing here
  is written to flight controller EEPROM.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_audio_events_link.lua). Menu conditions come from `app/tool.lua`.
