# Navigation Regression Checklist

Run these manually on radio after menu/navigation changes.

## Core return paths

1. `Advanced -> PID controller -> Back`
Expected: returns to `Advanced` submenu with icons.

2. `Hardware -> Setup -> Servos -> Servo 1 -> Back -> Back`
Expected:
- Back 1: `Servos` servo list
- Back 2: `Hardware / Setup` submenu with icons

3. `Hardware -> Setup -> Back`
Expected: `Hardware` submenu with icons.

4. `Tools -> Profile Select -> Back`
Expected: `Tools` submenu with icons.

## Legacy tools (now routed via openMenuContext)

1. `Governor -> General/Filters/Time/Curves -> Back`
Expected: return to `Governor` submenu.

2. `Profile Governor -> General/Flags -> Back`
Expected: return to `Profile Governor` submenu.

3. `Mixer -> Swash/Swash Geometry/Tail/Trims -> Back`
Expected: return to `Mixer` submenu.

