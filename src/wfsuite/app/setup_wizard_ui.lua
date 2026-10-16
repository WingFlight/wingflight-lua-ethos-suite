-- Setup Wizard screens: what every step's screen is made of. A title, a few
-- lines of text, an optional picture (app/setup_wizard_art.lua) or other
-- drawing, rows of values, and one to five big buttons along the bottom.
-- The buttons are form fields (touch and the rotary encoder both work); the
-- rest is drawn from the page's paint handler, below the header.
--
--   local screen = ui.new(wiz)
--   -- in step.build():
--   screen:begin()
--   screen:text(title, body, accentLine)
--   screen:picture(art.layout(...), caption)   -- or screen:draw(fn)
--   return screen:buttons({{text =, press =, primary =, needsMotion =, small =, weight =}, ...})
--   -- in step.paint():
--   screen:paint()
--
-- begin() is called from build() only (it reads form.height()); paint()
-- does not allocate.

if package.loaded["wfsuite.app.setup_wizard_ui"] then
  return package.loaded["wfsuite.app.setup_wizard_ui"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local art = requireModule("app/setup_wizard_art.lua")

local floor = math.floor
local BUTTON_GAP = 6
local MARGIN = 8

local Screen = {}
Screen.__index = Screen

local ui = {}

function ui.new(wiz)
  return setmetatable({wiz = wiz, view = {lines = {}, rows = {}}, buttonList = {}}, Screen)
end

function Screen:begin()
  local v = self.view
  v.top = form.height() + 4
  v.bottom = nil
  v.title = nil
  v.lines = {}
  v.accentFrom = nil
  v.picture, v.caption, v.drawFn = nil, nil, nil
  v.rows = {}
  self.buttonList = {}
end

-- title (FONT_STD), body (wrapped, FONT_S), accent (wrapped, FONT_S, in the
-- accent colour: a status or warning line). Any may be nil.
function Screen:text(title, body, accent)
  local v = self.view
  local width = lcd.getWindowSize()
  v.title = title
  v.lines = body and self.wiz.wrapLines(body, width - 2 * MARGIN, FONT_S) or {}
  v.accentFrom = nil
  if accent and accent ~= "" then
    v.accentFrom = #v.lines + 1
    local extra = self.wiz.wrapLines(accent, width - 2 * MARGIN, FONT_S)
    for i = 1, #extra do v.lines[#v.lines + 1] = extra[i] end
  end
end

function Screen:picture(layout, caption)
  self.view.picture = layout
  self.view.caption = caption
end

-- fn(x, y, w, h, colors) draws in the space below the text.
function Screen:draw(fn, caption)
  self.view.drawFn = fn
  self.view.caption = caption
end

-- Rows of "label  value" below the text: {{label, value, accent}, ...}.
-- Values may be changed in place later (screen:setRow) without a rebuild.
function Screen:rows(list)
  self.view.rows = list
end

function Screen:setRow(i, value, accent)
  local row = self.view.rows[i]
  if not row or (row[2] == value and row[3] == accent) then return false end
  row[2], row[3] = value, accent
  return true
end

-- specs: {{text =, press =, weight =, primary =, needsMotion =, small =}, ...}
-- left to right along the bottom. Returns the field to focus.
function Screen:buttons(specs)
  local width, height = lcd.getWindowSize()
  local h = math.max(36, floor(height * 0.15))
  local y = height - h - 4
  local total = 0
  for i = 1, #specs do total = total + (specs[i].weight or 1) end
  local free = width - self.wiz.FORM_RIGHT_PADDING - BUTTON_GAP * (#specs - 1)
  local x, focus = 0, nil
  for i = 1, #specs do
    local s = specs[i]
    local w = floor(free * (s.weight or 1) / total)
    local field = form.addButton(nil, {x = x, y = y, w = w, h = h}, {
      text = s.text,
      options = (s.small and FONT_S or FONT_STD) + CENTERED,
      press = s.press,
    })
    -- The field is Ethos userdata: the flags live beside it.
    self.buttonList[#self.buttonList + 1] = {field = field, needsMotion = s.needsMotion, disabled = s.disabled}
    if s.primary then focus = field end
    x = x + w + BUTTON_GAP
  end
  self.view.bottom = y - 4
  self:refresh()
  return focus
end

-- Many choices: a grid of buttons filling the space below the text, `cols`
-- across, then the usual row (`bottom`, may be nil) along the bottom.
-- Call after text(); a grid screen has no picture. Returns the field to
-- focus (a spec with primary =, else the first).
function Screen:grid(specs, cols, bottom)
  local focus = bottom and self:buttons(bottom) or nil
  local width, height = lcd.getWindowSize()
  local v = self.view
  lcd.font(FONT_S)
  local _, th = lcd.getTextSize("Ag")
  local top = v.top + #v.lines * th + (v.title and (th + 8) or 0) + 4
  local stop = (v.bottom or (height - 4)) - 4
  local rows = math.ceil(#specs / cols)
  local h = math.floor((stop - top - BUTTON_GAP * (rows - 1)) / rows)
  if h > 56 then h = 56 end
  local w = math.floor((width - self.wiz.FORM_RIGHT_PADDING - BUTTON_GAP * (cols - 1)) / cols)
  local first
  for i, s in ipairs(specs) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local field = form.addButton(nil, {x = col * (w + BUTTON_GAP), y = top + row * (h + BUTTON_GAP), w = w, h = h}, {
      text = s.text,
      options = FONT_S + CENTERED,
      press = s.press,
    })
    self.buttonList[#self.buttonList + 1] = {field = field, needsMotion = s.needsMotion, disabled = s.disabled}
    first = first or field
    if s.primary then focus = field end
  end
  v.gridUsed = true
  self:refresh()
  return focus or first
end

-- Grey out the buttons that move something while the wizard can't.
function Screen:refresh()
  local canMove = self.wiz.canMove()
  for i = 1, #self.buttonList do
    local b = self.buttonList[i]
    if b.field and b.field.enable then
      b.field:enable(not b.disabled and (not b.needsMotion or canMove))
    end
  end
end

function Screen:paint()
  local v = self.view
  local colors = art.colors()
  local width, height = lcd.getWindowSize()
  local y = v.top
  if v.title then
    lcd.font(FONT_STD)
    lcd.color(colors.text)
    lcd.drawText(MARGIN, y, v.title, LEFT)
    local _, th = lcd.getTextSize(v.title)
    y = y + th + 2
  end
  lcd.font(FONT_S)
  for i = 1, #v.lines do
    lcd.color((v.accentFrom and i >= v.accentFrom) and colors.active or colors.text)
    lcd.drawText(MARGIN, y, v.lines[i], LEFT)
    local _, th = lcd.getTextSize(v.lines[i])
    y = y + th
  end
  if #v.rows > 0 then
    y = y + 4
    local _, th = lcd.getTextSize("Ag")
    local room = width - 2 * MARGIN - 8
    local stop = (v.bottom or height) - th
    for i = 1, #v.rows do
      if y > stop then break end
      local row = v.rows[i]
      local value = row[2] or ""
      lcd.color(colors.muted)
      lcd.drawText(MARGIN, y, row[1], LEFT)
      local lw = lcd.getTextSize(row[1])
      local vw = lcd.getTextSize(value)
      lcd.color(row[3] and colors.active or colors.text)
      if lw + vw + 16 <= room then
        lcd.drawText(width - MARGIN - 8, y, value, RIGHT)
      else
        -- No room beside the label: on its own line, shortened to fit.
        y = y + th
        if vw > room - 16 then value = ui.fit(value, room - 16) end
        lcd.drawText(MARGIN + 16, y, value, LEFT)
      end
      y = y + th + 2
    end
  end
  local bottom = v.bottom or (height - 4)
  if v.caption then
    lcd.font(FONT_XS)
    local _, ch = lcd.getTextSize(v.caption)
    lcd.color(colors.muted)
    lcd.drawText(MARGIN, bottom - ch, v.caption, LEFT)
    bottom = bottom - ch
  end
  if v.picture then
    art.draw(v.picture, 0, y + 4, width, bottom - y - 6, colors)
  elseif v.drawFn then
    v.drawFn(MARGIN, y + 4, width - 2 * MARGIN, bottom - y - 6, colors)
  end
end

-- text cut to fit maxW in the current font, with "..." at the end. Only
-- reached when a row is too long, so the allocation is rare.
function ui.fit(text, maxW)
  local n = #text
  while n > 1 and lcd.getTextSize(text:sub(1, n) .. "...") > maxW do n = n - 1 end
  return text:sub(1, n) .. "..."
end

-- A horizontal gauge, for live values: a track from x to x + w, a mark at
-- `fraction` (0..1 along it), and optional zone marks (also 0..1).
function ui.gauge(x, y, w, h, fraction, colors, zoneFrom, zoneTo)
  lcd.color(colors.body)
  lcd.drawFilledRectangle(x, y + floor(h / 2) - 2, w, 4)
  if zoneFrom and zoneTo then
    lcd.color(colors.surface)
    local zw = math.max(2, floor(w * (zoneTo - zoneFrom)))
    lcd.drawFilledRectangle(x + floor(w * zoneFrom), y + floor(h / 2) - 3, zw, 6)
  end
  if fraction then
    if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end
    lcd.color(colors.active)
    local mx = x + floor(w * fraction)
    lcd.drawFilledRectangle(mx - 3, y, 6, h)
  end
end

package.loaded["wfsuite.app.setup_wizard_ui"] = ui
return ui
