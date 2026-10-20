-- Setup Wizard step: Receiver (check only). Opened by app/pages/setup_wizard.lua.
--
-- The configurator's StepReceiver.svelte also sets up the receiver port and
-- protocol. The radio talks to the flight controller through the receiver,
-- so that part stays in the Configurator: if this page is open, the link
-- already works. What is left is the channel order and direction check:
--
--   check   four live bars (roll, pitch, yaw, throttle, read as the
--           configurator does: the raw receiver channel the RX map points at,
--           scaled by rc_center and rc_deflection). Both sticks bottom-left,
--           and every bar should go left. "Bars are wrong" offers Detect.
--   detect  move throttle, roll, pitch and yaw in turn; the channel that
--           clearly moves is that function's (lib/setup_wizard_controls.lua
--           movedChannel()), and the map is written (MSP_SET_RX_MAP).
--
-- A reversed bar is fixed on the radio, not here, as the configurator says.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local ui = requireModule("app/setup_wizard_ui.lua")
-- Freed when the step closes (app/setup_wizard_ui.lua's notLoaded()).
local OWNED = ui.notLoaded({"wfsuite.lib.setup_wizard_controls", "wfsuite.lib.msp_rx_map", "wfsuite.lib.msp_rc_config"})
local controls = requireModule("lib/setup_wizard_controls.lua")
local rxMap = requireModule("lib/msp_rx_map.lua")
local rcConfig = requireModule("lib/msp_rc_config.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.rx_title)@",
  check = "@i18n(app.modules.setup_wizard.rx_check)@",
  order = "@i18n(app.modules.setup_wizard.rx_order_fmt)@",
  reversed = "@i18n(app.modules.setup_wizard.rx_reversed)@",
  detectTitle = "@i18n(app.modules.setup_wizard.rx_detect_title)@",
  wrong = "@i18n(app.modules.setup_wizard.rx_wrong)@",
  restart = "@i18n(app.modules.setup_wizard.rx_restart)@",
}

local FUNCTIONS = {
  {name = "@i18n(app.modules.setup_wizard.axis_roll)@",
    move = "@i18n(app.modules.setup_wizard.rx_move_roll)@"},
  {name = "@i18n(app.modules.setup_wizard.axis_pitch)@",
    move = "@i18n(app.modules.setup_wizard.rx_move_pitch)@"},
  {name = "@i18n(app.modules.setup_wizard.axis_yaw)@",
    move = "@i18n(app.modules.setup_wizard.rx_move_yaw)@"},
  {name = "@i18n(app.modules.setup_wizard.axis_throttle)@",
    move = "@i18n(app.modules.setup_wizard.rx_move_throttle)@"},
}

-- The order the configurator asks for them in: throttle, then roll, pitch, yaw.
local DETECT_ORDER = {4, 1, 2, 3}

local function new(wiz)
  local self = {liveRc = "raw"}
  local scr = ui.new(wiz)

  local screen = "check"
  local map = nil
  local centre, span = 1500, 500
  local found, baseline, peaks = {}, {}, {}

  wiz.fetch({
    map = function(ok, err) return rxMap.buildReadMessage(ok, err) end,
    rc = function(ok, err) return rcConfig.buildReadMessage(ok, err) end,
  }, function(results)
    map = results.map and rxMap.toList(results.map) or {0, 1, 2, 3, 4, 5, 6, 7}
    if results.rc then
      centre = results.rc.rc_center or centre
      span = results.rc.rc_deflection or span
    end
    wiz.rebuild()
  end)

  -- -1..1 for function i (1 = roll ... 4 = throttle), or nil when unknown.
  local function reading(i)
    local raw = map and wiz.rcRaw[(map[i] or 0) + 1]
    if not raw or raw <= 0 then return nil end
    local f = (raw - centre) / span
    if f < -1 then f = -1 elseif f > 1 then f = 1 end
    return f
  end

  local function startDetect()
    found = {}
    screen = "detect"
    for i = 1, #wiz.rcRaw do baseline[i] = wiz.rcRaw[i]; peaks[i] = 0 end
    for i = #wiz.rcRaw + 1, #baseline do baseline[i], peaks[i] = nil, nil end
    wiz.rebuild()
  end

  local function writeMap(newMap)
    wiz.change("rx_map", map, function(o)
      bus.publish("msp.request", rxMap.buildWriteMessage(o))
    end)
    map = newMap
    bus.publish("msp.request", rxMap.buildWriteMessage(map))
  end

  local function drawBars(x, y, w, h, colors)
    lcd.font(FONT_S)
    local _, th = lcd.getTextSize("Ag")
    local rowH = math.min(math.floor(h / 4), th + 10)
    local labelW = math.floor(w * 0.28)
    for i = 1, 4 do
      local ry = y + (i - 1) * rowH
      lcd.color(colors.text)
      lcd.drawText(x, ry + math.floor((rowH - th) / 2), FUNCTIONS[i].name, LEFT)
      local f = reading(i)
      ui.gauge(x + labelW, ry + 2, w - labelW - 8, rowH - 6, f and (f + 1) / 2 or nil, colors, 0.48, 0.52)
    end
  end

  function self.build()
    scr:begin()
    if not map then
      scr:text(T.title, "@i18n(app.msg_loading)@")
      return nil
    end
    if screen == "check" then
      scr:text(T.title, T.check .. " " .. string.format(T.order, controls.orderLabel(map)), T.reversed)
      scr:draw(drawBars)
      -- Next when the bars follow the sticks; Detect when they don't.
      return scr:row(nil, {{text = T.wrong, press = startDetect}})
    end
    local fn = FUNCTIONS[DETECT_ORDER[#found + 1]]
    scr:text(T.detectTitle, fn.move)
    scr:draw(drawBars)
    -- Back cancels; the order is written once every stick has moved.
    return scr:row(function() screen = "check"; wiz.rebuild() end,
      {{text = T.restart, primary = true, press = startDetect}}, false)
  end

  function self.paint() scr:paint() end

  local lastShown = {}

  function self.wakeup()
    if screen == "detect" then
      local raw = wiz.rcRaw
      for i = 1, #raw do
        if baseline[i] == nil then baseline[i], peaks[i] = raw[i], 0 end
        local move = math.abs(raw[i] - baseline[i])
        if move > (peaks[i] or 0) then peaks[i] = move end
      end
      local channel = controls.movedChannel(peaks, found)
      if channel >= 0 then
        found[#found + 1] = channel
        -- The next stick starts from where everything is now.
        for i = 1, #raw do baseline[i], peaks[i] = raw[i], 0 end
        if #found == #DETECT_ORDER then
          local byFunction = {}
          for k, fnIndex in ipairs(DETECT_ORDER) do byFunction[fnIndex] = found[k] end
          writeMap(controls.mapFromDetected(byFunction, #map))
          screen = "check"
        end
        wiz.rebuild()
        return
      end
    end
    -- Redraw the bars when a reading moves.
    for i = 1, 4 do
      local f = reading(i)
      if f ~= lastShown[i] then
        lastShown[i] = f
        wiz.invalidate()
      end
    end
  end

  function self.released() scr:refresh() end

  return self
end

return {new = new, owned = OWNED}
