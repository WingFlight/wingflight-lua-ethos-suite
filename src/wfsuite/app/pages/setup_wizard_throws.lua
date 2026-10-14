-- Setup Wizard step: Throws. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepThrows.svelte. The
-- wizard forces PASSTHROUGH on top of the setup state, so the pilot's sticks
-- drive the surfaces with no gyro, and Axis Throw and servo scale still
-- apply (flight/mixer.c). For each axis the mix uses:
--
--   axis   hold the stick full one way, measure the surface, and step the
--          axis's Throw (Axis Throw, every surface on the axis, both ways)
--   fine   optional: one surface, one stick direction at a time, step that
--          servo's scale on the side that direction uses (differential, or a
--          surface that comes out different from its pair)
--
-- Each surface is fine-tuned on its own axis only: a surface that works two
-- axes has one scale per side for both. A surface that reaches its binding
-- limit before full stick on this axis alone is flagged.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")
local art = requireModule("app/setup_wizard_art.lua")
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.thr_title)@",
  intro = "@i18n(app.modules.setup_wizard.thr_intro)@",
  axis = "@i18n(app.modules.setup_wizard.thr_axis_fmt)@",
  fine = "@i18n(app.modules.setup_wizard.thr_fine_fmt)@",
  fineIntro = "@i18n(app.modules.setup_wizard.thr_fine_intro)@",
  atLimit = "@i18n(app.modules.setup_wizard.thr_at_limit_fmt)@",
  sideLimit = "@i18n(app.modules.setup_wizard.thr_side_limit)@",
  noPass = "@i18n(app.modules.setup_wizard.thr_no_passthrough)@",
  fineBtn = "@i18n(app.modules.setup_wizard.thr_fine_btn)@",
  progress = "@i18n(app.modules.setup_wizard.progress_fmt)@",
  doneTitle = "@i18n(app.modules.setup_wizard.thr_done_title)@",
  done = "@i18n(app.modules.setup_wizard.thr_done)@",
  start = "@i18n(app.modules.setup_wizard.btn_start)@",
  skip = "@i18n(app.modules.setup_wizard.btn_skip)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
  again = "@i18n(app.modules.setup_wizard.btn_again)@",
  saveNext = "@i18n(app.modules.setup_wizard.dir_save_next)@",
}

-- Full stick each way. Signs as in the Direction step: roll + is right,
-- pitch - is stick back, yaw - is right.
local DIRECTIONS = {
  roll = {{stick = 1, name = "@i18n(app.modules.setup_wizard.thr_roll_right)@"},
    {stick = -1, name = "@i18n(app.modules.setup_wizard.thr_roll_left)@", flip = true}},
  pitch = {{stick = -1, name = "@i18n(app.modules.setup_wizard.thr_pitch_back)@"},
    {stick = 1, name = "@i18n(app.modules.setup_wizard.thr_pitch_forward)@", flip = true}},
  yaw = {{stick = -1, name = "@i18n(app.modules.setup_wizard.thr_yaw_right)@"},
    {stick = 1, name = "@i18n(app.modules.setup_wizard.thr_yaw_left)@", flip = true}},
}
local AXIS_NAMES = {
  roll = "@i18n(app.modules.setup_wizard.axis_roll)@",
  pitch = "@i18n(app.modules.setup_wizard.axis_pitch)@",
  yaw = "@i18n(app.modules.setup_wizard.axis_yaw)@",
}

