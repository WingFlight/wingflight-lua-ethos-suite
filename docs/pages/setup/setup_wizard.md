---
title: "Setup Wizard"
sidebar_label: "Setup Wizard"
sidebar_position: 90
documentation_status: reviewed
source: app/pages/setup_wizard.lua
---

# Setup Wizard

> **Remove the propeller and secure the model.** The wizard moves the control
> surfaces itself. It puts the flight controller in its setup state, which blocks
> arming while the wizard is open.

Walks through setting up a model from the radio, one step at a time, at the field
and without a computer. It is the radio's copy of the Configurator's Setup Wizard.
So far it has one step, **Direction**; more of the Configurator's steps will
follow.

The wizard starts from a model whose mix is already set up, in Mixer Rules or with
the Configurator's Setup Wizard. With no control surface mixed, it says so and
stops. Receiver protocol setup and the ESC telemetry port stay in the
Configurator: the radio talks to the flight controller through the receiver, so it
cannot set the receiver up from scratch.

## Where to find it

*Configuration* → *Setup* → *Setup Wizard*

Requires a running background task and a flight controller connection. The
flight controller firmware must support MSP API 22.14 or newer (timed overrides);
on older firmware the page explains that and does nothing else.

## Layout

The title shows the current step. Below it, a notice line appears only when
something stops the wizard moving the surfaces (see below). Each step then asks
one thing per screen: a picture, a sentence and one or two big buttons along the
bottom. **Save** in the header writes the changes to the flight controller's
EEPROM at any time.

## Direction step

Checks that every surface moves the right way. The wizard moves the surfaces
itself and asks whether they moved the way the picture shows.

The picture is the model **seen from behind**, as you see it standing behind it,
drawn from the mix: wing, flaps, tailplane or V-tail, and fin. The surfaces the
check moves are highlighted, with arrows for the way they should go.

| Screen | What happens |
| --- | --- |
| Start | Says what is about to happen. **Start** begins with the first check. |
| A check | One per axis the mix uses, in this order: *Flaps down*, *Pitch up*, *Roll right*, *Yaw right*. The wizard holds every other axis at centre and the flaps up, and flicks the checked axis between centre and the test movement, so the surfaces keep moving. **Like this** goes on to the next check. **Not like this** asks what was wrong. **Move 25 %** steps the test movement through 25, 35, 50 and 15 % of full stick. |
| All of them / Only some | Asked when the check moves more than one surface. **All of them** fixes the axis as a whole. **Only some** goes through the surfaces one at a time. |
| Servo *n* is wiggling | Only that servo moves, back and forth. **Yes** if it is one that moved the wrong way, **No** if not. Focus starts on **No**. |
| Can't fix | A wrong surface that also works another axis is left alone, and the screen says to change its mix in Mixer Rules. |
| Directions checked | What the wizard changed. **Check again** starts over; **Save and finish** writes EEPROM and leaves the wizard (or **Save and continue** goes on to the next step, once there is one). |

How the wizard fixes a surface, as in the Configurator:

- **One surface wrong, on its own axis** (an aileron on the roll check, the elevator
  on the pitch check): its servo is reversed.
- **Every surface wrong**: the axis is inverted (its Axis Throw in the mixer is
  negated). That keeps surfaces that also work another axis right. The flap
  channel has no axis to invert, so each flap servo is reversed instead.
- **A wrong surface that also works another axis** (an elevon on the roll check,
  say) cannot be reversed without breaking the other axis, so the wizard explains
  and leaves it.

After a fix the same check runs again, so you can see it is right.

Signs follow the stabilized mixer inputs: roll + is right roll, pitch + is stick
forward (nose down), and yaw + is yaw left, since the firmware negates RC yaw once.
The flap check moves the flap channel (AUX1) positive, which the mix takes as flaps
down. It comes first, because flaps that follow the ailerons take their roll
direction from it.

## How it stays safe

**Everything the wizard holds lapses on its own.** The setup state, the mixer
overrides and the servo overrides are all sent with a timeout and re-sent by the
suite's override keepalive (`lib/override_keepalive.lua`): a 10 s timeout,
refreshed every 3 s. A radio that is switched off, or a link that drops, lets the
flight controller drop them within 10 s.

**An armed model is never moved.** The setup state blocks arming while the wizard
is open, and the flight controller ignores overrides while armed and refuses the
setup state. If the model is armed, or the flight controller refuses the setup
state, the wizard lets everything go and the notice says why.

**PASSTHROUGH and MANUAL are flagged.** These modes put the sticks straight on the
surfaces, so the notice asks you to switch them off.

**Every way out lets go.** Back, the close key, a step change and closing the tool
all release every override the wizard set. On opening, it also clears overrides
left on by other pages, so they cannot hold a surface still and make a check look
wrong.

## Saving

Changes go to the flight controller as you make them, so the surface moves straight
away. They are lost at the next power cycle until you save them. Leaving the wizard
with unsaved changes asks whether to **Save** them or **Discard** them. Discard
writes back the settings the wizard loaded. Closing the tool cannot ask, so it leaves
them on the flight controller, unsaved, as other pages do.

## Source

[Page implementation](../../../src/wfsuite/app/pages/setup_wizard.lua) and the
[Direction step](../../../src/wfsuite/app/pages/setup_wizard_direction.lua), with its
pictures drawn by [app/setup_wizard_art.lua](../../../src/wfsuite/app/setup_wizard_art.lua). Surface
detection is [lib/setup_wizard_surfaces.lua](../../../src/wfsuite/lib/setup_wizard_surfaces.lua),
a port of the Configurator's `src/tabs/setup_wizard/surfaces.js`. Menu conditions
come from `app/tool.lua`.

*Documented against WFSuite Ethos 2.3.1.*
