# ActiveLook

The Wingflight ActiveLook widget displays up to four values on the EnGo 2's
304 x 256 pixel display. Each flight phase has its own layout and slot
assignments. ActiveLook preferences are stored on the transmitter in
`SCRIPTS:/wfsuite.user/settings.ini`; they are not flight-controller EEPROM
settings.

## Configure

Open **System -> Settings -> ActiveLook** on the transmitter. All four pages
are available offline.

The **Settings** page enables the widget, chooses an optional switch to blank
the display, and sets horizontal and vertical offsets from -20 to +20 pixels.
The **Preflight**, **Inflight** and **Postflight** pages each select one of five
layouts and assign values to up to four slots. Layouts are Two Top + One
Bottom, Two Top + Two Bottom, Single Centered, One Top + Two Bottom, and
Stacked Large + Large + Small. Layouts that use fewer than four positions
disable the unused slots.

Selectable values include flight phase, timer, governor state, arm status,
ESC and MCU temperature, link, fuel, current, voltage, cell voltage, motor
RPM, and consumed capacity. Min/max slots are available for fuel, current,
voltage, RPM and link; maximum-only slots are available for ESC and MCU
temperature.

## Flight phases and statistics

The widget starts in preflight. A fresh disarmed-to-armed transition starts in
preflight; the flight detector then enters inflight when the model is armed and
connected and either the governor reports an active state (4 through 8) or the
mapped transmitter throttle exceeds 35%. FC `throttle_percent` is the fallback
until RX_MAP is available.

After inflight begins, the phase stays inflight while the model remains armed,
even if throttle or telemetry briefly drops out. Disarming after a flight
enters postflight. Losing the connection after inflight has started also
changes the display to postflight.

Min/max statistics are collected only during inflight. They reset when a new
flight first enters inflight and remain available throughout postflight. Select
a Min/Max slot to display an extreme value.

## Simulator preview

Run **ActiveLook Preview** from the VS Code task or launch configuration. It
reads sensor profiles from the configured Ethos simulator's
`scripts/wfsuite/sim/sensors` folder and loads/saves phase layouts and slots in
`scripts/wfsuite.user/settings.ini`. If the settings file does not exist yet,
the first preview save creates it. Saving preserves unrelated INI sections and
rejects stale edits if the file changes concurrently.

The preview uses Wingflight slot IDs, including `rpm`, `rpm_min` and `rpm_max`.
For profiles that return `math.random(...)`, it samples the configured range;
it cannot read the exact random sample currently held by the simulator. The
preview edits layouts and slots, not the widget enable switch or display
offsets.

## Source

Widget logic: `src/wfsuite/widgets/activelook.lua`. The flight phase comes from the session
(`src/wfsuite/lib/flight_stats.lua`), the same one the dashboard shows. Settings and slot definitions:
`src/wfsuite/lib/activelook_config.lua`. Simulator preview:
`bin/activelook_preview/`.