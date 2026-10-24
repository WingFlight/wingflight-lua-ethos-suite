-- Setup Wizard step: Finish. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepFinish.svelte: what the
-- wizard set (model type, control surfaces, ESC protocol, throws, flying
-- style, the ARM switch), the checks to do before the first flight, and
-- Save and finish (the footer's way forward on the last step), which saves
-- and leaves the wizard.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")
local art = requireModule("app/setup_wizard_art.lua")
-- Freed when the step closes (app/setup_wizard_ui.lua's notLoaded()).
local OWNED = ui.notLoaded({"wfsuite.lib.setup_wizard_styles", "wfsuite.lib.msp_motor_config", "wfsuite.lib.msp_rc_tuning", "wfsuite.lib.msp_pid_profile", "wfsuite.lib.msp_modes"})
local styles = requireModule("lib/setup_wizard_styles.lua")
local motorConfig = requireModule("lib/msp_motor_config.lua")
local rcTuning = requireModule("lib/msp_rc_tuning.lua")
local pidProfile = requireModule("lib/msp_pid_profile.lua")
local modes = requireModule("lib/msp_modes.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.fin_title)@",
  intro = "@i18n(app.modules.setup_wizard.fin_intro)@",
  before = "@i18n(app.modules.setup_wizard.fin_before)@",
  model = "@i18n(app.modules.setup_wizard.fin_model)@",
  surfaces = "@i18n(app.modules.setup_wizard.fin_surfaces)@",
  esc = "@i18n(app.modules.setup_wizard.fin_esc)@",
  throws = "@i18n(app.modules.setup_wizard.fin_throws)@",
  style = "@i18n(app.modules.setup_wizard.fin_style)@",
  arm = "@i18n(app.modules.setup_wizard.fin_arm)@",
  armMissing = "@i18n(app.modules.setup_wizard.mod_arm_missing)@",
  yes = "@i18n(app.modules.setup_wizard.btn_yes)@",
  no = "@i18n(app.modules.setup_wizard.btn_no)@",
  custom = "@i18n(app.modules.setup_wizard.sty_custom)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
}

local TYPE_NAMES = {
  [0] = "@i18n(app.modules.setup_wizard.air_type_regular)@",
  [1] = "@i18n(app.modules.setup_wizard.air_type_flying_wing)@",
  [2] = "@i18n(app.modules.setup_wizard.air_type_vtail)@",
  [3] = "@i18n(app.modules.setup_wizard.air_type_delta)@",
  [4] = "@i18n(app.modules.setup_wizard.air_type_trainer)@",
  [5] = "@i18n(app.modules.setup_wizard.air_type_custom)@",
}
local ESC_NAMES = {
  [0] = "@i18n(app.modules.setup_wizard.mot_pwm)@",
  [6] = "@i18n(app.modules.setup_wizard.mot_dshot300)@",
  [7] = "@i18n(app.modules.setup_wizard.mot_dshot600)@",
  [11] = "@i18n(app.modules.setup_wizard.mot_none)@",
}
local STYLE_NAMES = {
  trainer = "@i18n(app.modules.setup_wizard.sty_trainer)@",
  sport = "@i18n(app.modules.setup_wizard.sty_sport)@",
  ["3d"] = "@i18n(app.modules.setup_wizard.sty_3d)@",
}
local AXES = {
  {key = "roll", name = "@i18n(app.modules.setup_wizard.axis_roll)@"},
  {key = "pitch", name = "@i18n(app.modules.setup_wizard.axis_pitch)@"},
  {key = "yaw", name = "@i18n(app.modules.setup_wizard.axis_yaw)@"},
}

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)
  local data = nil
  local screen = "summary"

  wiz.fetch({
    motor = function(ok, err) return motorConfig.buildReadMessage(ok, err) end,
    rc = function(ok, err) return rcTuning.buildReadMessage(ok, err) end,
    pid = function(ok, err) return pidProfile.buildReadMessage(ok, err) end,
    ranges = function(ok, err) return modes.buildModeRangesReadMessage(ok, err) end,
  }, function(results)
    data = results
    wiz.rebuild()
  end)

  function self.build()
    scr:begin()
    if not data then
      scr:text(T.title, "@i18n(app.msg_loading)@")
      return nil
    end
    local cfg = wiz.mixConfig()
    local surfaceNames = {}
    for _, s in ipairs(wiz.surfaces()) do
      surfaceNames[#surfaceNames + 1] = "S" .. (s.servo + 1) .. " " .. wiz.kindName(s.kind)
    end
    local throws = {}
    for _, a in ipairs(AXES) do
      for _, s in ipairs(wiz.surfaces()) do
        if s.axes[a.key] then throws[#throws + 1] = a.name .. " " .. wiz.axisGainPercent(a.key) .. "%"; break end
      end
    end
    local style = (data.rc and data.pid) and styles.matchingStyle(data.rc, data.pid) or nil
    local armed = false
    for _, r in ipairs(data.ranges or {}) do
      if r.id == 0 and r.range.start < r.range["end"] then armed = true end
    end
    local protocol = data.motor and data.motor.motor_pwm_protocol
    if screen == "before" then
      -- The model with a big tick: set up, ready for the checks.
      scr:text(T.title, T.before)
      local layout = art.layout(wiz.surfaces(), nil)
      scr:draw(function(x, y, w, h, colors) art.done(layout, x, y, w, h, colors) end, nil, true)
      -- The last step: the default way forward is Save and finish.
      return scr:row(function() screen = "summary"; wiz.rebuild() end)
    end
    scr:text(T.title, T.intro, (not armed) and T.armMissing or nil)
    scr:rows({
      {T.model, TYPE_NAMES[cfg and cfg.model_type or 0] or "-"},
      {T.surfaces, table.concat(surfaceNames, ", ")},
      {T.esc, ESC_NAMES[protocol] or tostring(protocol or "-")},
      {T.throws, table.concat(throws, ", ")},
      {T.style, style and STYLE_NAMES[style.key] or T.custom},
      {T.arm, armed and T.yes or T.no, not armed},
    })
    return scr:row(nil, nil, {text = T.next, press = function() screen = "before"; wiz.rebuild() end})
  end

  function self.paint() scr:paint() end
  function self.released() scr:refresh() end

  return self
end

return {new = new, owned = OWNED}
