--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

local API_NAME = "MIXER_CURVE"
local MSP_API_CMD_READ = 177
local MSP_API_CMD_WRITE = 178

local CURVE_COUNT = 8
local POINT_COUNT = 9

-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos, offset, xvals
-- Flattened as count_<curveIndex> / x_<curveIndex>_<pointIndex> / y_<curveIndex>_<pointIndex>
-- (0-based, matching the firmware array indices) since MSP_MIXER_CURVES always
-- returns all CURVE_COUNT curves, each with all POINT_COUNT point slots, in one
-- response - only the first `count` points of each curve are meaningful, the
-- rest are unused filler kept to match the fixed-size wire format.
local FIELD_SPEC = {}
for i = 0, CURVE_COUNT - 1 do
    FIELD_SPEC[#FIELD_SPEC + 1] = {"count_" .. i, "U8", 2, POINT_COUNT}
    for p = 0, POINT_COUNT - 1 do
        FIELD_SPEC[#FIELD_SPEC + 1] = {"x_" .. i .. "_" .. p, "S16", -1000, 1000}
        FIELD_SPEC[#FIELD_SPEC + 1] = {"y_" .. i .. "_" .. p, "S16", -1000, 1000}
    end
end

-- Writes target a single curve at a time (MSP_SET_MIXER_CURVE), index-prefixed.
-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos, offset, xvals
local WRITE_FIELD_SPEC = {
    {"index", "U8"},
    {"count", "U8", 2, POINT_COUNT}
}
for p = 0, POINT_COUNT - 1 do
    WRITE_FIELD_SPEC[#WRITE_FIELD_SPEC + 1] = {"x_" .. p, "S16", -1000, 1000}
    WRITE_FIELD_SPEC[#WRITE_FIELD_SPEC + 1] = {"y_" .. p, "S16", -1000, 1000}
end

local function appendU8(bytes, v)
    bytes[#bytes + 1] = v & 0xFF
end

local function appendS16(bytes, v)
    if v < 0 then v = v + 0x10000 end
    bytes[#bytes + 1] = v & 0xFF
    bytes[#bytes + 1] = (v >> 8) & 0xFF
end

-- Every curve defaults to a neutral 2-point passthrough line - mirrors
-- pgResetFn_mixerCurves() in wingflight-firmware/src/main/pg/mixer.c
local function buildSimResponse()
    local bytes = {}

    for _ = 0, CURVE_COUNT - 1 do
        appendU8(bytes, 2)        -- count
        appendS16(bytes, -1000)   -- point 0 x
        appendS16(bytes, -1000)   -- point 0 y
        appendS16(bytes, 1000)    -- point 1 x
        appendS16(bytes, 1000)    -- point 1 y
        for _ = 2, POINT_COUNT - 1 do
            appendS16(bytes, 0)   -- unused point x
            appendS16(bytes, 0)   -- unused point y
        end
    end

    return bytes
end

local SIM_RESPONSE = core.simResponse(buildSimResponse())

return core.createConfigAPI({
    name = API_NAME,
    readCmd = MSP_API_CMD_READ,
    writeCmd = MSP_API_CMD_WRITE,
    fields = FIELD_SPEC,
    writeFields = WRITE_FIELD_SPEC,
    simulatorResponseRead = SIM_RESPONSE,
    writeUuidFallback = true,
    initialRebuildOnWrite = true,
    exports = {
        curveCount = CURVE_COUNT,
        pointCount = POINT_COUNT,
        simulatorResponse = SIM_RESPONSE
    }
})
