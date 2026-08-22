# Dashboard flight-mode stuck-on-postflight fix — dev notes

**Status: implemented, UNTESTED.** No Lua interpreter or scriptable
simulator driver was available in the session that wrote this, so
everything below is code-review-verified only, not execution-verified.
Pick up testing here on whatever machine has the Ethos simulator/radio
available.

This is a **port** of the same fix in the sibling
`rotorflight-lua-ethos-suite` repo (branch
`fix/dashboard-flightmode-rx-throttle` there too). See that repo's
`docs/dev-notes-dashboard-flightmode-fix.md` for the full root-cause
writeup — this file only covers what's wfsuite-specific.

## The bug (same as rotorflight-lua-ethos-suite)

`widgets/dashboard/flightmode.lua` is currently byte-identical between
the two suites. Its `inFlight()` decides "are we flying" as: `isArmed
AND (governor active OR throttle > 35%)`. The upstream "Total rewrite"
(#2256, rotorflight-lua-ethos-suite) swapped the throttle signal from
the radio's own throttle channel (a local `system.getSource
(CATEGORY_CHANNEL)` read) for the FC's telemetry-reported
`throttle_percent` sensor, and dropped two state-machine rules
(reset-on-rearm, hold-inflight-while-armed). Together these let the
dashboard get stuck showing `"postflight"` after a rearm.

## What this port does

Same four files, same mechanism, applied at the equivalent anchor
points in wfsuite's own `tasks/session.lua` / `widgets/dashboard.lua`
(structurally close enough to rotorflight's that the same edits
dropped in cleanly):

1. **New**: `lib/msp_rx_map.lua` — reads `MSP_RX_MAP` (cmd 64).
2. **`tasks/session.lua`**: fetches/publishes/resets `session.rxMap`.
3. **`widgets/dashboard.lua`**: threads `rxMap` through to the widget.
4. **`widgets/dashboard/flightmode.lua`**: reads the RX throttle
   channel via `rxMap.throttle` (falls back to telemetry
   `throttle_percent` if RX_MAP hasn't resolved), restores the two
   dropped state-machine rules.

## wfsuite-specific note: the governor branch is a no-op here

`isGovernorActive(widget.governorState)` is ported unchanged, but
wfsuite's own `tasks/session.lua` never fetches a governor config (no
such firmware concept for fixed-wing) — `governorState` stays `nil`
for the life of the connection, so that branch always evaluates false
and `inFlight()` always falls through to the throttle check. That's
harmless (costs nothing, keeps this file diffable against
rotorflight-lua-ethos-suite's copy) and happens to be correct for a
plane anyway — but it's worth flagging as a **known follow-up**:

- "Throttle above X%" is a much weaker "are we flying" signal for a
  glider, or a plane on a long low-throttle descent/approach, than it
  is for a helicopter's collective/headspeed relationship.
- A future wfsuite-specific `inFlight()` might want to check airspeed
  or altitude-rate instead of (or alongside) throttle. Not attempted
  in this pass — this port intentionally kept the two suites'
  `flightmode.lua` mechanism-identical for now, per instruction to
  land the parity fix first and revisit wfsuite-specific tuning
  separately.

## What's verified vs. not

Same caveats as the rotorflight-lua-ethos-suite fix — no Lua
interpreter, no simulator driver available in the authoring session.
**Biggest open risk**: the raw RX channel value's scale — the
threshold `35` was carried over unchanged from the pre-rewrite code
with zero unit conversion; see the other repo's dev-notes for detail.

## How to test

Same checklist as rotorflight-lua-ethos-suite's dev-notes: connect,
watch console for errors from `msp_rx_map`/`rxMap`/`flightmode.lua`,
arm + throttle-up to confirm `"inflight"`, momentary throttle dip
should *not* drop to `"postflight"` while still armed, disarm confirms
`"postflight"`, then the actual repro: rearm + throttle-up should
return to `"inflight"`.

## Git references

Same as rotorflight-lua-ethos-suite (shared history up to the fork
point) — see that repo's `docs/dev-notes-dashboard-flightmode-fix.md`.
