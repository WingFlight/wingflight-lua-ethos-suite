-- Setup Wizard step: Travel check. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepTravel.svelte and its
-- TravelGauge.svelte: one row per surface, with how far it goes with full
-- stick on every axis that drives it at once, as a percentage of its binding
-- limit on each side (lib/setup_wizard_surfaces.lua travelReach()). Above
-- 100% the surface reaches its limit before full stick, and the stabilizer
-- has no travel left on that side. The wizard forces PASSTHROUGH so the pilot
-- can move the sticks into the corners and watch.
--
-- Each row's gauge, either side of the centre: the binding limit (a mark),
-- full-stick reach (the fill, red past the limit), where the servo is now
-- (a dot, from the shell's live MSP_SERVO poll, livePositions) and the
-- furthest it has gone on this visit (a thin mark), so trying the stick
-- corners leaves something to see. The last is the radio's own: the
-- configurator shows only the live dot.
--
-- Differences from the configurator: the servo balance curve is not
-- included in the reach yet (see lib/setup_wizard_surfaces.lua).

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.trv_title)@",
  intro = "@i18n(app.modules.setup_wizard.trv_intro)@",
  row = "@i18n(app.modules.setup_wizard.trv_row_fmt)@",
  clipping = "@i18n(app.modules.setup_wizard.trv_clipping)@",
  ok = "@i18n(app.modules.setup_wizard.trv_ok)@",
  noPass = "@i18n(app.modules.setup_wizard.thr_no_passthrough)@",
}

-- As TravelGauge.svelte: each limit sits LIMIT_AT of the way out from the
-- centre; the rest of the bar shows overshoot, up to OVER_MAX times the limit.
local LIMIT_AT = 0.8
local OVER_MAX = 1.25

local OVER_COLOR = lcd.RGB(230, 60, 50)

