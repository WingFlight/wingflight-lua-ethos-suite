-- Message-builders + decoders for BATTERY_CONFIG (cmd 32) and
-- SMARTFUEL_CONFIG (cmd 0x4000). Stateless. Used by tasks/session.lua.
--
-- Field order/scale transcribed from rotorflight-lua-ethos-suite's
-- tasks/scheduler/msp/api/{BATTERY_CONFIG,SMARTFUEL_CONFIG}.lua. This
-- rebuild's floor (Wingflight 2.3 / MSP API >= 12.09) always includes the
-- six per-profile batteryCapacity_0..5 fields the original only reads on
-- newer firmware -- no version gating needed. Those values are kept in
-- `profiles[0]..profiles[5]` so the dashboard can offer the same battery
-- profile selector without loading the heavier app page.
--
-- Both decoders below check the payload length before reading a single byte
-- (ported from rotorflight/rotorflight-lua-ethos-suite#2417). A decoder that
-- ran off the end of a short payload either raised inside the background
-- task (SMARTFUEL_CONFIG used to divide a nil readU8 by 1000) or, now that
-- lib/mspcodec.lua defaults a missing byte to 0, would quietly produce a
-- config of zeros -- one that still satisfies session.lua's handshake guard
-- and only fails much later, in announceVoltage() or a dashboard gauge, far
-- from the cause. Refusing the payload and reporting it through errorHandler
-- keeps the failure at the one place it belongs.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local msp_battery = {}

msp_battery.BATTERY_CONFIG_READ_COMMAND = 32

-- Wire size, verified against wingflight-firmware's own handler
-- (src/main/msp/msp.c, case MSP_BATTERY_CONFIG), not rotorflight's:
--   15 legacy bytes: u16 batteryCapacity + u8 cellCount + u8
--   voltageMeterSource + u8 currentMeterSource + 4x u16 cell voltages + u8
--   lvcPercentage + u8 consumptionWarningPercentage;
--   then BATTERY_PROFILE_COUNT (6, src/main/pg/battery.h) u16 capacities = 12;
--   then 6x u8 cell counts + 4 x 6x u16 cell voltages = 54.
-- Current wingflight-firmware writes all 81 unconditionally. The last block
-- (rotorflight-firmware #508) is still treated as optional here, as it always
-- has been, so firmware without it keeps working: 27 is the minimum a reply
-- must carry to be decoded at all, 81 the size that also fills profileCells.
msp_battery.BATTERY_CONFIG_SIZE = 27
msp_battery.BATTERY_CONFIG_PROFILE_CELLS_SIZE = 81

local function decodeBatteryConfig(buf)
  if type(buf) ~= "table" or #buf < msp_battery.BATTERY_CONFIG_SIZE then
    return nil, "short_payload"
  end

  local batteryCapacity = mspcodec.readU16(buf)
  local cellCount = mspcodec.readU8(buf)
  mspcodec.readU8(buf) -- voltageMeterSource (unused)
  mspcodec.readU8(buf) -- currentMeterSource (unused)
  local vbatMinCell = mspcodec.readU16(buf) / 100
  local vbatMaxCell = mspcodec.readU16(buf) / 100
  local vbatFullCell = mspcodec.readU16(buf) / 100
  local vbatWarningCell = mspcodec.readU16(buf) / 100
  mspcodec.readU8(buf) -- lvcPercentage (unused)
  local consumptionWarningPercentage = mspcodec.readU8(buf)
  local profiles = {}
  for i = 0, 5 do
    profiles[i] = mspcodec.readU16(buf)
  end
  -- Per-profile cell count / cell voltages. The legacy fields above are the
  -- FC's active profile at read time; tasks/session.lua re-resolves them from
  -- these whenever the active battery profile changes. Only decoded when the
  -- whole block is there: a partial one would be zeros, not "absent".
  local profileCells = nil
  if #buf >= msp_battery.BATTERY_CONFIG_PROFILE_CELLS_SIZE then
    profileCells = {}
    for i = 0, 5 do profileCells[i] = {cellCount = mspcodec.readU8(buf)} end
    for i = 0, 5 do profileCells[i].vbatMinCell = mspcodec.readU16(buf) / 100 end
    for i = 0, 5 do profileCells[i].vbatMaxCell = mspcodec.readU16(buf) / 100 end
    for i = 0, 5 do profileCells[i].vbatFullCell = mspcodec.readU16(buf) / 100 end
    for i = 0, 5 do profileCells[i].vbatWarningCell = mspcodec.readU16(buf) / 100 end
  end
  return {
    batteryCapacity = batteryCapacity,
    cellCount = cellCount,
    vbatMinCell = vbatMinCell,
    vbatMaxCell = vbatMaxCell,
    vbatFullCell = vbatFullCell,
    vbatWarningCell = vbatWarningCell,
    consumptionWarningPercentage = consumptionWarningPercentage,
    profiles = profiles,
    profileCells = profileCells,
  }
end

function msp_battery.buildBatteryConfigReadMessage(onData, onError)
  return {
    command = msp_battery.BATTERY_CONFIG_READ_COMMAND,
    processReply = function(_, buf)
      local config, reason = decodeBatteryConfig(buf)
      if not config then
        if onError then onError(reason) end
        return
      end
      onData(config)
    end,
    errorHandler = onError,
    simulatorResponse = {
      136, 19, -- batteryCapacity = 5000 mAh
      6,       -- batteryCellCount
      1,       -- voltageMeterSource
      1,       -- currentMeterSource
      74, 1,   -- vbatmincellvoltage = 330 -> 3.30V
      164, 1,  -- vbatmaxcellvoltage = 420 -> 4.20V
      154, 1,  -- vbatfullcellvoltage = 410 -> 4.10V
      94, 1,   -- vbatwarningcellvoltage = 350 -> 3.50V
      100,     -- lvcPercentage
      30,      -- consumptionWarningPercentage
      232, 3, 20, 5, 64, 6, 108, 7, 152, 8, 196, 9, -- batteryCapacity_0..5
      6, 6, 6, 6, 6, 6,                               -- batteryCellCount_0..5
      74, 1, 74, 1, 74, 1, 74, 1, 74, 1, 74, 1,       -- vbatmincellvoltage_0..5
      164, 1, 164, 1, 164, 1, 164, 1, 164, 1, 164, 1, -- vbatmaxcellvoltage_0..5
      154, 1, 154, 1, 154, 1, 154, 1, 154, 1, 154, 1, -- vbatfullcellvoltage_0..5
      94, 1, 94, 1, 94, 1, 94, 1, 94, 1, 94, 1,       -- vbatwarningcellvoltage_0..5
    },
  }
end

msp_battery.SMARTFUEL_CONFIG_READ_COMMAND = 0x4000

-- wingflight-firmware src/main/msp/msp.c, case MSP2_GET_SMARTFUEL_CONFIG
-- (guarded by USE_SMARTFUEL): four u8 fields -- smartfuel_mode,
-- voltage_drop_rate, charge_drop_rate, sag_gain.
msp_battery.SMARTFUEL_CONFIG_SIZE = 4

local function decodeSmartfuelConfig(buf)
  if type(buf) ~= "table" or #buf < msp_battery.SMARTFUEL_CONFIG_SIZE then
    return nil, "short_payload"
  end

  local mode = mspcodec.readU8(buf)
  local voltageDropRate = mspcodec.readU8(buf)
  local chargeDropRate = mspcodec.readU8(buf)
  mspcodec.readU8(buf) -- sag_gain (unused -- no sag compensation, see lib/smartfuel_calc.lua)
  return {
    mode = mode,
    voltageFallPerSecond = voltageDropRate / 1000, -- mV/s -> V/s
    chargeDropPerSecond = chargeDropRate / 10000,  -- raw -> fraction/s
  }
end

-- mode: 0 = off (FC doesn't compute/broadcast it -- run the local
-- fallback, see lib/smartfuel_calc.lua), 1/2/3 = voltage/current/combined
-- (FC computes it on-board and broadcasts it -- just mirror the sensor,
-- see tasks/session.lua).
function msp_battery.buildSmartfuelConfigReadMessage(onData, onError)
  return {
    command = msp_battery.SMARTFUEL_CONFIG_READ_COMMAND,
    processReply = function(_, buf)
      local config, reason = decodeSmartfuelConfig(buf)
      if not config then
        if onError then onError(reason) end
        return
      end
      onData(config)
    end,
    errorHandler = onError,
    simulatorResponse = {0, 10, 50, 40},
  }
end

return msp_battery
