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

The title shows the current step. The line below it is a notice, empty unless
something stops the wizard moving the surfaces (see below). At the bottom, **Back**
and **Next** move between steps; **Next** saves any changes first, as *Save and
continue* does in the Configurator. **Save** in the header writes the changes to
the flight controller's EEPROM.

## Direction step

Checks that every surface moves the right way. The wizard holds one axis at a
time with mixer overrides, and you say for each surface whether it moved the
right way.

| Setting | What it does |
| --- | --- |
| Test movement | How far the wizard moves the axis: Small (15 %), Medium (25 %), Large (35 %) or Half stick (50 %). Start small. Changing it while the surfaces are held moves them to the new size at once. |
| Check | Which axis to check: *Flaps down*, *Pitch up*, *Roll right* or *Yaw right*. Only the checks for axes the mix uses are offered. The line below says how the surfaces should move. |
| Surfaces: Move / Stop | **Move** holds the selected axis at the test movement; **Stop** lets the surfaces go. Every other axis is held at zero meanwhile, and the flap channel at flaps up. |
| *S1 Aileron* … | One row per surface the check moves. The value is the servo's live output in µs, or *Done* / *Fixed* once you have answered. **Wiggle** moves just that servo back and forth so you can see which surface the row is. **OK** marks it right. **Wrong** reverses that servo. |
| All moved wrong? / Invert axis | Inverts the axis (negates its Axis Throw in the mixer) instead of reversing each servo. Use it when every surface on the axis went the wrong way. |

**Wrong** is greyed out for a surface that also works another axis (an elevon on
the roll check, say). Reversing its servo would break the other axis. If every
surface is wrong, invert the axis instead; if only one is, change its mix in Mixer
Rules. A flap that follows the ailerons gets its direction from the flap check.

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
[Direction step](../../../src/wfsuite/app/pages/setup_wizard_direction.lua). Surface
detection is [lib/setup_wizard_surfaces.lua](../../../src/wfsuite/lib/setup_wizard_surfaces.lua),
a port of the Configurator's `src/tabs/setup_wizard/surfaces.js`. Menu conditions
come from `app/tool.lua`.

*Documented against WFSuite Ethos 2.3.1.*
