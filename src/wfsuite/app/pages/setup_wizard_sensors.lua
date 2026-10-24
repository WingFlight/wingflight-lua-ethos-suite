-- Setup Wizard step: Sensors and level. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepSensors.svelte, which
-- runs the Configuration tab's accelerometer calibration, automatic board
-- orientation (AutoAlignWizard.svelte) and automatic level
-- (MountTrimAutoWizard.svelte). One screen each, in that order:
--
--   intro   the tail-wheel note; Start, or Next to leave the step as it is
--   acc     calibrate the accelerometer (MSP_ACC_CALIBRATION, then wait for
--           the FC to clear ARMING_DISABLED_CALIBRATING, lib/acc_calibration_wait.lua)
--   align   MSP2_WING_BOARD_AUTO_ALIGN: flat, Start, lift the tail 20 deg; the
--           result is written as the board alignment. A side view of the
--           plane (app/plane3d.lua) shows the tail lift.
--   check   the live attitude (MSP_ATTITUDE) on the 3D plane, seen from
--           behind: tilting the model must move the picture the same way.
--           The firmware applies an auto-align result at once, so this
--           shows the new orientation without a restart.
--   level   MSP2_WING_BOARD_MOUNT_TRIM_AUTO: hold the flying attitude; the
--           result is written as the mount trim
--   done    board alignment only applies after a restart, so Save and
--           restart when either changed
--
-- A board without an accelerometer (sensor_status bit 0, as the
-- configurator's have_sensor()) gets a note and Next only.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local ui = requireModule("app/setup_wizard_ui.lua")
-- Freed when the step closes (app/setup_wizard_ui.lua's notLoaded()).
local OWNED = ui.notLoaded({"wfsuite.lib.msp_acc_calibration", "wfsuite.lib.acc_calibration_wait", "wfsuite.lib.msp_board_auto_align", "wfsuite.lib.msp_board_alignment_config", "wfsuite.lib.msp_board_mount_trim", "wfsuite.lib.msp_attitude"})
local status = requireModule("lib/msp_status.lua")
local accCalibration = requireModule("lib/msp_acc_calibration.lua")
local calibrationWait = requireModule("lib/acc_calibration_wait.lua")
local autoAlign = requireModule("lib/msp_board_auto_align.lua")
local boardAlignment = requireModule("lib/msp_board_alignment_config.lua")
local mountTrim = requireModule("lib/msp_board_mount_trim.lua")
local attitude = requireModule("lib/msp_attitude.lua")
local plane3d = requireModule("app/plane3d.lua")
local art = requireModule("app/setup_wizard_art.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.sen_title)@",
  intro = "@i18n(app.modules.setup_wizard.sen_intro)@",
  tail = "@i18n(app.modules.setup_wizard.sen_tail)@",
  noAcc = "@i18n(app.modules.setup_wizard.sen_no_acc)@",
  accTitle = "@i18n(app.modules.setup_wizard.sen_acc_title)@",
  accText = "@i18n(app.modules.setup_wizard.sen_acc_text)@",
  accBusy = "@i18n(app.modules.setup_wizard.sen_acc_busy)@",
  accDone = "@i18n(app.modules.setup_wizard.sen_acc_done)@",
  accFailed = "@i18n(app.modules.setup_wizard.sen_acc_failed)@",
  alignTitle = "@i18n(app.modules.setup_wizard.sen_align_title)@",
  alignText = "@i18n(app.modules.setup_wizard.sen_align_text)@",
  alignLift = "@i18n(app.modules.setup_wizard.sen_align_lift)@",
  alignDone = "@i18n(app.modules.setup_wizard.sen_align_done_fmt)@",
  checkTitle = "@i18n(app.modules.setup_wizard.sen_check_title)@",
  checkText = "@i18n(app.modules.setup_wizard.sen_check_text)@",
  roll = "@i18n(app.modules.pids.roll)@",
  pitch = "@i18n(app.modules.pids.pitch)@",
  levelTitle = "@i18n(app.modules.setup_wizard.sen_level_title)@",
  progress = "@i18n(app.modules.setup_wizard.progress_fmt)@",
  levelText = "@i18n(app.modules.setup_wizard.sen_level_text)@",
  levelBusy = "@i18n(app.modules.setup_wizard.sen_level_busy)@",
  levelDone = "@i18n(app.modules.setup_wizard.sen_level_done_fmt)@",
  armed = "@i18n(app.modules.setup_wizard.sen_rejected_armed)@",
  uncalibrated = "@i18n(app.modules.setup_wizard.sen_rejected_uncal)@",
  timeout = "@i18n(app.modules.setup_wizard.sen_timeout)@",
  noMatch = "@i18n(app.modules.setup_wizard.sen_no_match)@",
  outOfRange = "@i18n(app.modules.setup_wizard.sen_out_of_range)@",
  unsupported = "@i18n(app.modules.setup_wizard.sen_unsupported)@",
  doneTitle = "@i18n(app.modules.setup_wizard.sen_done_title)@",
  doneRestart = "@i18n(app.modules.setup_wizard.sen_done_restart)@",
  doneSame = "@i18n(app.modules.setup_wizard.sen_done_same)@",
  start = "@i18n(app.modules.setup_wizard.btn_start)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
  again = "@i18n(app.modules.setup_wizard.btn_again)@",
  calibrate = "@i18n(app.modules.setup_wizard.sen_calibrate)@",
  saveRestart = "@i18n(app.modules.setup_wizard.btn_save_restart)@",
}

-- Auto align and level: poll every quarter second while the FC works.
local AUTO_POLL = 0.25
-- Live attitude on the check screen, as the Alignment page polls it: the
-- MSP queue is shared with the background task, and a request that gets no
-- answer is given up after ATTITUDE_TIMEOUT (msp_attitude retries for ~1.6s).
local ATTITUDE_POLL = 0.3
local ATTITUDE_TIMEOUT = 3.0
-- The orientation screen's view: from behind and to the side, nose to the
-- left, and the tail lift it asks for.
local SIDE_YAW = -65
local TAIL_LIFT = 20
-- The pictures tilt only a little: a little bigger
-- than plane3d's fit-any-attitude size (it clips what overflows).
local LIFT_ZOOM = 1.3
local LIVE_ZOOM = 1.25
local PARTS = 4
local DEGREES = "%.1f°"

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)

  local screen = "intro"
  local hasAcc = nil
  local alignment, trim = nil, nil
  local note, noteAccent = nil, nil   -- result line for the current screen
  local busy = false                  -- a calibration or auto run is going
  local accWait = nil
  local autoKind = nil                -- "align" | "level" while polling
  local autoReply = nil               -- latest decoded auto reply
  local nextPollAt = 0
  local changed = false
  -- Live attitude (check screen).
  local live = {roll = 0, pitch = 0}
  local liveRows = {{T.roll, string.format(DEGREES, 0)}, {T.pitch, string.format(DEGREES, 0)}}
  local attitudePending, attitudeAt, nextAttitudeAt = false, 0, 0
  local attitudeMoved = false   -- repaint from wakeup: replies arrive in the background task

  wiz.fetch({
    status = function(ok, err) return status.buildReadMessage(ok, err) end,
    alignment = function(ok, err) return boardAlignment.buildReadMessage(ok, err) end,
    trim = function(ok, err) return mountTrim.buildReadMessage(ok, err) end,
  }, function(results)
    local flags = results.status and tonumber(results.status.sensor_status) or nil
    hasAcc = flags == nil or (math.floor(flags) & 1) == 1
    alignment, trim = results.alignment, results.trim
    wiz.rebuild()
  end)

  local function go(name)
    screen, note, noteAccent, busy, autoKind, accWait = name, nil, nil, false, nil, nil
    attitudePending, nextAttitudeAt = false, 0
    wiz.rebuild()
  end

  -- This model's airframe (as the other steps' pictures), surfaces neutral.
  local airframe = art.airframe(wiz.surfaces())
  local function plane(x, y, w, h, roll, pitch, yaw, zoom)
    plane3d.setup(airframe)
    plane3d.pose(nil)
    plane3d.draw(x, y, w, h, roll, pitch, yaw, zoom)
  end

  -- The model level: the intro, the calibration and the level screens.
  local function drawLevel(x, y, w, h)
    plane(x, y, w, h, 0, 0, SIDE_YAW, LIFT_ZOOM)
  end

  -- The plane from the side, its tail lifted while auto align waits for it.
  local function drawLift(x, y, w, h)
    plane(x, y, w, h, 0, (autoKind == "align") and TAIL_LIFT or 0, SIDE_YAW, LIFT_ZOOM)
  end

  -- The plane from behind at the live attitude (the numbers are rows).
  local function drawLive(x, y, w, h)
    plane(x, y, w, h, live.roll, live.pitch, 0, LIVE_ZOOM)
  end

  local function onAttitude(values)
    attitudePending = false
    if screen ~= "check" then return end
    local roll = ((values and values.roll) or 0) / 10
    local pitch = ((values and values.pitch) or 0) / 10
    if roll ~= live.roll or pitch ~= live.pitch then
      live.roll, live.pitch = roll, pitch
      attitudeMoved = true
    end
  end

  local function onAttitudeError() attitudePending = false end

  local function startAcc()
    busy = true
    note = T.accBusy
    bus.publish("msp.request", accCalibration.buildWriteMessage(function()
      accWait = calibrationWait.new(os.clock())
    end, function()
      busy, note, noteAccent = false, nil, T.accFailed
    end))
    wiz.rebuild()
  end

  local function startAuto(kind)
    busy, autoKind, autoReply, nextPollAt = true, kind, nil, os.clock() + AUTO_POLL
    note, noteAccent = (kind == "align") and T.alignLift or T.levelBusy, nil
    local onData = function(data) autoReply = data end
    local onError = function() autoReply = {state = -1} end
    if kind == "align" then
      bus.publish("msp.request", autoAlign.buildStartMessage(onData, onError))
    else
      bus.publish("msp.request", mountTrim.buildAutoStartMessage(onData, onError))
    end
    wiz.rebuild()
  end

  local function writeAlignment(data)
    wiz.change("board_alignment", alignment, function(o)
      bus.publish("msp.request", boardAlignment.buildWriteMessage(o))
    end)
    alignment = {roll_degrees = data.roll_degrees, pitch_degrees = data.pitch_degrees, yaw_degrees = data.yaw_degrees}
    bus.publish("msp.request", boardAlignment.buildWriteMessage(alignment))
    changed = true
  end

  local function writeTrim(data)
    wiz.change("mount_trim", trim, function(o)
      bus.publish("msp.request", mountTrim.buildWriteMessage(o))
    end)
    trim = {roll_trim = data.roll_trim, pitch_trim = data.pitch_trim, yaw_trim = trim and trim.yaw_trim or 0}
    bus.publish("msp.request", mountTrim.buildWriteMessage(trim))
    changed = true
  end

  -- An auto reply, from wakeup.
  local function onAuto(reply)
    local s = reply.state
    if autoKind == "align" then
      local S = autoAlign.STATE
      if s == S.WAITING_FOR_TAIL_LIFT then return false end
      busy = false
      if s == S.SUCCESS then
        writeAlignment(reply)
        note = string.format(T.alignDone, reply.roll_degrees, reply.pitch_degrees, reply.yaw_degrees)
      elseif s == S.REJECTED_ARMED then noteAccent = T.armed
      elseif s == S.REJECTED_UNCALIBRATED then noteAccent = T.uncalibrated
      elseif s == S.TIMEOUT then noteAccent = T.timeout
      elseif s == S.NO_MATCH then noteAccent = T.noMatch
      elseif s == -1 then noteAccent = T.unsupported
      else return false end
    else
      local S = mountTrim.STATE
      if s == S.SAMPLING then return false end
      busy = false
      if s == S.SUCCESS then
        writeTrim(reply)
        note = string.format(T.levelDone, reply.roll_trim / 10, reply.pitch_trim / 10)
      elseif s == S.REJECTED_ARMED then noteAccent = T.armed
      elseif s == S.REJECTED_UNCALIBRATED then noteAccent = T.uncalibrated
      elseif s == S.TIMEOUT then noteAccent = T.timeout
      elseif s == S.OUT_OF_RANGE then noteAccent = T.outOfRange
      elseif s == -1 then noteAccent = T.unsupported
      else return false end
    end
    autoKind = nil
    return true
  end

  function self.build()
    scr:begin()
    if hasAcc == nil then
      scr:text(T.title, "@i18n(app.msg_loading)@")
      return nil
    end

    if screen == "intro" then
      scr:text(T.title, T.intro .. " " .. T.tail, (not hasAcc) and T.noAcc or nil)
      scr:draw(drawLevel, nil, true)
      return scr:row(nil, hasAcc and {{text = T.start, primary = true, press = function() go("acc") end}} or nil)

    elseif screen == "acc" then
      -- The step's three parts, one at a time: calibrate, orientation, level.
      scr:text(T.accTitle, T.accText, noteAccent or note, string.format(T.progress, 1, PARTS))
      scr:draw(drawLevel, nil, true)
      -- Once it has calibrated, the focus moves on to Next.
      local done = note ~= nil and not busy
      return scr:row(function() go("intro") end, {
        {text = done and T.again or T.calibrate, primary = not done, needsMotion = true, disabled = busy,
          press = startAcc},
      }, {text = T.next, disabled = busy, press = function() go("align") end})

    elseif screen == "check" then
      scr:text(T.checkTitle, T.checkText, nil, string.format(T.progress, 3, PARTS))
      scr:draw(drawLive, nil, true)
      scr:rows(liveRows)
      return scr:row(function() go("align") end, nil, {text = T.next, press = function() go("level") end})

    elseif screen == "align" or screen == "level" then
      local align = screen == "align"
      scr:text(align and T.alignTitle or T.levelTitle, align and T.alignText or T.levelText,
        noteAccent or note, string.format(T.progress, align and 2 or 4, PARTS))
      scr:draw(align and drawLift or drawLevel, nil, true)
      local done = note ~= nil and not busy
      return scr:row(function() go(align and "acc" or "check") end, {
        {text = done and T.again or T.start, primary = not done, needsMotion = true, disabled = busy,
          press = function() startAuto(screen) end},
      }, {text = T.next, disabled = busy, press = function() go(align and "check" or "done") end})

    else -- done
      scr:text(T.doneTitle, changed and T.doneRestart or T.doneSame)
      scr:draw(drawLevel, nil, true)
      return scr:row(function() go("level") end, nil,
        changed and {text = T.saveRestart, press = function() wiz.saveAndReboot() end} or nil)
    end
  end

  function self.paint() scr:paint() end

  function self.wakeup(now)
    if screen == "check" then
      if attitudeMoved then
        attitudeMoved = false
        scr:setRow(1, string.format(DEGREES, live.roll))
        scr:setRow(2, string.format(DEGREES, live.pitch))
        wiz.invalidate()
      end
      if attitudePending and now - attitudeAt > ATTITUDE_TIMEOUT then attitudePending = false end
      if not attitudePending and now >= nextAttitudeAt then
        attitudePending, attitudeAt, nextAttitudeAt = true, now, now + ATTITUDE_POLL
        bus.publish("msp.request", attitude.buildReadMessage(onAttitude, onAttitudeError))
      end
    end
    if accWait then
      if calibrationWait.shouldPoll(accWait, now) then
        local waiting = accWait
        bus.publish("msp.request", status.buildReadMessage(function(data)
          if accWait ~= waiting then return end
          local d = calibrationWait.onStatus(waiting, data.arming_disable_flags, os.clock())
          if d ~= "wait" then waiting.result = d end
        end, function()
          if accWait ~= waiting then return end
          local d = calibrationWait.onError(waiting, os.clock())
          if d ~= "wait" then waiting.result = d end
        end))
        accWait.nextPollAt = now + calibrationWait.POLL_INTERVAL
      end
      if accWait.result then
        busy = false
        note = (accWait.result == "done") and T.accDone or nil
        noteAccent = (accWait.result ~= "done") and T.accFailed or nil
        accWait = nil
        wiz.rebuild()
      end
    end
    if autoKind then
      if autoReply then
        local reply = autoReply
        autoReply = nil
        if onAuto(reply) then wiz.rebuild() return end
      end
      if now >= nextPollAt then
        nextPollAt = now + AUTO_POLL
        local onData = function(data) autoReply = data end
        if autoKind == "align" then
          bus.publish("msp.request", autoAlign.buildReadMessage(onData))
        else
          bus.publish("msp.request", mountTrim.buildAutoReadMessage(onData))
        end
      end
    end
  end

  function self.released() scr:refresh() end
  function self.leave() accWait, autoKind, attitudePending = nil, nil, false end

  return self
end

return {new = new, owned = OWNED}
