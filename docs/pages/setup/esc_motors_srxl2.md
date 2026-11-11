---
title: "SRXL2 ESC"
sidebar_label: "SRXL2 ESC"
sidebar_position: 40
documentation_status: reviewed
source: app/pages/esc_motors_srxl2.lua
---

# SRXL2 ESC

Sets how the flight controller talks to Spektrum Smart ESCs on an SRXL2 ESC bus:
how often it polls them for telemetry, and which SRXL2 channel drives the second
motor of a dual-motor ESC.

## Where to find it

*Configuration* → *Setup* → *ESC & Motors* → *SRXL2 ESC*

Requires a running background task and a flight controller connection. Lit only while the flight controller reports this ESC telemetry protocol (Protocol ID: 14). The firmware sets that protocol whenever a serial port carries the SRXL2 ESC function.

## Settings

| Setting | What it does |
| --- | --- |
| Telemetry Interval | How many SRXL2 frames pass between telemetry polls of the ESC; 0 turns polling off. Range: 0 to 255 frames. Default: 7. |
| Motor 2 Channel | The SRXL2 channel that carries motor 2 on a dual-motor Smart ESC (for example the Spektrum SPMXAE1020). *Off* for a single-motor ESC; otherwise channel 2 to 32 (channel 1 is always motor 1). Default: Off. |

## Notes

- Saving writes the settings to the flight controller EEPROM and then **reboots the
  flight controller**: the firmware reads them only at boot.
- Save is refused while the model is armed.
- The throttle rate is not shown. The firmware derives it from the motor PWM rate;
  the page writes back the value it read unchanged.
- Firmware without MSP2_WING_SRXL2_ESC_CONFIG refuses the read, and the page shows a
  failed load. A reply of another payload version or length is refused the same way,
  rather than decoded and written back on the next save.

## Source

[Page implementation](../../../src/wfsuite/app/pages/esc_motors_srxl2.lua), codec
`lib/msp_srxl2_esc_config.lua` (MSP2_WING_SRXL2_ESC_CONFIG / MSP2_WING_SET_SRXL2_ESC_CONFIG,
wingflight-firmware PR #257), PR #279. Menu conditions come from `app/tool.lua`.

*Documented against WFSuite Ethos 2.3.1.*
