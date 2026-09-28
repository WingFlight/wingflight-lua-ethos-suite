-- Arming-disable flag decoding for Tools -> Diagnostics -> FBL Status.
--
-- Split out of app/pages/diagnostics_fblstatus.lua so the mask arithmetic can
-- be checked without a radio (bin/tests/arming_flags.lua). The page keeps the
-- layout; this file keeps the arithmetic.
--
-- The page used to join every active flag's name into the value column, the
-- narrow right-hand half of the row, which does not wrap: with a few flags set
-- the reason blocking arming was cut off the right edge. So the value column
-- gets summary() -- "OK" or a count, short by construction -- and the names
-- are listed by active() for the page to put on full-width rows. Ported from
-- rotorflight-lua-ethos-suite PR #2409.
--
-- Bits follow wingflight-firmware's armingDisableFlags_e
-- (src/main/fc/runtime_config.h): 0..26 are named reasons, 27 is ARM_SWITCH.

if package.loaded["wfsuite.lib.arming_flags"] then
  return package.loaded["wfsuite.lib.arming_flags"]
end

local arming_flags = {}

local FLAG_TAGS = {
  [0] = "@i18n(app.modules.fblstatus.arming_disable_flag_0)@",
  [1] = "@i18n(app.modules.fblstatus.arming_disable_flag_1)@",
  [2] = "@i18n(app.modules.fblstatus.arming_disable_flag_2)@",
  [3] = "@i18n(app.modules.fblstatus.arming_disable_flag_3)@",
  [4] = "@i18n(app.modules.fblstatus.arming_disable_flag_4)@",
  [5] = "@i18n(app.modules.fblstatus.arming_disable_flag_5)@",
  [6] = "@i18n(app.modules.fblstatus.arming_disable_flag_6)@",
  [7] = "@i18n(app.modules.fblstatus.arming_disable_flag_7)@",
  [8] = "@i18n(app.modules.fblstatus.arming_disable_flag_8)@",
  [9] = "@i18n(app.modules.fblstatus.arming_disable_flag_9)@",
  [10] = "@i18n(app.modules.fblstatus.arming_disable_flag_10)@",
  [11] = "@i18n(app.modules.fblstatus.arming_disable_flag_11)@",
  [12] = "@i18n(app.modules.fblstatus.arming_disable_flag_12)@",
  [13] = "@i18n(app.modules.fblstatus.arming_disable_flag_13)@",
  [14] = "@i18n(app.modules.fblstatus.arming_disable_flag_14)@",
  [15] = "@i18n(app.modules.fblstatus.arming_disable_flag_15)@",
  [16] = "@i18n(app.modules.fblstatus.arming_disable_flag_16)@",
  [17] = "@i18n(app.modules.fblstatus.arming_disable_flag_17)@",
  [18] = "@i18n(app.modules.fblstatus.arming_disable_flag_18)@",
  [19] = "@i18n(app.modules.fblstatus.arming_disable_flag_19)@",
  [20] = "@i18n(app.modules.fblstatus.arming_disable_flag_20)@",
  [21] = "@i18n(app.modules.fblstatus.arming_disable_flag_21)@",
  [22] = "@i18n(app.modules.fblstatus.arming_disable_flag_22)@",
  [23] = "@i18n(app.modules.fblstatus.arming_disable_flag_23)@",
  [24] = "@i18n(app.modules.fblstatus.arming_disable_flag_24)@",
  [25] = "@i18n(app.modules.fblstatus.arming_disable_flag_25)@",
  [26] = "@i18n(app.modules.fblstatus.arming_disable_flag_26)@",
  [27] = "@i18n(app.modules.fblstatus.arming_disable_flag_27)@",
}

-- ARMING_DISABLED_ARM_SWITCH is set whenever the arm switch is on while
-- anything else blocks arming, so next to a real reason it only repeats "and
-- the arm switch is on" (the same reason widgets/dashboard/context.lua's
-- armingDisableFlagsToString() leaves it out). On its own it *is* the reason:
-- the switch was on at power-up or after a disarm and has to be turned off.
local ARM_SWITCH_BIT = 27
local HIGHEST_BIT = 31

arming_flags.FLAG_TAGS = FLAG_TAGS
arming_flags.ARM_SWITCH_BIT = ARM_SWITCH_BIT

function arming_flags.normalize(mask)
  local value = tonumber(mask)
  if not value or value ~= value or value < 0 then return 0 end
  return math.floor(value)
end

function arming_flags.hasBit(mask, bit)
  return math.floor(arming_flags.normalize(mask) / (2 ^ bit)) % 2 >= 1
end

-- Names of the active flags, lowest bit first, written into `out` (cleared in
-- place, so a caller can reuse one table). A set bit with no name is shown as
-- its mask value rather than dropped, so no reason is ever invisible.
function arming_flags.active(mask, out)
  out = out or {}
  for i = #out, 1, -1 do out[i] = nil end
  mask = arming_flags.normalize(mask)
  for bit = 0, HIGHEST_BIT do
    if bit ~= ARM_SWITCH_BIT and arming_flags.hasBit(mask, bit) then
      out[#out + 1] = FLAG_TAGS[bit] or string.format("0x%X", math.floor(2 ^ bit))
    end
  end
  if #out == 0 and arming_flags.hasBit(mask, ARM_SWITCH_BIT) then
    out[1] = FLAG_TAGS[ARM_SWITCH_BIT]
  end
  return out
end

-- The value-column text and the number of reasons. Never the names: the value
-- column cannot hold them.
function arming_flags.summary(count)
  if count == 0 then return "@i18n(app.modules.fblstatus.ok)@" end
  return string.format("@i18n(app.modules.fblstatus.arming_flags_active_fmt)@", count)
end

package.loaded["wfsuite.lib.arming_flags"] = arming_flags
return arming_flags
