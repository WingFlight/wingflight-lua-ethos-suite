-- Setup Wizard step: Flying style. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepStyle.svelte: Trainer,
-- Sport or 3D, each a set of rates (deg/s at full stick, expo) and I-term
-- relax for roll, pitch and yaw (lib/setup_wizard_styles.lua). Applied to the
-- current rate and PID profiles: MSP_SET_RC_TUNING and MSP_SET_PID_PROFILE
-- with the whole records read back, only the style's fields changed.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local ui = requireModule("app/setup_wizard_ui.lua")
local styles = requireModule("lib/setup_wizard_styles.lua")
local rcTuning = requireModule("lib/msp_rc_tuning.lua")
local pidProfile = requireModule("lib/msp_pid_profile.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.sty_title)@",
  intro = "@i18n(app.modules.setup_wizard.sty_intro)@",
  now = "@i18n(app.modules.setup_wizard.sty_now_fmt)@",
  custom = "@i18n(app.modules.setup_wizard.sty_custom)@",
  rates = "@i18n(app.modules.setup_wizard.sty_rates_fmt)@",
  more = "@i18n(app.modules.setup_wizard.sty_more)@",
  saveNext = "@i18n(app.modules.setup_wizard.dir_save_next)@",
}

local NAMES = {
  trainer = "@i18n(app.modules.setup_wizard.sty_trainer)@",
  sport = "@i18n(app.modules.setup_wizard.sty_sport)@",
  ["3d"] = "@i18n(app.modules.setup_wizard.sty_3d)@",
}

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)
  local rc, pid = nil, nil

  wiz.fetch({
    rc = function(ok, err) return rcTuning.buildReadMessage(ok, err) end,
    pid = function(ok, err) return pidProfile.buildReadMessage(ok, err) end,
  }, function(results)
    rc, pid = results.rc, results.pid
    wiz.rebuild()
  end)

  local function apply(style)
    wiz.change("rc_tuning", rc, function(o) bus.publish("msp.request", rcTuning.buildWriteMessage(o)) end)
    wiz.change("pid_profile", pid, function(o) bus.publish("msp.request", pidProfile.buildWriteMessage(o)) end)
    rc, pid = copy(rc), copy(pid)
    styles.applyStyle(style, rc, pid)
    bus.publish("msp.request", rcTuning.buildWriteMessage(rc))
    bus.publish("msp.request", pidProfile.buildWriteMessage(pid))
    wiz.rebuild()
  end

  function self.build()
    scr:begin()
    if not (rc and pid) then
      scr:text(T.title, "@i18n(app.msg_loading)@")
      return nil
    end
    local current = styles.matchingStyle(rc, pid)
    scr:text(T.title, T.intro .. " " .. T.more,
      string.format(T.now, current and NAMES[current.key] or T.custom))
    local rows = {}
    for _, s in ipairs(styles.STYLES) do
      rows[#rows + 1] = {NAMES[s.key],
        string.format(T.rates, s.rate.roll, s.rate.pitch, s.rate.yaw, s.expo), current == s}
    end
    scr:rows(rows)
    local specs = {}
    for _, s in ipairs(styles.STYLES) do
      specs[#specs + 1] = {text = NAMES[s.key], small = true, press = function() apply(s) end}
    end
    specs[#specs + 1] = {text = T.saveNext, small = true, primary = true, weight = 1.4,
      press = function() wiz.finishStep() end}
    return scr:buttons(specs)
  end

  function self.paint() scr:paint() end
  function self.released() scr:refresh() end

  return self
end

return {new = new}
