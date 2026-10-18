---
title: "Preferences"
sidebar_label: "Preferences"
sidebar_position: 50
documentation_status: reviewed
source: app/pages/power_preferences.lua
---

# Preferences

Setup -> Power -> Preferences page.

## Where to find it

*Configuration* → *Setup* → *Power* → *Preferences*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| ESC Current Limit | The current limit of the speed controller, in whole amps. 0 means not set. Used by the dashboard's ESC load box. |

## Notes

- AM32, Scorpion and YGE speed controllers store their own current limit. Opening their page under *ESC & Motors* → *Forward Programming* fills this value in automatically. Other speed controllers have no such field: type the limit in here.
- With no limit set, an ESC load box shows `--` instead of a percentage.
- Changes are stored on the radio for the connected flight controller when you press Save.

## Source

[Page implementation](../../../src/wfsuite/app/pages/power_preferences.lua). Menu conditions come from `app/tool.lua`.

*Documented against WFSuite Ethos 2.3.1.*
