---
title: "Rx Backup"
sidebar_label: "Rx Backup"
sidebar_position: 40
documentation_status: reviewed
source: app/pages/diagnostics_rx_input_backup.lua
---

# Rx Backup

Live status of the backup receivers: which protocol each one decodes, whether
it is receiving, which receiver is flying the model, and every channel value
the backups report. Use it on the bench to confirm a backup satellite is wired
and bound before relying on it, and to watch it take over when the primary
receiver's link is pulled.

The flight controller supports two backup receivers, assigned on the *Ports*
page as *Receiver: Backup 1* and *Receiver: Backup 2*. They take over in that
order when the primary receiver's signal is lost (PR #277).

## Where to find it

*System* → *Tools* → *Diagnostics* → *Rx Backup*

Requires a running background task and a flight controller connection. The page
is read-only and refreshes about three times a second; the header's reload
button forces a read.

## Settings

There is nothing to change here. The lines shown:

| Line | What it shows |
| --- | --- |
| Backup 1 Protocol / Backup 2 Protocol | The protocol selected for that backup on the flight controller (`rx_input_backup_provider` / `rx_input_backup2_provider`): NONE, SBUS, FBUS, FPORT, EXBUS or CRSF. `-` when that backup has no port assigned. |
| Backup 1 Link / Backup 2 Link | *Up* (green) when the backup has decoded a valid frame in the last ~50 ms, *Down* (red) otherwise, *Not configured* when no port carries that backup. |
| Active Source | *Active: Main RX* (green) while the primary receiver is flying the model, *Active: Backup 1* or *Active: Backup 2* (red) while that backup has taken over. `-` when no backup is configured. |
| CH 1 … CH 24 | The channel value each backup reports, in microseconds, as `backup 1 / backup 2`. A backup without a value for that channel shows `-` in its position (`- / 1500`), so a number is always attributable. Channels beyond what a backup's frame carries read as stick centre, which is what a takeover would apply. |

## Notes

- Values come from `MSP2_WING_RX_INPUT_BACKUP_STATUS` (`lib/msp_rx_input_backup_status.lua`),
  payload versions 1 to 4. Firmware older than payload version 4 reports one
  backup only; the second backup's lines then read *Not configured*.
- Telemetry travels over the primary receiver, so while the primary link is
  down the radio usually cannot reach the flight controller and this page
  stops updating. Test takeover with the primary receiver's control link cut
  but telemetry still reachable, or watch the Configurator instead.
- A simulator session shows both backups as *Not configured*.

## Source

[Page implementation](../../../src/wfsuite/app/pages/diagnostics_rx_input_backup.lua). Menu conditions come from `app/tool.lua`.

*Checked against the source at PR #277 (WFSuite Ethos 2.3.x).*