local function new(wiz)
  local self = {livePositions = true}
  local scr = ui.new(wiz)
  -- Per row, rebuilt with the screen: {surface, reach, label, over}.
  local rows = {}
  -- Per servo, refilled in place: the last pulse drawn, and the furthest
  -- the servo has gone either side of its centre on this visit, in us.
  local shown, peakNeg, peakPos = {}, {}, {}

  local function along(fraction)
    if fraction < 0 then fraction = 0 elseif fraction > OVER_MAX then fraction = OVER_MAX end
    return fraction * LIMIT_AT
  end

  -- The servo's offset from its centre now, or nil before the first reply.
  local function offsetNow(servo)
    local pulse = wiz.positions[servo]
    local config = wiz.configs[servo]
    if not pulse or pulse <= 0 or not config then return nil end
    return pulse - config.mid
  end

  local function drawGauge(gx, gy, gw, gh, row, colors)
    local half = math.floor(gw / 2)
    local cx = gx + half
    local mid = gy + math.floor(gh / 2)
    local barH = math.max(4, math.floor(gh * 0.45))
    local reach = row.reach
    -- Track.
    lcd.color(colors.body)
    lcd.drawFilledRectangle(gx, mid - 1, gw, 2)
    for dir = -1, 1, 2 do
      local s = dir < 0 and reach.neg or reach.pos
      -- Full-stick reach: inside the limit, then past it in red.
      local inside = math.floor(half * along(math.min(s.fraction, 1)))
      lcd.color(colors.active)
      if dir < 0 then
        lcd.drawFilledRectangle(cx - inside, mid - math.floor(barH / 2), inside, barH)
      else
        lcd.drawFilledRectangle(cx, mid - math.floor(barH / 2), inside, barH)
      end
      if s.fraction > 1 then
        local beyond = math.floor(half * along(s.fraction)) - inside
        lcd.color(OVER_COLOR)
        if dir < 0 then
          lcd.drawFilledRectangle(cx - inside - beyond, mid - math.floor(barH / 2), beyond, barH)
        else
          lcd.drawFilledRectangle(cx + inside, mid - math.floor(barH / 2), beyond, barH)
        end
      end
      -- The binding limit.
      local lx = cx + dir * math.floor(half * LIMIT_AT)
      lcd.color(colors.text)
      lcd.drawFilledRectangle(lx - 1, gy, 3, gh)
    end
    lcd.color(colors.muted)
    lcd.drawFilledRectangle(cx, gy + 2, 1, gh - 4)

    local servo = row.surface.servo
    -- Furthest this visit: thin marks, against the same limits.
    lcd.color(colors.text)
    local pn, pp = peakNeg[servo], peakPos[servo]
    if pn and pn > 0 and reach.neg.limit > 0 then
      local px = cx - math.floor(half * along(pn / reach.neg.limit))
      lcd.drawFilledRectangle(px, gy + 1, 1, gh - 2)
    end
    if pp and pp > 0 and reach.pos.limit > 0 then
      local px = cx + math.floor(half * along(pp / reach.pos.limit))
      lcd.drawFilledRectangle(px, gy + 1, 1, gh - 2)
    end
    -- Now.
    local offset = offsetNow(servo)
    if offset then
      local limit = offset >= 0 and reach.pos.limit or reach.neg.limit
      local f = limit > 0 and math.abs(offset) / limit or 0
      local dx = math.floor(half * along(f))
      lcd.color(f > 1 and OVER_COLOR or colors.text)
      lcd.drawFilledCircle(offset >= 0 and cx + dx or cx - dx, mid, math.max(3, math.floor(gh / 3)))
    end
  end

  local function drawRows(x, y, w, h, colors)
    if #rows == 0 then return end
    lcd.font(FONT_S)
    local _, th = lcd.getTextSize("Ag")
    local font = FONT_S
    if math.floor(h / #rows) < th + 2 then
      font = FONT_XS
      lcd.font(font)
      _, th = lcd.getTextSize("Ag")
    end
    local rowH = math.max(th, math.min(th + 12, math.floor(h / #rows)))
    local nameW = math.floor(w * 0.34)
    local valueW = math.floor(w * 0.2)
    local gx = x + nameW + 8
    local gw = w - nameW - valueW - 24
    for i = 1, #rows do
      local row = rows[i]
      local ry = y + (i - 1) * rowH
      if ry + rowH > y + h + 2 then break end
      local ty = ry + math.floor((rowH - th) / 2)
      lcd.font(font)
      lcd.color(colors.text)
      lcd.drawText(x, ty, row.name, LEFT)
      lcd.color(row.over and OVER_COLOR or colors.text)
      lcd.drawText(x + w, ty, row.label, RIGHT)
      drawGauge(gx, ry + 3, gw, rowH - 6, row, colors)
    end
  end

  local lastPass = nil
  -- PASSTHROUGH is on only while the wizard can move things (linked, disarmed).
  local function passOn() return wiz.canMove() and wiz.forcedMode() == wiz.BOX_PASSTHROUGH end

  function self.build()
    scr:begin()
    if wiz.canMove() and wiz.forcedMode() ~= wiz.BOX_PASSTHROUGH then wiz.forceMode(wiz.BOX_PASSTHROUGH) end
    lastPass = passOn()
    local gains = wiz.axisGains()
    local clips = false
    local list = wiz.surfaces()
    for i = 1, #list do
      local s = list[i]
      local reach = surfacesLib.travelReach(s, wiz.configs[s.servo], gains)
      local neg = math.floor(reach.neg.fraction * 100 + 0.5)
      local pos = math.floor(reach.pos.fraction * 100 + 0.5)
      local over = neg > 100 or pos > 100
      clips = clips or over
      local row = rows[i] or {}
      row.surface, row.reach, row.over = s, reach, over
      row.name, row.label = wiz.surfaceName(s), string.format(T.row, neg, pos)
      rows[i] = row
    end
    for i = #list + 1, #rows do rows[i] = nil end
    local accent = (not lastPass and T.noPass) or (clips and T.clipping) or T.ok
    scr:text(T.title, T.intro, accent)
    scr:draw(drawRows)
    -- Back is the Throws step, where a clipping surface is fixed.
    return scr:row()
  end

  function self.paint() scr:paint() end

  function self.wakeup()
    -- PASSTHROUGH comes and goes with the link and arming: say so.
    if passOn() ~= lastPass then
      wiz.rebuild()
      return
    end
    local moved = false
    for i = 1, #rows do
      local servo = rows[i].surface.servo
      local pulse = wiz.positions[servo]
      if pulse ~= shown[servo] then
        shown[servo] = pulse
        moved = true
        local offset = offsetNow(servo)
        if offset then
          if offset < 0 and -offset > (peakNeg[servo] or 0) then peakNeg[servo] = -offset end
          if offset > 0 and offset > (peakPos[servo] or 0) then peakPos[servo] = offset end
        end
      end
    end
    if moved then wiz.invalidate() end
  end

  function self.released() scr:refresh() end

  return self
end

return {new = new}
