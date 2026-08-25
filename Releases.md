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
