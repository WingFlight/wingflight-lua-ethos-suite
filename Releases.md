# Unreleased

Split Radio Config's shared Cyclic deadband into separate Roll and Pitch deadbands, alongside Yaw. Requires matching firmware (MSP_RC_CONFIG layout change).

# 0.0.26

Add Nav Throttle, Altitude Damp and Turn Coord. to the GPS Navigation page, matching the reworked 0.0.26 firmware GPS Loiter/RTH; firmware without them keeps working and ignores them.

Add a Failsafe Stage 2 page (procedure, delay/off delay/throttle low delay/throttle/recovery delay, test switch mode) and a GPS Navigation tuning page (RTH altitude, loiter radius/direction, min satellites, max bank/pitch angle, bearing/altitude gain), both requiring MSP API 22.4 firmware. Failsafe is now a submenu grouping Channel Fallback and Stage 2, each with dedicated icons.
Add a GPS fix telemetry sensor and an audio callout ("GPS fix acquired/lost", off by default pending generated audio), including on first connect if a fix is already present.
Remove the GPS RESCUE box name; relabel the RESC arming-disable flag to GPS RTH, matching the firmware/Configurator retirement of the redundant GPS RESCUE switch.

Announce battery profile cell count alongside capacity when the battery profile audio event fires.

Rename Governor Headspeed to Governor RPM (adjustment id 80).
Fix broken RPM sensor labels: the sensor catalog referenced telemetry.sensor_motor1speed/sensor_motor2speed keys that didn't exist in any locale, rendering blank; renamed from Headspeed/Tailspeed to match the firmware's Motor 1/2 RPM rename.

Split Thrust Vector into PIDs, Master Gains, PID Controller, PID Bandwidth and Attitude / Heading Hold tools. Each follows the selected TV profile and preserves the other tools' settings when saving.

Rename the Autolevel group to Flight Modes and split it into separate Trainer, Angle, Horizon, Auto Hover and Attitude Hold tools. Horizon includes the shared Angle limits; each tool preserves other modes' settings when saving.

Require MSP API 22.04 or newer and use 22.04 in the simulator. Update the firmware snapshot alongside the suite.

Add independent bank/pitch limits for Trainer and Angle in Autolevel with MSP API 22.4 firmware. Remove the legacy shared Max fields and older-firmware compatibility branches; show only bank and pitch limits. TRAINER is already available under Controls -> Modes.

# 0.0.25

Target MSP API 22.3: drop the heli placeholder bytes and raise the minimum supported API version.
Add per-profile battery cell count and cell voltages.
Add the CRSF Sensors serial port function and fix a stale RX_INPUT_BACKUP id.
Allow negative flap compensation and diff thrust yaw adjustments.
Show SmartFuel Sag Gain in volts instead of percent.

# 0.0.24

Add per-servo balance curves to the Curves page (new Servo category).

# 0.0.23

Add AUTOHOVER throttle assist fields to the Autolevel page.
Unify RC channel naming to CH #N in the Mixer Rules, Adjustments, and Modes pages, and resolve the Roll/Pitch/Yaw/Throttle bypass inputs to the pilot's actual mapped channel instead of a fixed order.

# 0.0.22

Add rule role tags and compensation gains to the Mixer Rules and Adjustments pages.
Add the TRADITIONAL flight mode name and an audio callout for it.
Surface the new BACKUP_RX arming disable flag; fix a stale bit-25 label.
Add an Auto Hover roll deadband field to the Autolevel page.
Hide the servo geometry correction field on PWM/bus servo pages.

# 0.0.21

Version bump for release alignment; no suite-relevant changes this cycle.

# 0.0.20

Version bump for release alignment; no suite-relevant changes this cycle.

# 0.0.19

Version bump for release alignment; no suite-relevant changes this cycle.

# 0.0.18

Add Thrust Vector profile support.
Generalize the backup RX display from SBUS-only into a provider-selectable input, recognizing FBUS, FPort, FPort2, Jeti EX Bus, and CRSF.

# 0.0.17

