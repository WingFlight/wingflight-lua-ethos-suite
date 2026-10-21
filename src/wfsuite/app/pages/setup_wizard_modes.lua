-- Setup Wizard step: Mode switches. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepModes.svelte. One screen
-- per mode the flight controller offers, ARM first: press Assign, then flick
-- the switch to the position that should turn the mode on. The AUX channel
-- that moves more than MOVE_US from where it was is the switch; once it has
-- settled, the range is centred where it landed
-- (lib/setup_wizard_controls.lua rangeForSwitch()) and written to the mode's
-- slot, or the first free one (MSP_SET_MODE_RANGE). Only ARM is required.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local ui = requireModule("app/setup_wizard_ui.lua")
-- Freed when the step closes (app/setup_wizard_ui.lua's notLoaded()).
local OWNED = ui.notLoaded({"wfsuite.lib.setup_wizard_controls", "wfsuite.lib.msp_modes"})
local controls = requireModule("lib/setup_wizard_controls.lua")
local modes = requireModule("lib/msp_modes.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.mod_title)@",
  intro = "@i18n(app.modules.setup_wizard.mod_intro)@",
  required = "@i18n(app.modules.setup_wizard.mod_required)@",
  optional = "@i18n(app.modules.setup_wizard.mod_optional)@",
  assigned = "@i18n(app.modules.setup_wizard.mod_assigned_fmt)@",
  notAssigned = "@i18n(app.modules.setup_wizard.mod_not_assigned)@",
  onNow = "@i18n(app.modules.setup_wizard.mod_on_now)@",
  off = "@i18n(app.modules.setup_wizard.mod_off)@",
  armMissing = "@i18n(app.modules.setup_wizard.mod_arm_missing)@",
  armOn = "@i18n(app.modules.setup_wizard.mod_arm_on)@",
  flick = "@i18n(app.modules.setup_wizard.mod_flick)@",
  noSlot = "@i18n(app.modules.setup_wizard.mod_no_slot)@",
  timedOut = "@i18n(app.modules.setup_wizard.tg_timed_out)@",
  assign = "@i18n(app.modules.setup_wizard.mod_assign)@",
  change = "@i18n(app.modules.setup_wizard.mod_change)@",
  remove = "@i18n(app.modules.setup_wizard.mod_remove)@",
  doneTitle = "@i18n(app.modules.setup_wizard.mod_done_title)@",
  progress = "@i18n(app.modules.setup_wizard.progress_fmt)@",
  start = "@i18n(app.modules.setup_wizard.btn_start)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
}

-- Permanent box ids (msp/msp_box.c) and the names the FC reports for them,
-- before and after the firmware#182 rename.
local MODES = {
  {id = 0, names = {"ARM"}, required = true, help = "@i18n(app.modules.setup_wizard.mod_help_arm)@"},
  {id = 59, names = {"MANUAL", "GYRO OFF"}, help = "@i18n(app.modules.setup_wizard.mod_help_manual)@"},
  {id = 6, names = {"ATT HOLD"}, help = "@i18n(app.modules.setup_wizard.mod_help_att_hold)@"},
  {id = 47, names = {"TRAINER"}, help = "@i18n(app.modules.setup_wizard.mod_help_trainer)@"},
  {id = 60, names = {"AUTO TRIM"}, help = "@i18n(app.modules.setup_wizard.mod_help_auto_trim)@"},
  {id = 12, names = {"PASSTHROUGH", "SETUP"}, help = "@i18n(app.modules.setup_wizard.mod_help_passthrough)@"},
}

local AUX_OFFSET = 4
local MOVE_US = 300
local SETTLE_SECONDS = 0.4
local LISTEN_SECONDS = 15
local EMPTY_RANGE = {start = 1500, ["end"] = 1500}

local function new(wiz)
  local self = {liveRc = "rc"}
  local scr = ui.new(wiz)

  local offered = nil          -- MODES the FC has, each with .name
  local ranges, extras = nil, nil
  local screen = "intro"
  local mi = 1
  local note = nil
  local listening = nil        -- {baseline =, untilAt =, best =, settleAt =}

  wiz.fetch({
    names = function(ok, err) return modes.buildBoxNamesReadMessage(ok, err) end,
    ranges = function(ok, err) return modes.buildModeRangesReadMessage(ok, err) end,
    extras = function(ok, err) return modes.buildModeRangesExtraReadMessage(ok, err) end,
  }, function(results)
    local names = results.names or {}
    offered = {}
    for _, m in ipairs(MODES) do
      for _, n in ipairs(m.names) do
        for _, have in ipairs(names) do
          if have == n then m.name = n end
        end
      end
      if m.name then offered[#offered + 1] = m end
    end
    ranges = results.ranges or {}
    extras = results.extras or {}
    wiz.rebuild()
  end)

  local function go(name, n)
    screen, note = name, n
    wiz.rebuild()
  end

  local function rangeIndex(mode)
    for i, r in ipairs(ranges) do
      if r.id == mode.id and r.range.start < r.range["end"] then return i end
    end
    return nil
  end

  local function auxValue(aux) return wiz.rc[AUX_OFFSET + aux + 1] end

  local function inRange(r)
    local v = r and auxValue(r.auxChannelIndex)
    return v ~= nil and v >= r.range.start and v <= r.range["end"]
  end

  local function writeSlot(index, id, aux, range)
    local extra = extras[index] or {id = id, modeLogic = 0, linkedTo = 0}
    wiz.change("mode_" .. index, {range = ranges[index], extra = extra}, function(o)
      bus.publish("msp.request", modes.buildSetModeRangeMessage(index, o.range, o.extra))
    end)
    ranges[index] = {id = id, auxChannelIndex = aux, range = range}
    extras[index] = {id = id, modeLogic = 0, linkedTo = 0}
    bus.publish("msp.request", modes.buildSetModeRangeMessage(index, ranges[index], extras[index]))
  end

  local function save(mode, aux, from, to)
    local index = rangeIndex(mode)
    if not index then
      for i, r in ipairs(ranges) do
        if not (r.range.start < r.range["end"]) then index = i; break end
      end
    end
    if not index then return false end
    writeSlot(index, mode.id, aux, controls.rangeForSwitch(from, to))
    return true
  end

  local function remove(mode)
    local index = rangeIndex(mode)
    if index then writeSlot(index, 0, 0, {start = EMPTY_RANGE.start, ["end"] = EMPTY_RANGE["end"]}) end
    wiz.rebuild()
  end

  local function auxValues()
    local out = {}
    for i = AUX_OFFSET + 1, #wiz.rc do out[#out + 1] = wiz.rc[i] end
    return out
  end

  local function statusOf(mode)
    local index = rangeIndex(mode)
    if not index then return T.notAssigned, false end
    local r = ranges[index]
    return string.format(T.assigned, r.auxChannelIndex + 1, r.range.start, r.range["end"]), inRange(r)
  end

  local function nextMode()
    if mi < #offered then mi = mi + 1; go("mode") else go("done") end
  end

  function self.build()
    scr:begin()
    if not offered then
      scr:text(T.title, "@i18n(app.msg_loading)@")
      return nil
    end

    if screen == "intro" then
      scr:text(T.title, T.intro)
      return scr:row(nil, {
        {text = T.start, primary = true, press = function() mi = 1; go(#offered > 0 and "mode" or "done") end},
      })

    elseif screen == "mode" then
      local m = offered[mi]
      local text, on = statusOf(m)
      local accent = note
      if m.id == 0 and not rangeIndex(m) then accent = accent or T.armMissing end
      if m.id == 0 and on then accent = T.armOn end
      scr:text(m.name, m.help, accent, string.format(T.progress, mi, #offered))
      scr:rows({{m.required and T.required or T.optional, text}, {"", on and T.onNow or T.off, on}})
      local assigned = rangeIndex(m) ~= nil
      -- Next goes on to the next mode; once this one has a switch, the focus
      -- is on it.
      return scr:row(function()
        if mi > 1 then mi = mi - 1; go("mode") else go("intro") end
      end, {
        {text = T.remove, small = true, disabled = not assigned, press = function() remove(m) end},
        {text = assigned and T.change or T.assign, primary = not assigned, press = function()
          listening = {baseline = auxValues(), untilAt = os.clock() + LISTEN_SECONDS}
          go("listen")
        end},
      }, {text = T.next, press = nextMode})

    elseif screen == "listen" then
      scr:text(offered[mi].name, T.flick, nil, true)
      -- Back cancels the listening.
      return scr:row(function() listening = nil; go("mode") end, nil, false)
    end

    local rows = {}
    for _, m in ipairs(offered) do
      local text = statusOf(m)
      rows[#rows + 1] = {m.name, text, m.required and not rangeIndex(m)}
    end
    local armMissing = offered[1] and offered[1].id == 0 and not rangeIndex(offered[1])
    scr:text(T.doneTitle, nil, armMissing and T.armMissing or nil)
    scr:rows(rows)
    return scr:row(function()
      mi = math.max(1, #offered)
      go(#offered > 0 and "mode" or "intro")
    end)
  end

  function self.paint() scr:paint() end

  local lastOn = nil
  function self.wakeup(now)
    if screen == "mode" then
      local _, on = statusOf(offered[mi])
      if on ~= lastOn then lastOn = on; wiz.rebuild() end
      return
    end
    local l = listening
    if screen ~= "listen" or not l then return end
    if now > l.untilAt then
      listening = nil
      go("mode", T.timedOut)
      return
    end
    local values = auxValues()
    if not l.best then
      local best, bestMove = nil, MOVE_US
      for aux, v in ipairs(values) do
        local base = l.baseline[aux] or v
        if math.abs(v - base) > bestMove then best, bestMove = aux - 1, math.abs(v - base) end
      end
      if best then l.best, l.settleAt = best, now + SETTLE_SECONDS end
      return
    end
    if now < l.settleAt then return end
    local from, to = l.baseline[l.best + 1], values[l.best + 1]
    listening = nil
    if from and to and math.abs(to - from) > MOVE_US then
      go("mode", (not save(offered[mi], l.best, from, to)) and T.noSlot or nil)
    else
      go("mode")
    end
  end

  function self.released() scr:refresh() end

  return self
end

return {new = new, owned = OWNED}
