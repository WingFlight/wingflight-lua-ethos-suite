---
title: "Setup Wizard"
sidebar_label: "Setup Wizard"
sidebar_position: 90
documentation_status: reviewed
source: app/pages/setup_wizard.lua
---

# Setup Wizard

> **Remove the propeller and secure the model.** The wizard moves the control
> surfaces itself, and the Motor step spins the motor. It puts the flight
> controller in its setup state, which blocks arming while the wizard is open.

Sets a model up from the radio, step by step, at the field and without a
computer. It is the radio's copy of the Configurator's Setup Wizard: the same
questions and the same rules, as a guided sequence for a radio screen. Each
screen asks one thing, with a picture or a live value and one or two big
buttons.

The pictures show the model in 3D, built from its airframe type and the
surfaces in its mix (a regular airplane, V-tail, flying wing, delta or
rudder-elevator model, with flaps when it has them), seen from behind as you
stand behind it. A check lights the surfaces it moves in orange, swings them the
way they should go and draws an arrow for each; a step that works on one surface
at a time lights that kind of surface. On a screen with a picture the picture is
on the left and the words on the right. Where there is room, mostly on the bigger
radios, the text is larger. A choice such as the servo type or motor protocol is
a list: each option has its own button with what it means beside it, and the
current one is lit. The Receiver step draws both sticks, laid out for the radio's
stick mode, with the corner to go to marked; on a small screen it shows only the
bars.

## Where to find it

*System* → *Tools* → *Setup Wizard*

Requires a running background task and a flight controller connection. The
flight controller firmware must support MSP API 22.14 or newer (timed overrides);
on older firmware the page explains that and does nothing else.

## Moving around

The title shows the step number and name. An amber notice line appears under it
only when something stops the wizard moving the surfaces (see below), including
**Switch MANUAL mode off** and **Switch PASSTHROUGH mode off**.

- Every screen has one row of buttons along the bottom, always in the same
  order. **Back** (‹) is a small button at the left end: the screen before, or
  the step before from a step's first screen (step 1 has none). The screen's
  own buttons (**Start**, the ± steps, answers) are in the middle, set apart
  from the two ends. The way forward is at the right end: **Next** (›), which
  becomes **Save and continue** once something has changed (it writes the
  changes to EEPROM and opens the next step), **Save and restart** where the
  change needs a restart, and **Save and finish** on the last step. **Next** on
  a step's first screen leaves that step as it is. On a screen that asks a
  question, the answers are the way forward.
- The **checklist** button in the header opens the list of all 15 steps; tap one to go
  to it. Back from the list returns to the step.
- **Save** in the header writes the changes at any time.
- **Save and restart** (steps whose settings apply after a restart) shows a
  *Restarting...* dialog while the flight controller restarts. Its bar fills
  and its message counts down the seconds left (at most 20). The dialog closes
  as soon as the flight controller is back, and the wizard reloads on the same step.
- The wizard reopens on the step it was on, for the rest of the radio session.
- A step that works on the control surfaces, on a model with none mixed yet, offers
  **Set up the airframe** instead.

## The steps

