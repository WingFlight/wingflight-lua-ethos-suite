# Dashboard controls

The Wingflight dashboard widget has two overlays on top of whatever theme is
showing: a toolbar along the bottom and an info panel from the top. Both are
hidden until you ask for them, so they never cover the theme on their own.

Source: `src/wfsuite/widgets/dashboard.lua`.

## Toolbar

Open it by sliding up on the dashboard, or with a long press of PAGE. Close it
by sliding down or pressing the rotary down. It closes by itself after 10
seconds without a touch or key press.

| Tile | Does | Greyed out when |
| --- | --- | --- |
| Reset | Resets the flight (timers and min/max stats) after a confirmation. | Never. |
| Erase | Erases the blackbox dataflash after a confirmation. | Not connected. |
| Battery | Picks the active battery profile. | Not connected, or fewer than two battery profiles are set. |
| Info | Opens the info panel (below). | Never. |
| Setup | Opens the Wingflight Suite. | Ethos is older than 26.1. |

## Info panel

Slide down on the dashboard to open it, or pick **Info** on the toolbar. It
drops from the top, as tall as its contents need (at most 85% of the
dashboard), and updates live. Unlike the toolbar
it does not time out, so it can stay open while you wait for satellites. It
closes when you:

- slide up, tap anywhere on the dashboard, or press Exit or Enter;
- arm the model. You can open it again while armed.

When the toolbar is open, sliding down closes the toolbar first. Only one of the
two is open at a time.

**Left column: Controller**

| Row | Shows |
| --- | --- |
| Link | Telemetry link type (S.Port or CRSF), plus link quality when the link reports it. |
| Flight mode | The active flight mode, named as the flight-mode callout speaks it: Failsafe, GPS Rescue, RTH, Loiter, Passthrough, Manual, Att Hold, Autotrim, Angle, Trainer, or Normal. A Loiter or RTH switched on that can't fly is shown in amber. |
| Arming | **Ready** (green), **Blocked** (amber), or **Armed** (red). When blocked, each reason is listed at the bottom of the column. `-` until the FC reports its arming flags. |
| Profile | Active PID, rate and battery profile numbers. |
| BEC Voltage | Receiver/BEC voltage, when the sensor reports it. |
| Blackbox | How full the blackbox dataflash is. |

**Right column: Battery, then GPS**

| Row | Shows |
| --- | --- |
| Pack | Cell count and capacity of the active battery profile, for example `6S  2200mAh`. |
| Voltage | Pack voltage. |
| Used | mAh used so far. |

A **GPS** section follows, only when the model has a GPS: the FC reports one
fitted, the **GPS Sats** sensor is reporting, or the FC reports a fix. Without a
GPS the column is just Battery.

| Row | Shows |
| --- | --- |
| Fix | **No fix** (red), **Fix** (amber), or **Home set** (green). From the FC's System Status sensor. |
| Satellites | The satellite count from the **GPS Sats** sensor (S.Port and CRSF/ELRS). `-` until the sensor reports. |
| GPS | **Not responding**, shown only when the GPS stopped talking after working earlier in the connection. |

Each row only appears once its value is known. If the panel can't fit
everything, the last rows of a column are left off. While no model is connected,
both columns show **Not connected**.