Add Thrust Vector page and Attitude Hold support.
Add Serial Rx (Backup, SBUS) port option and diagnostics page.
Restore dashboard power type preference.

# 0.0.16

Version bump for release alignment; no suite-relevant changes this cycle.

# 0.0.15

Add support for Spektrum SRXL2 ESC.

# 0.0.14

Clarify ARM_WIGGLE configuration label.
Make adjustment range loading reliable.
Add thrust vector adjustment functions.
Fix mixer setup and add configuration feature toggles.
Fix dirty state tracking for servo edits.

# 0.0.13

Fix dashboard boxes flashing empty on cold-start repaint.
Fix dashboard stuck on postflight after rearm (throttle detection).
Fix broken armed-save dialog missing i18n keys.
Fix dashboard widgets starving for updates on the post-wake render pass.

# 0.0.12

Align GPS Loiter/RTH flight modes with firmware.
Reduce boot/dashboard startup overhead via lazy module loading, load memoization, and reduced loadfile duplication.
Fix dashboard telemetry refresh on link loss and invalid MSP version overlay handling.
Fix alignment orientation and retry S.Port telemetry sensor setup.
Persist disabled model dashboard theme; update i18n and deploy script retry handling.

# 0.0.11

Improve dashboard startup, wakeup, theme reload, and low-resolution layout stability under Ethos instruction and paint budgets.
Fix CRSF/ELRS telemetry updates, RSSI/VFR header display, unsupported MSP API handling, and repeated reboot resend behavior.
Add Settings > General, integration name sync, copy-profile tools, and model/altitude audio callouts.
Improve save-dirty tracking, confirmation dialogs, battery/smartfuel profile handling, and translations.
Fall back to the transmitter model name when the MSP craft name is unset.

# 0.0.10

Rename headspeed/tailspeed RPM naming to rpm/motor2speed, matching firmware's motor1/motor2 rename.
Force crsf_telemetry_mode to CUSTOM when saving custom telemetry sensors, so the FC actually transmits the picked sensors.
Show a disarm notice instead of a save error when EEPROM_WRITE is armed-blocked.
Force dashboard widget title off via registerWidget to avoid a duplicate title bar.

# 0.0.9

Rebuild the suite on rotorflight-lua-ethos-suite's latest base, realigned to wingflight-firmware.
Add Mixer Rules and Curves (Mixer/Gain curve shape) editors.
Add ELRS link probe/sync tool to Diagnostics.
Fix dashboard voltage/telemetry sensor mis-detection, MSP/S.Port sensor dropouts, and high CPU with no telemetry link.
Fix save-write dialog silently closing on failure.
Reset dashboard to preflight when reconnecting to a different aircraft.

# 0.0.8

Version bump for release alignment; no suite-relevant changes this cycle.

# 0.0.7

Version bump for release alignment; no suite-relevant changes this cycle.

# 0.0.6

Add throttle range governor support.
Add ready-to-arm surface wiggle support.
Add ATTHOLD mode support.
Add auto-trim flight mode sensor bit.
Add feature flags to reduce RAM usage.
Fix missing translations in the Auto Level module.

# 0.0.5

Version bump for release alignment; no suite-relevant changes this cycle.

# 0.0.4

Add distinct manual and passthrough modes.
Add cross-axis relax controls.
Add auto-hover flight mode support.
Remove atthold mode.
Update mixer configuration support.
Refresh translations.

# 0.0.3

ESC Programing
Improve telemetry conditions
IdleUP governor

# 0.0.2

Board Alignment
Remove collective from channel maps
Add in ability to set master gains on RPY via lua
Added in support for flight modes sensor
Ensure flight mode sensor is enabled by default

# 0.0.1

First snapshot release of the Wingflight Lua Suite for FrSky Ethos.

Wingflight is a fork of Rotorflight, refocused exclusively on fixed-wing 3D
and aerobatic aircraft. This is the first release under the Wingflight name,
starting a fresh release history independent of Rotorflight.

This version is intended to be used for beta-testing only. It may contain
incomplete features or stability issues and is not recommended for end-user
use.
