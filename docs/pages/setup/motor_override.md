---
title: "Motor Override"
sidebar_label: "Motor Override"
sidebar_position: 10
documentation_status: reviewed
source: app/pages/motor_override.lua
---

# Motor Override

> **Remove the propeller and secure the model first.** The flight controller drives
> the motor directly here, with no throttle stick, no mix and no arming check in
> between. Anything still attached turns.

Drives one motor directly, so a direction check, an ESC calibration or a motor
swap can be done from the radio instead of on a bench with the Configurator.

## Where to find it

*Configuration* → *Setup* → *ESC & Motors* → *Motor Override*

Requires a running background task and a flight controller connection.

## Settings

| Setting | What it does |
| --- | --- |
| Motor | Which motor this page drives. Offered only on a board with more than one. |
| Enable motor override | Arms the page. Asks for confirmation first. |
| Throttle | 0-100 % of full throttle, applied directly to the selected motor. |

## How it stays safe

**A confirmation stands in front of the switch.** Turning it on asks before
anything is written; turning it off asks too. A cancel puts the page back the way
it was.

**The flight controller holds a one-second deadline.** `MOTOR_OVERRIDE_TIMEOUT`
is 1.0 s (`flight/motors.h`), and `motors.c` resets every override once it
passes. A single write is therefore not "the motor is on" — it is "the motor
turns for one more second". The page re-sends the current value four times a
second while the override is enabled. Without that the motor would stop by itself
about a second after the wheel is let go, which reads as an intermittent fault.

This is **not** the timed override of `lib/override_keepalive.lua`. That path
exists for servo, mixer and mode overrides, which carry their own timeout in the
payload from firmware API 22.14 on a 10-second window refreshed every 3 seconds.
`MSP_SET_MOTOR_OVERRIDE` carries no timeout field at all — the firmware supplies
its own one-second one — so a 3-second refresh would let the motor lapse between
sends.

**Leaving the page releases the motor.** Back, a page switch and closing the tool
all run the same release, and it names *every* motor the page could have touched,
not only the selected one.

**An armed model cannot be overridden at all.** The firmware ignores the write
outright while armed — `setMotorOverride()` checks the arming flag before it
stores anything. The switch is therefore disabled rather than shown as a control
that would quietly do nothing, and an override already running when the model
armed is handed straight back.

**A lost link hands the motor back.** When the link drops nothing can be written
any more, so the one-second deadline on the board ends the override on its own;
the page drops the switch at the same moment instead of leaving it claiming a
motor is being driven.

What none of that can cover — the script being killed, the transmitter crashing —
is covered by the firmware, for the same reason the keep-alive exists: no write,
no motor, one second after the last one.

## Notes

- The page shows what the flight controller is *already* overriding when it
  opens, rather than starting from zero. A non-zero value there means something
  else is driving that motor.
- Only the forward half of the range is offered. The firmware accepts negative
  values and they run the motor backwards; that is not part of any setup
  procedure.
- The title carries a `*` while the override is engaged.
- Nothing on this page is written to the flight controller EEPROM. A reboot, a
  disarm or a link loss ends the override; nothing is saved.

## Source

[Page implementation](../../../src/wfsuite/app/pages/motor_override.lua). Menu conditions come from `app/tool.lua`. Firmware behaviour from `src/main/flight/motors.c`, `src/main/flight/motors.h` and `src/main/msp/msp.c`.

*Documented against WFSuite Ethos 2.3.1.*