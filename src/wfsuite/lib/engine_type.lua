-- Whether a model is powered by a battery, which decides the wording the
-- suite uses in front of its fuel/smartfuel announcements.
--
-- The flight controller reports no powerplant type (MSP_SMARTFUEL_CONFIG is
-- mode, voltage fall, charge drop and sag gain only), so the answer comes from
-- the transmitter-side model preference and, on Auto, from the configured
-- battery config: a model that has a cell count or a configured pack capacity
-- has a battery. widgets/dashboard/context.lua's isElectricEngine() used
-- exactly that rule before this module existed; it lives here so the
-- dashboard and the audio callouts read one rule instead of two copies.
-- Ported from rotorflight-lua-ethos-suite PR #2401.

if package.loaded["wfsuite.lib.engine_type"] then
  return package.loaded["wfsuite.lib.engine_type"]
end

local engine_type = {}

-- The values of app/pages/power_smartfuel.lua's MODEL_TYPE_CHOICES.
engine_type.AUTO = 0
engine_type.ELECTRIC = 1
engine_type.NITRO = 2

-- A pack capacity entry is a plain number with the decoder in lib/msp_battery.lua,
-- but the dashboard also tolerates a string and a {capacity=} / {name=} table,
-- so all three shapes are read.
local function configuredCapacity(value)
  if type(value) == "number" then return value end
  if type(value) == "string" then return tonumber(value:match("(%d+)")) end
  if type(value) == "table" then
    if type(value.capacity) == "number" then return value.capacity end
    if type(value.capacity) == "string" then return tonumber(value.capacity:match("(%d+)")) end
    if type(value.name) == "string" then return tonumber(value.name:match("(%d+)")) end
  end
  return nil
end

-- Both index ranges are checked: lib/msp_battery.lua fills profiles[0]..[5],
-- while a list-shaped table would be 1..6.
function engine_type.hasConfiguredBatteryCapacity(config)
  if not config then return false end
  local capacity = tonumber(config.batteryCapacity) or 0
  if capacity > 0 then return true end

  local profiles = config.profiles
  if type(profiles) ~= "table" then return false end
  for i = 0, 5 do
    capacity = configuredCapacity(profiles[i])
    if capacity and capacity > 0 then return true end
  end
  for i = 1, 6 do
    capacity = configuredCapacity(profiles[i])
    if capacity and capacity > 0 then return true end
  end
  return false
end

-- config is the battery config table (session.batteryConfig /
-- widget.batteryConfig), or nil when none has been read yet, which answers
-- "no battery" as the dashboard always has.
function engine_type.isElectric(config, modelType)
  modelType = tonumber(modelType) or engine_type.AUTO
  if modelType == engine_type.AUTO then
    if not config then return false end
    local cellCount = tonumber(config.cellCount or config.batteryCellCount) or 0
    return cellCount ~= 0 or engine_type.hasConfiguredBatteryCapacity(config)
  end
  return modelType == engine_type.ELECTRIC
end

package.loaded["wfsuite.lib.engine_type"] = engine_type
return engine_type
