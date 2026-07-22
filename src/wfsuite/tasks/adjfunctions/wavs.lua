-- Adjustment-function ID -> spoken-word-token spec, used by
-- tasks/audio_events.lua's speakAdjFunction() to announce in-flight
-- adjustment-range changes (each space-separated token plays one
-- "<token>.wav" from the "adjfunctions" soundpack folder -- word clips,
-- not one recording per function).
--
-- IDs match wingflight-firmware's own adjustmentFunc_e enum
-- (src/main/fc/rc_adjustments.h) exactly -- confirmed directly against
-- that header, not assumed. Entries for heli-only IDs are deliberately
-- absent (unlike the wire-format MSP codecs, this is a sparse lookup
-- table, not a fixed-position struct, so there is no alignment reason to
-- keep a dead placeholder): yaw cw/ccw stop gain (26/27), yaw cyclic/
-- collective ff and collective dynamic gain/decay (28-32), the entire
-- rescue block (39-44, MSP_RESCUE_PROFILE is gone from wingflight-
-- firmware entirely), the entire heli-governor block (48-55,
-- MSP_GOVERNOR_CONFIG/PROFILE likewise gone), pitch/roll "O gain"
-- (59/60, offset_limit -- doesn't exist on wingflight-firmware's
-- MSP_PID_PROFILE wire at all), cyclic cross-coupling (61-63), yaw
-- inertia precomp (66/67), and collective setpoint boost gain (71, the
-- axis-4 MSP_RC_TUNING field) -- see lib/msp_pid_profile.lua/
-- lib/msp_rc_tuning.lua's own headers for the wire-level confirmation of
-- each. IDs 76-81 (ADJUSTMENT_GOV_* throttle/headspeed/yaw-ff) are
-- reserved in the firmware header but have no get_/set_ implementation
-- anywhere yet, so they can't actually fire. IDs 82 (battery profile) and
-- 84-88 (master gain per axis, autohover gain, atthold gain) *are* real
-- and implemented, but have no page exposing an adjustment range for
-- them yet -- left for whenever those wingflight features are ported (see
-- AGENTS.md's migration notes), same as those features' own MSP fields.
return {
  [5] = "pitch rate",
  [6] = "roll rate",
  [7] = "yaw rate",
  [8] = "pitch rc rate",
  [9] = "roll rc rate",
  [10] = "yaw rc rate",
  [11] = "pitch rc expo",
  [12] = "roll rc expo",
  [13] = "yaw rc expo",
  [14] = "pitch p gain",
  [15] = "pitch i gain",
  [16] = "pitch d gain",
  [17] = "pitch f gain",
  [18] = "roll p gain",
  [19] = "roll i gain",
  [20] = "roll d gain",
  [21] = "roll f gain",
  [22] = "yaw p gain",
  [23] = "yaw i gain",
  [24] = "yaw d gain",
  [25] = "yaw f gain",
  [33] = "pitch gyro cutoff",
  [34] = "roll gyro cutoff",
  [35] = "yaw gyro cutoff",
  [36] = "pitch dterm cutoff",
  [37] = "roll dterm cutoff",
  [38] = "yaw dterm cutoff",
  [45] = "angle level gain",
  [46] = "horizon level gain",
  [47] = "acro gain",
  [56] = "pitch b gain",
  [57] = "roll b gain",
  [58] = "yaw b gain",
  [64] = "acc pitch trim",
  [65] = "acc roll trim",
  [68] = "pitch setpoint boost gain",
  [69] = "roll setpoint boost gain",
  [70] = "yaw setpoint boost gain",
  [72] = "yaw dyn ceiling gain",
  [73] = "yaw dyn deadband gain",
  [74] = "yaw dyn deadband filter",
}
