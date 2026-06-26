--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

local API_NAME = "MIXER_RULE"
local MSP_API_CMD_READ = 172
local MSP_API_CMD_WRITE = 173

local RULE_COUNT = 32

-- Per-rule fields, in firmware wire order (mixerRule_t, pg/mixer.h):
--   field, type, min, max, default, unit, decimals, scale
local RULE_FIELDS = {
    {"oper", "U8", 0, 3},
    {"input", "U8", 0, 28},
    {"output", "U8", 0, 12},
    {"offset", "S16", -2500, 2500, 0, "%", 1, 10},
    {"weight", "S16", -10000, 10000, 0, "%", 1, 10},
    {"weightNeg", "S16", -10000, 10000, 0, "%", 1, 10},
    {"reverse", "U8", 0, 1},
    {"speed", "U16", 0, 60000},
    {"curve", "U8", 0, 8}
}

-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos, offset, xvals
-- Flattened as <field>_<ruleIndex> (0-based, matching the firmware array index)
-- since MSP_MIXER_RULES always returns all RULE_COUNT rules in one response.
local FIELD_SPEC = {}
for i = 0, RULE_COUNT - 1 do
    for _, fieldDef in ipairs(RULE_FIELDS) do
        local entry = {}
        for idx, value in ipairs(fieldDef) do
            entry[idx] = value
        end
        entry[1] = fieldDef[1] .. "_" .. i
        FIELD_SPEC[#FIELD_SPEC + 1] = entry
    end
end

-- Writes target a single rule at a time (MSP_SET_MIXER_RULE), index-prefixed.
-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos, offset, xvals
local WRITE_FIELD_SPEC = {
    {"index", "U8"},
    {"oper", "U8", 0, 3},
    {"input", "U8", 0, 28},
    {"output", "U8", 0, 12},
    {"offset", "S16", -2500, 2500, 0, "%", 1, 10},
    {"weight", "S16", -10000, 10000, 0, "%", 1, 10},
    {"weightNeg", "S16", -10000, 10000, 0, "%", 1, 10},
    {"reverse", "U8", 0, 1},
    {"speed", "U16", 0, 60000},
    {"curve", "U8", 0, 8}
}

local function appendU8(bytes, v)
    bytes[#bytes + 1] = v & 0xFF
end

local function appendU16(bytes, v)
    bytes[#bytes + 1] = v & 0xFF
    bytes[#bytes + 1] = (v >> 8) & 0xFF
end

local function appendS16(bytes, v)
    if v < 0 then v = v + 0x10000 end
    appendU16(bytes, v)
end

-- Standard Glider defaults (rule 0-4), remaining rules left NUL/zeroed -
-- mirrors pgResetFn_mixerRules() in wingflight-firmware/src/main/pg/mixer.c
local DEFAULT_RULES = {
    {1, 1, 1, 0, 1000, 1000, 0, 0, 0},   -- S1: aileron (Stabilized Roll)
    {1, 1, 2, 0, -1000, -1000, 0, 0, 0}, -- S2: aileron, reversed
    {1, 2, 3, 0, 1000, 1000, 0, 0, 0},   -- S3: elevator (Stabilized Pitch)
    {1, 3, 4, 0, 1000, 1000, 0, 0, 0},   -- S4: rudder (Stabilized Yaw)
    {1, 15, 9, 0, 1000, 1000, 0, 0, 0}   -- M1: throttle passthrough
}

local function buildSimResponse()
    local bytes = {}

    for i = 0, RULE_COUNT - 1 do
        local rule = DEFAULT_RULES[i + 1] or {0, 0, 0, 0, 0, 0, 0, 0, 0}
        appendU8(bytes, rule[1])   -- oper
        appendU8(bytes, rule[2])   -- input
        appendU8(bytes, rule[3])   -- output
        appendS16(bytes, rule[4])  -- offset
        appendS16(bytes, rule[5])  -- weight
        appendS16(bytes, rule[6])  -- weightNeg
        appendU8(bytes, rule[7])   -- reverse
        appendU16(bytes, rule[8])  -- speed
        appendU8(bytes, rule[9])   -- curve
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
        ruleCount = RULE_COUNT,
        simulatorResponse = SIM_RESPONSE
    }
})
