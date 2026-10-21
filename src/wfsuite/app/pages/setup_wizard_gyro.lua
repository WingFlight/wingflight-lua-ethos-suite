-- Setup Wizard step: Gyro direction. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepGyro.svelte. No
-- overrides: the stabilizer drives the surfaces (the PID runs while disarmed
-- too). The wizard forces ANGLE mode on top of the setup state, so the
-- reaction holds while the model is tilted by hand. One screen per axis the
-- mix uses: move the model as the text says, and the surfaces should push
-- back the way the picture's arrows show -- the opposite of the Direction
-- step's pictures for the same axis.
--
-- A wrong answer means the board orientation doesn't match how the board is
-- mounted (the Direction step already set the servo directions): go back to
-- the Sensors step, and don't reverse servos for it.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")
local art = requireModule("app/setup_wizard_art.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.gyr_title)@",
  intro = "@i18n(app.modules.setup_wizard.gyr_intro)@",
  noAngle = "@i18n(app.modules.setup_wizard.gyr_no_angle)@",
  q = "@i18n(app.modules.setup_wizard.dir_q_match)@",
  wrong = "@i18n(app.modules.setup_wizard.gyr_wrong)@",
  doneTitle = "@i18n(app.modules.setup_wizard.gyr_done_title)@",
  done = "@i18n(app.modules.setup_wizard.gyr_done)@",
  progress = "@i18n(app.modules.setup_wizard.progress_fmt)@",
  start = "@i18n(app.modules.setup_wizard.btn_start)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
  like = "@i18n(app.modules.setup_wizard.dir_like)@",
  unlike = "@i18n(app.modules.setup_wizard.dir_unlike)@",
  again = "@i18n(app.modules.setup_wizard.btn_again)@",
  fromBehind = "@i18n(app.modules.setup_wizard.dir_from_behind)@",
}

local CHECKS = {
  {axis = "roll", title = "@i18n(app.modules.setup_wizard.axis_roll)@",
    text = "@i18n(app.modules.setup_wizard.gyr_roll)@"},
  {axis = "pitch", title = "@i18n(app.modules.setup_wizard.axis_pitch)@",
    text = "@i18n(app.modules.setup_wizard.gyr_pitch)@"},
  {axis = "yaw", title = "@i18n(app.modules.setup_wizard.axis_yaw)@",
    text = "@i18n(app.modules.setup_wizard.gyr_yaw)@"},
}

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)
  local checks = {}
  for _, c in ipairs(CHECKS) do
    for _, s in ipairs(wiz.surfaces()) do
      if s.axes[c.axis] then checks[#checks + 1] = c; break end
    end
  end

  local screen = "intro"
  local ci = 1

  local function forceAngle()
    if wiz.forcedMode() ~= wiz.BOX_ANGLE then wiz.forceMode(wiz.BOX_ANGLE) end
  end

  local function go(name)
    screen = name
    wiz.rebuild()
  end

  local function nextCheck()
    if ci < #checks then ci = ci + 1; go("check") else wiz.releaseMode(); go("done") end
  end

  function self.build()
    scr:begin()
    if screen == "intro" then
      scr:text(T.title, T.intro)
      scr:picture(art.layout(wiz.surfaces(), nil))
      return scr:row(nil, {
        {text = T.start, primary = true, needsMotion = true, press = function()
          forceAngle()
          ci = 1
          go(#checks > 0 and "check" or "done")
        end},
      })
    elseif screen == "check" then
      local c = checks[ci]
      scr:text(c.title, c.text .. " " .. T.q, wiz.forcedMode() ~= wiz.BOX_ANGLE and T.noAngle or nil,
        string.format(T.progress, ci, #checks))
      scr:picture(art.layout(wiz.surfaces(), c.axis, true), T.fromBehind)
      return scr:row(function()
        if ci > 1 then ci = ci - 1; go("check") else wiz.releaseMode(); go("intro") end
      end, {
        {text = T.unlike, press = function() go("wrong") end},
        {text = T.like, primary = true, press = nextCheck},
      }, false)
    elseif screen == "wrong" then
      -- The fix is in the Sensors step, which the step list (header) opens.
      scr:text(checks[ci].title, T.wrong, nil, true)
      return scr:row(function() go("check") end, nil, {text = T.next, press = nextCheck})
    end
    scr:text(T.doneTitle, T.done)
    return scr:row(function()
      forceAngle()
      ci = math.max(1, #checks)
      go(#checks > 0 and "check" or "intro")
    end, {{text = T.again, press = function() forceAngle(); ci = 1; go("check") end}})
  end

  function self.paint() scr:paint() end

  local lastCanMove = nil
  function self.wakeup()
    local canMove = wiz.canMove()
    if canMove ~= lastCanMove then
      lastCanMove = canMove
      if canMove and screen == "check" then forceAngle() end
      scr:refresh()
    end
  end

  function self.released() scr:refresh() end

  return self
end

return {new = new}
