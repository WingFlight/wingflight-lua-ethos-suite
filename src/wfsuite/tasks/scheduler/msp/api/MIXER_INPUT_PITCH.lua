--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

local API_NAME = "MIXER_INPUT_PITCH"
local MSP_API_CMD_READ = 170
local MSP_API_CMD_WRITE = 171

-- MSP_MIXER_INPUTS (170) always returns every mixer input (rate/min/max,
-- S16 each) in firmware wire order starting at MIXER_IN_NONE = 0; this input
-- is MIXER_IN_STABILIZED_PITCH = 2 (see pg/mixer.h). MSP_SET_MIXER_INPUT (171)
-- writes a single input, index-prefixed.
local INPUT_INDEX = 2

-- The GUI exposes this as a plain 0-200% Gain plus a separate Invert choice,
-- rather than the signed rate the wire uses directly -- mirrors the same
-- split done in the desktop configurator's mixer tab (see wingflight-
-- configurator src/js/tabs/mixer.js rateToPercent/percentToRate). min/max
-- aren't user-editable here; they're carried through unchanged on write.
local FIELD_SPEC = {
    {"gain", "U8", 0, 200, 100, "%"},
    {"invert", "U8", 0, 1, nil, nil, nil, nil, nil, nil, {"@i18n(app.modules.mixer.normal)@", "@i18n(app.modules.mixer.inverted)@"}, -1},
}

local function parseRead(buf, helper)
    if not helper then return nil, "msp_helper_missing" end
    if type(buf) ~= "table" then return nil, "missing_buffer" end

    buf.offset = 1

    local rate, minVal, maxVal
    for i = 0, INPUT_INDEX do
        rate = helper.readS16(buf)
        minVal = helper.readS16(buf)
        maxVal = helper.readS16(buf)
        if rate == nil or minVal == nil or maxVal == nil then
            return nil, "short_mixer_inputs"
        end
    end

    local invert = (rate < 0) and 1 or 0
    local gain = (rate < 0) and -rate or rate
    gain = gain // 10
    if gain > 200 then gain = 200 end

    return {
        parsed = {gain = gain, invert = invert, min = minVal, max = maxVal},
        buffer = buf,
        receivedBytesCount = #buf
    }
end

local function buildWritePayload(payloadData, _, helper)
    local gain = tonumber(payloadData.gain) or 100
    if gain < 0 then gain = 0 elseif gain > 200 then gain = 200 end

    local rate = gain * 10
    if (tonumber(payloadData.invert) or 0) ~= 0 then rate = -rate end

    local minVal = tonumber(payloadData.min) or -1000
    local maxVal = tonumber(payloadData.max) or 1000

    local bytes = {}
    helper.writeU8(bytes, INPUT_INDEX)
    helper.writeS16(bytes, rate)
    helper.writeS16(bytes, minVal)
    helper.writeS16(bytes, maxVal)
    return bytes
end

-- Simulator response only needs to cover bytes through this input's slot;
-- defaults mirror pgResetFn_mixerInputs() in wingflight-firmware/src/main/pg/mixer.c.
local SIM_RESPONSE = core.simResponse({
    0, 0,     0, 0,     0, 0,        -- MIXER_IN_NONE:             rate=0,    min=0,     max=0
    232, 3,   24, 252,   232, 3,     -- MIXER_IN_STABILIZED_ROLL:  rate=1000, min=-1000, max=1000
    232, 3,   24, 252,   232, 3,     -- MIXER_IN_STABILIZED_PITCH: rate=1000, min=-1000, max=1000
})

return core.createConfigAPI({
    name = API_NAME,
    readCmd = MSP_API_CMD_READ,
    writeCmd = MSP_API_CMD_WRITE,
    fields = FIELD_SPEC,
    parseRead = parseRead,
    buildWritePayload = buildWritePayload,
    simulatorResponseRead = SIM_RESPONSE,
    writeUuidFallback = true,
    exports = {
        inputIndex = INPUT_INDEX,
        simulatorResponse = SIM_RESPONSE
    }
})
