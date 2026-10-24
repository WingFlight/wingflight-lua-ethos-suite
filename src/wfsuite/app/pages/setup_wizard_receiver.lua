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

-- Which function each stick's axes carry, by the radio's stick mode
-- (system.getStickMode(), 1..4): {left stick, right stick}, each {x =, y =}
-- as FUNCTIONS indices (1 roll, 2 pitch, 3 yaw, 4 throttle).
local STICKS = {
  {{x = 3, y = 2}, {x = 1, y = 4}},   -- mode 1: rudder/elevator, aileron/throttle
  {{x = 3, y = 4}, {x = 1, y = 2}},   -- mode 2: rudder/throttle, aileron/elevator
  {{x = 1, y = 2}, {x = 3, y = 4}},   -- mode 3: aileron/elevator, rudder/throttle
  {{x = 1, y = 4}, {x = 3, y = 2}},   -- mode 4: aileron/throttle, rudder/elevator
}

-- A stick this far out (of 1) counts as in the corner.
local TARGET = 0.85
-- Room the bars need, in text lines.
local BARS_LINES = 6

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

  -- One bar per function, the target (full left) marked at its left end.
  local function drawBars(x, y, w, h, colors)
    lcd.font(FONT_S)
    local _, th = lcd.getTextSize("Ag")
    local rowH = math.min(math.floor(h / 4), th + 14)
    local labelW = 0
    for i = 1, 4 do labelW = math.max(labelW, (lcd.getTextSize(FUNCTIONS[i].name))) end
    labelW = labelW + 10
    for i = 1, 4 do
      local ry = y + (i - 1) * rowH
      local f = reading(i)
      local there = f and f <= -TARGET
      lcd.color(there and colors.active or colors.text)
      lcd.drawText(x, ry + math.floor((rowH - th) / 2), FUNCTIONS[i].name, LEFT)
      ui.gauge(x + labelW, ry + 3, w - labelW - 4, rowH - 6, f and (f + 1) / 2 or nil, colors, 0, (1 - TARGET) / 2)
    end
  end

  -- The two sticks as the radio's stick mode has them, each a square with
  -- the target corner (bottom left) marked and a dot where the stick is.
  local mode = (system and system.getStickMode and system.getStickMode()) or 2
  local sticks = STICKS[mode] or STICKS[2]
  local stickNames = {
    FUNCTIONS[sticks[1].x].name .. " / " .. FUNCTIONS[sticks[1].y].name,
    FUNCTIONS[sticks[2].x].name .. " / " .. FUNCTIONS[sticks[2].y].name,
  }
  local function drawSticks(x, y, w, h, colors)
    lcd.font(FONT_XS)
    local _, lh = lcd.getTextSize("Ag")
    local gap = math.max(8, math.floor(w * 0.06))
    local s = math.min(math.floor((w - gap) / 2) - 4, h - lh - 6)
    if s < 30 then return end
    local x0 = x + math.floor((w - (2 * s + gap)) / 2)
    local y0 = y + math.floor((h - s - lh - 4) / 2)
    local r = math.max(3, math.floor(s * 0.07))
    for k = 1, 2 do
      local gx = x0 + (k - 1) * (s + gap)
      local cx, cy = gx + math.floor(s / 2), y0 + math.floor(s / 2)
      lcd.color(colors.surface)
      lcd.drawRectangle(gx, y0, s, s)
      lcd.drawLine(cx, y0 + 4, cx, y0 + s - 4)
      lcd.drawLine(gx + 4, cy, gx + s - 4, cy)
      -- The corner to go to.
      local z = math.floor(s * (1 - TARGET) / 2) + r
      lcd.color(colors.active)
      lcd.drawRectangle(gx + 1, y0 + s - z - 1, z, z)
      local fx, fy = reading(sticks[k].x), reading(sticks[k].y)
      if fx and fy then
        local px = cx + math.floor(fx * (s / 2 - r - 2))
        local py = cy - math.floor(fy * (s / 2 - r - 2))
        lcd.color((fx <= -TARGET and fy <= -TARGET) and colors.active or colors.text)
        lcd.drawLine(cx, cy, px, py)
        lcd.drawFilledCircle(px, py, r)
      end
      lcd.color(colors.muted)
      lcd.drawText(gx + math.floor(s / 2), y0 + s + 4, stickNames[k], CENTERED)
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
      scr:draw(drawSticks, nil, true)
      scr:live(drawBars, BARS_LINES)
      -- Next when the bars follow the sticks; Detect when they don't.
      return scr:row(nil, {{text = T.wrong, press = startDetect}})
    end
    local fn = FUNCTIONS[DETECT_ORDER[#found + 1]]
    scr:text(T.detectTitle, fn.move)
    scr:draw(drawSticks, nil, true)
    scr:live(drawBars, BARS_LINES)
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