| Step | What happens |
| --- | --- |
| 1. Sensors and level | Calibrate the accelerometer (hold the model level and still), find the board orientation automatically (flat, Start, lift the tail 20°: a picture of the plane shows the lift), check it on a live 3D plane that must follow the model as you tilt it, and set level automatically (hold the flying attitude). Board orientation applies after a restart: the step ends with **Save and restart**, and the wizard reopens on this step when the flight controller is back. |
| 2. Receiver | Checks the sticks: put both in the bottom-left corner and every bar should go left. **Bars are wrong** finds the channel order by moving throttle, roll, pitch and yaw in turn, and writes the RX map. A reversed bar is fixed on the radio. Receiver port and protocol setup stays in the Configurator, because the radio talks to the flight controller through the receiver. |
| 3. Airframe | Shows the model type and its servos. **Change** asks the type (regular, flying wing, V-tail, delta, rudder-elevator), then only the questions that type needs (ailerons, tail, rudder, flaps, flaps following the ailerons, motors, differential thrust), with a picture of the result, then **Apply** writes the whole mix and the model type. Custom mixes stay in Mixer Rules; applying a type also replaces thrust vectoring rules (set them up again in the Configurator). |
| 4. Servo type | Analog (50 Hz), digital (333 Hz) or narrow-band (560 Hz, 760 µs) for every control-surface servo. Changing between normal and narrow band resets that servo's centre, limits and scale. Applies after a restart (**Save and restart**). |
| 5. Motor | Standard PWM, DShot150 or DShot300, or any other protocol from the **Other** drop-down (No motor, DShot600, OneShot, ProShot, ...), which shows the protocol set when it is one of those. DShot600 is not offered as a quick pick: on long ESC or servo leads it picks up noise, so choose it only if you know your wiring suits it. DShot150 has no bidirectional DShot RPM telemetry: choosing it in the wizard also turns bidirectional DShot off (an ESC that doesn't answer it may not arm), and while it is set the step notes that motor RPM needs DShot300 or an RPM or ESC telemetry source. A change applies after a restart. **Check motor**: confirm the propeller is off, then **Spin** runs every motor at 5, 10 or 20 % for 3 seconds and stops by itself. |
| 6. Center | Every surface is held at its centre. One screen per surface: −10/−1/+1/+10 µs until it is neutral. **Identify** rocks only the selected servo gently either side of center for 3 seconds, then centers it again; adjusting or leaving stops it early. More than 100 µs from the servo's normal centre is flagged: move the horn instead. |
| 7. Direction | The wizard moves each axis itself and asks **Like this** / **Not like this** against a picture of the model seen from behind. See below. |
| 8. Binding limits | One screen per side of each surface (servo 1 Min, servo 1 Max, servo 2 Min, ...), counted together ("3 of 8"). The intro pictures the method on three servo dials: step until it binds, back off one step, **Set**. On each screen the servo is held by a probe that ignores the stored limits, and a dial shows its horn: the side being found is lit, the stored range is the thick part of the arc, and the stored limit for this side is ticked. Step it with −50/−10/+10/+50 µs; **Set** saves this side only, so it is enabled once the servo is on that side of center, and moves to the next screen. **Next** skips the side and keeps its old limit; **Back** returns to the screen before. A flap's limits are its end points: setting one also sets the flap travel so the flap channel's end lands on it. |
| 9. Throws | The wizard switches PASSTHROUGH on, so your sticks move the surfaces directly. For each axis: hold full stick, measure, and step the axis Throw (−5/−1/+1/+5 %). **Fine-tune** adjusts one surface in one stick direction (that servo's scale on that side), for differential. A surface that reaches its binding limit before full stick is flagged. |
| 10. Travel check | A row per surface: its reach with full stick on every axis at once, as a percentage of its limit on each side, and a live gauge. On the gauge the bar is the full-stick reach (red past a limit), the marks are the binding limits, the dot is where the servo is now, and a thin mark stays at the furthest it has gone on each side, so trying the stick corners shows what each surface does. Above 100 % it reaches its limit before full stick. PASSTHROUGH stays on so the sticks move the surfaces; without the link, or armed, the screen says PASSTHROUGH is off. |
| 11. Gyro direction | The wizard switches ANGLE on. For each axis, move the model as the screen says; the surfaces should push back the way the arrows show. If one doesn't, the board orientation is wrong: run the Sensors step again (the step list). Don't reverse servos for this. |
| 12. Trim and gain | Trim: trim buttons on one channel (the flight controller keeps the trim), a channel per trim (the radio keeps it), or Auto trim only. The screen says what to set up in the radio's mixes, then **Detect** finds the channel when you press a trim button. Gain: one knob, one per axis, or none; turn the knob end to end to find it (0–150 %, centre 75 %). |
| 13. Mode switches | One screen per mode the flight controller offers (ARM, MANUAL, ATT HOLD, TRAINER, AUTO TRIM, PASSTHROUGH): **Assign** / **Change**, then flick the switch to its on position; **Remove** clears it. Only ARM is required. |
| 14. Flying style | Trainer, Sport or 3D: rates (°/s at full stick, expo) and I-term relax for roll, pitch and yaw, on the current rate and PID profiles. |
| 15. Finish | What the model has (type, surfaces, ESC protocol, throws, style, ARM switch), then the checks before the first flight, and **Save and finish**. |

ESC telemetry setup stays in the Configurator.

## Direction

The picture is the model **seen from behind**, as you see it standing behind it,
drawn from the mix: wing, flaps, tailplane or V-tail, and fin. The surfaces the
check moves are highlighted, with arrows for the way they should go. The wizard
flicks the checked axis between centre and the test movement (25 %, or 35, 50 or
15 % with **Move**), one axis at a time: *Flaps down*, *Pitch up*, *Roll right*,
*Yaw right* — only the ones the mix uses.

**Not like this** with more than one surface asks **All of them** or **Only some**.
*Only some* wiggles each servo in turn and asks whether it moved the wrong way
(focus starts on **No**). Then, as in the Configurator:

- one surface wrong on its own axis: its servo is reversed;
- every surface wrong: the axis is inverted (its Axis Throw negated); the flap
  channel has no axis to invert, so each flap servo is reversed;
- a wrong surface that also works another axis (an elevon on the roll check) is
  left alone and the screen says to change its mix in Mixer Rules.

After a fix the same check runs again. The last screen lists what changed.

## How it stays safe

**Everything the wizard holds lapses on its own.** The setup state, ANGLE or
PASSTHROUGH when a step switches them on, mixer and servo overrides, and the
Binding-limits probe are all sent with a timeout and re-sent by the suite's
override keepalive (`lib/override_keepalive.lua`): a 10 s timeout, refreshed every
3 s. A radio that is switched off, or a link that drops, lets the flight
controller drop them within 10 s. The motor spin re-sends four times a second
against the firmware's own one-second deadline, and stops after 3 seconds.

**An armed model is never moved.** The setup state blocks arming while the wizard
is open; the flight controller ignores overrides while armed and refuses the setup
state. If the model is armed, or the setup state is refused, the wizard lets
everything go, greys out the buttons that move things, and the notice says why.

**PASSTHROUGH and MANUAL are flagged** when you switch them on yourself, since they
put the sticks straight on the surfaces.

**Every way out lets go.** Back, the close key, a step change and closing the tool
all release everything the wizard holds. On opening, it also clears overrides left
on by other pages.

## Saving

Changes go to the flight controller as you make them, so the surfaces move straight
away. They are lost at the next power cycle until you save them. Leaving the wizard
with unsaved changes asks whether to **Save** them or **Discard** them; Discard
writes back what was there before every change since the last save. Closing the
tool cannot ask, so it leaves them on the flight controller, unsaved, as other pages
do.

## Source

[Page implementation](../../../src/wfsuite/app/pages/setup_wizard.lua) and one
`app/pages/setup_wizard_<step>.lua` per step. The screens are built by
[app/setup_wizard_ui.lua](../../../src/wfsuite/app/setup_wizard_ui.lua) and the
pictures drawn by [app/setup_wizard_art.lua](../../../src/wfsuite/app/setup_wizard_art.lua).
The rules are ports of the Configurator's: `lib/setup_wizard_surfaces.lua`
(`surfaces.js`), `lib/setup_wizard_controls.lua` (`receiver.js`, `modeRanges.js`,
`trimGain.js`), `lib/setup_wizard_styles.lua` (`styles.js`) and
`lib/setup_wizard_mix.lua` (`Mixer.buildWizardRules()`). Menu conditions come from
`app/tool.lua`.

*Documented against WFSuite Ethos 2.3.1.*