local AXIS_GAIN_MAX = 200
-- Servo scale shown as a percentage of the firmware default (500).
local DEFAULT_SCALE = 500
local SCALE_STEP = DEFAULT_SCALE / 100
local STEPS = {-5, -1, 1, 5}

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)

  local axes = {}
  for _, axis in ipairs({"roll", "pitch", "yaw"}) do
    for _, s in ipairs(wiz.surfaces()) do
      if s.axes[axis] then axes[#axes + 1] = axis; break end
    end
  end

  local screen = "intro"
  local ai = 1
  local fineList, fi = {}, 1      -- {surface, direction} pairs for this axis

  local function axis() return axes[ai] end

  local function forcePassthrough()
    if wiz.forcedMode() ~= wiz.BOX_PASSTHROUGH then wiz.forceMode(wiz.BOX_PASSTHROUGH) end
  end

  -- Surfaces on this axis that hit a limit with this axis alone at full stick.
  local function limited(a)
    local names = {}
    local gains = wiz.axisGains()
    for _, s in ipairs(wiz.surfaces()) do
      if s.axes[a] then
        local alone = {servo = s.servo, axes = {[a] = s.axes[a]}, axisOrder = {a}, kind = s.kind}
        local reach = surfacesLib.travelReach(alone, wiz.configs[s.servo], gains)
        if reach.pos.fraction > 1 or reach.neg.fraction > 1 then names[#names + 1] = tostring(s.servo + 1) end
      end
    end
    return names
  end

  -- Which scale field this stick direction uses on this servo, and the most
  -- it may be before full stick passes that side's binding limit.
  local function sideOf(surface, a, direction)
    local config = wiz.configs[surface.servo]
    local output = surfacesLib.outputForAxis(surface, a, direction.stick, wiz.axisGains())
    local reversed = ((config.flags or 0) & surfacesLib.SERVO_FLAG_REVERSE) ~= 0
    local pos = surfacesLib.servoSide(output, reversed) == "pos"
    return pos and "rpos" or "rneg", surfacesLib.maxScale(output, pos and config.max or -config.min)
  end

  local function nudgeThrow(delta)
    local a = axis()
    local nextValue = math.max(0, math.min(AXIS_GAIN_MAX, wiz.axisGainPercent(a) + delta))
    wiz.setAxisGainPercent(a, nextValue)
    wiz.rebuild()
  end

  local function nudgeScale(delta)
    local item = fineList[fi]
    local field, most = sideOf(item.surface, axis(), item.direction)
    wiz.editServo(item.surface.servo, function(config)
      config[field] = math.min(most, math.max(surfacesLib.SCALE_MIN, config[field] + delta * SCALE_STEP))
    end)
    wiz.rebuild()
  end

  local function startFine()
    fineList, fi = {}, 1
    for _, s in ipairs(wiz.surfaces()) do
      if s.axes[axis()] and surfacesLib.primaryAxis(s) == axis() then
        for _, d in ipairs(DIRECTIONS[axis()]) do fineList[#fineList + 1] = {surface = s, direction = d} end
      end
    end
    screen = #fineList > 0 and "fine" or "axis"
    wiz.rebuild()
  end

  local function nextAxis()
    if ai < #axes then
      ai = ai + 1
      screen = "axis"
    else
      screen = "done"
      wiz.releaseMode()
    end
    wiz.rebuild()
  end

  local function stepButtons(press, extra)
    local specs = {}
    for _, d in ipairs(STEPS) do
      specs[#specs + 1] = {text = (d > 0 and "+" or "") .. d .. "%", small = true, weight = 0.7, needsMotion = true,
        press = function() press(d) end}
    end
    for _, e in ipairs(extra) do specs[#specs + 1] = e end
    return scr:buttons(specs)
  end

  function self.build()
    scr:begin()
    local passNote = (screen ~= "intro" and screen ~= "done" and wiz.forcedMode() ~= wiz.BOX_PASSTHROUGH)
      and T.noPass or nil

    if screen == "intro" or #axes == 0 then
      scr:text(T.title, T.intro)
      return scr:buttons({
        {text = T.skip, press = function() wiz.skipStep() end},
        {text = T.start, primary = true, needsMotion = true, disabled = #axes == 0, press = function()
          forcePassthrough()
          ai, screen = 1, "axis"
          wiz.rebuild()
        end},
      })

    elseif screen == "axis" then
      local a = axis()
      local lim = limited(a)
      local accent = passNote or (#lim > 0 and string.format(T.atLimit, table.concat(lim, ", ")) or nil)
      scr:text(AXIS_NAMES[a] .. "  " .. string.format(T.progress, ai, #axes),
        string.format(T.axis, DIRECTIONS[a][1].name, wiz.axisGainPercent(a)), accent)
      scr:picture(art.layout(wiz.surfaces(), a))
      return stepButtons(nudgeThrow, {
        {text = T.fineBtn, small = true, press = startFine},
        {text = T.next, primary = true, small = true, press = nextAxis},
      })

    elseif screen == "fine" then
      local item = fineList[fi]
      local field, most = sideOf(item.surface, axis(), item.direction)
      local config = wiz.configs[item.surface.servo]
      local pct = math.floor(config[field] / SCALE_STEP + 0.5)
      scr:text(wiz.surfaceName(item.surface) .. "  " .. string.format(T.progress, fi, #fineList),
        T.fineIntro .. " " .. string.format(T.fine, item.direction.name, pct),
        passNote or (config[field] >= most and T.sideLimit or nil))
      scr:picture(art.layout(wiz.surfaces(), axis(), item.direction.flip))
      return stepButtons(nudgeScale, {
        {text = T.next, primary = true, small = true, press = function()
          if fi < #fineList then fi = fi + 1 else screen = "axis" end
          wiz.rebuild()
        end},
      })
    end

    scr:text(T.doneTitle, T.done)
    return scr:buttons({
      {text = T.again, press = function()
        forcePassthrough()
        ai, screen = 1, "axis"
        wiz.rebuild()
      end},
      {text = T.saveNext, primary = true, press = function() wiz.finishStep() end},
    })
  end

  function self.paint() scr:paint() end

  local lastCanMove = nil
  function self.wakeup()
    local canMove = wiz.canMove()
    if canMove ~= lastCanMove then
      lastCanMove = canMove
      if canMove and (screen == "axis" or screen == "fine") then forcePassthrough() end
      wiz.rebuild()
    end
  end

  function self.released() scr:refresh() end

  return self
end

return {new = new}
