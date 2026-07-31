-- Mixer Config page. Loaded on demand from Setup -> Mixer.
--
-- Wingflight's own feature (not part of the rotorflight-based rewrite this
-- base came from -- see AGENTS.md's migration notes): scales/inverts the
-- stabilized Roll/Pitch/Yaw axes that every mixer rule reads from, via
-- MSP_GET_MIXER_INPUT/MSP_SET_MIXER_INPUT (cmd 174/171, one index per
-- axis -- see lib/msp_mixer_input.lua). One flight controller adjustment
-- affecting every rule reading that axis at once, rather than editing
-- each rule individually -- see @i18n(app.modules.mixer.axis_gain_help)@.
--
-- Each axis's single wire field (`rate`, signed S16) is *split* into two
-- widgets here: Gain (0-200%, |rate|/10) and Invert (rate's sign) --
-- matches this project's own last-known-good app/modules/mixer/mixer.lua
-- and tasks/scheduler/msp/api/MIXER_INPUT_ROLL.lua's parseRead()/
-- buildWritePayload() exactly (gain = min(200, |rate|//10), invert =
-- rate < 0). `min`/`max` (the wire's other two fields) are read but never
-- shown here -- carried through unchanged on write, same as that
-- project's own comment on why they aren't user-editable from this page.
--
-- Three independent MSP commands (one per axis, lib/msp_mixer_input.lua's
-- roll()/pitch()/yaw() factories), combined via app/page_runtime.lua's
-- multi-source `sources` list -- see app/pages/alignment.lua for the same
-- pattern with two sources instead of three. Not profile-scoped
-- (`profileField = "none"`): mixer input scaling is a per-aircraft
-- geometry setting, not something that varies by PID/rate profile,
-- same reasoning as app/pages/alignment.lua's own board-alignment data.

local pageRuntime = assert(loadfile("app/page_runtime.lua"))()
local mixerInput = assert(loadfile("lib/msp_mixer_input.lua"))()

local PAGE_TITLE = "@i18n(app.modules.mixer.name)@"
local GAIN_MAX = 200

local INVERT_OPTIONS = {
  {"@i18n(app.modules.mixer.normal)@", 0},
  {"@i18n(app.modules.mixer.inverted)@", 1},
}

-- key: source key (also lib/msp_mixer_input.lua's factory name).
-- rateKey: the field name that factory's decode()/encode() uses.
local AXES = {
  {key = "roll", label = "@i18n(app.modules.mixer.roll)@", rateKey = "rate_stabilized_roll"},
  {key = "pitch", label = "@i18n(app.modules.mixer.pitch)@", rateKey = "rate_stabilized_pitch"},
  {key = "yaw", label = "@i18n(app.modules.mixer.yaw)@", rateKey = "rate_stabilized_yaw"},
}

local function gainFromRate(rate)
  rate = rate or 0
  local gain = (rate < 0 and -rate or rate) // 10
  if gain > GAIN_MAX then gain = GAIN_MAX end
  return gain
end

local function invertFromRate(rate)
  return ((rate or 0) < 0) and 1 or 0
end

local function open(opts)
  local sources = {}
  for _, axis in ipairs(AXES) do
    sources[#sources + 1] = {key = axis.key, mspModule = mixerInput[axis.key]()}
  end

  local runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "mixerconfig",
    sources = sources,
    opts = opts,
    profileField = "none",
    unloadPackageKeys = {"wfsuite.lib.msp_mixer_input"},
  })

  form.clear()
  runtime:buildChrome()

  local headerLine = form.addLine(" ")
  local headerSlots = form.getFieldSlots(headerLine, {0, 0})
  form.addStaticText(headerLine, headerSlots[1], "@i18n(app.modules.mixer.gain)@", RIGHT)
  form.addStaticText(headerLine, headerSlots[2], "@i18n(app.modules.mixer.invert)@", RIGHT)

  for _, axis in ipairs(AXES) do
    local line = form.addLine(axis.label)
    local slots = form.getFieldSlots(line, {0, 0})
    local data = runtime.data[axis.key]

    local gainField = form.addNumberField(line, slots[1], 0, GAIN_MAX,
      function()
        return gainFromRate(data[axis.rateKey])
      end,
      function(value)
        runtime:markDirty()
        local invert = invertFromRate(data[axis.rateKey])
        local rate = (tonumber(value) or 0) * 10
        if invert == 1 then rate = -rate end
        data[axis.rateKey] = rate
      end)
    gainField:suffix("%")
    runtime:registerField(axis.key .. "_gain", gainField)

    local invertField = form.addChoiceField(line, slots[2], INVERT_OPTIONS,
      function()
        return invertFromRate(data[axis.rateKey])
      end,
      function(value)
        runtime:markDirty()
        local gain = gainFromRate(data[axis.rateKey])
        local rate = gain * 10
        if (tonumber(value) or 0) ~= 0 then rate = -rate end
        data[axis.rateKey] = rate
      end)
    runtime:registerField(axis.key .. "_invert", invertField)
  end

  runtime:loadInitial()
end

return {open = open}
