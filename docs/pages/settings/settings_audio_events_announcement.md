---
title: "Model announcement"
sidebar_label: "Model announcement"
sidebar_position: 60
documentation_status: reviewed
source: app/pages/settings_audio_events_announcement.lua
---

# Model announcement

Plays a custom model greeting WAV file on connection.

## Where to find it

*System* → *Settings* → *Audio* → *Events* → *Model announcement*

Available without a flight controller connection; the background task must be running.

## Settings

| Setting | What it does |
| --- | --- |
| *Model announcement* | When enabled, plays `SD:/audio/<model_name>.wav` once per connect if recorded on the SD card. |

## Notes

- Changes are saved to the radio's settings store, not to the flight controller.
- Looks for the WAV file using spaces and underscores interchangeably.

## Source

[Page implementation](../../../src/wfsuite/app/pages/settings_audio_events_announcement.lua). Menu conditions come from `app/tool.lua`.
