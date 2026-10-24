-- Setup Wizard screens: what every step's screen is made of. A title, a few
-- lines of text, an optional picture (app/setup_wizard_art.lua) or other
-- drawing, rows of values, and one row of buttons along the bottom in the
-- same order on every screen: Back on the left, the screen's own buttons
-- (answers, Start, nudges), the way forward on the right.
-- The buttons are form fields (touch and the rotary encoder both work); the
-- rest is drawn from the page's paint handler, below the header.
--
--   local screen = ui.new(wiz)
--   -- in step.build():
--   screen:begin()
--   screen:text(title, body, accentLine)
--   screen:picture(art.layout(...), caption)   -- or screen:draw(fn[, caption, side])
--   return screen:row(backFn, {{text =, press =, primary =, needsMotion =, small =, weight =}, ...}, forwardSpec)
--   -- in step.paint():
--   screen:paint()
--
-- begin() is called from build() only (it reads form.height()); paint()
-- does not allocate.
--
-- Side by side: a screen with a picture (or a drawing passed with side =
-- true) shows it in the left half and its words (body, status line, rows)
-- in the right half, under a full-width title, as Rotorflight's wizard
-- does: the picture gets the screen's whole height instead of what the
-- text leaves. When the words don't fit the column the screen stays
-- stacked (text above, picture below). Gauges, bars and grids that need
-- the width stay stacked. The row of buttons is the same either way.

if package.loaded["wfsuite.app.setup_wizard_ui"] then
  return package.loaded["wfsuite.app.setup_wizard_ui"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local art = requireModule("app/setup_wizard_art.lua")

local floor = math.floor
local BUTTON_GAP = 6
local MARGIN = 8
local GRID_MIN_H = 30
local GRID_MAX_H = 56
-- Side by side: the picture's share of the width.
local SIDE_SHARE = 0.5
-- Body text in FONT_STD on screens at least this wide (the 800 px radios)
-- when it fits; FONT_S otherwise.
local BIG_TEXT_MIN_W = 700
local BIG_FIRST = {FONT_STD, FONT_S}
local SMALL_ONLY = {FONT_S}
-- Stacked text may take the room only while it leaves a picture this much.
local STACKED_PICTURE_SHARE = 0.5
-- A choice list's buttons: this share of the width, the help beside them.
local CHOICE_BUTTON_SHARE = 0.3
-- Its rows take this share of the room under the title, each at least
-- CHOICE_MIN_H (four fit on the X18 with a status line above).
local CHOICES_SHARE = 0.62
local CHOICE_MIN_H = 26
local CHOICE_GAP = 4
local HELP_FONTS_BIG = {FONT_STD, FONT_S}
local HELP_FONTS = {FONT_S}
local NEXT = "@i18n(app.modules.setup_wizard.btn_next)@"

-- The row's Back and plain Next are small icon-only buttons (as the
-- header's): chevrons, not the header's arrow, which leaves the wizard.
-- Loaded with the module, which the wizard frees when it closes.
local PREV_ICON = lcd.loadMask("app/gfx/nav/prev.png")
local NEXT_ICON = lcd.loadMask("app/gfx/nav/next.png")
-- Row geometry: nav buttons are square-ish, a forward button with words
-- (Save and continue, Save and restart, ...) a fixed width; NAV_GAP keeps
-- the screen's own buttons clear of them; ACTION_MAX stops a lone Start
-- stretching across the screen.
local NAV_W = 48
local FORWARD_TEXT_SHARE = 0.36
local NAV_GAP = 16
local ACTION_MAX_SHARE = 0.4

local Screen = {}
Screen.__index = Screen

local ui = {}

-- Ethos may retain a form callback after form.clear(). Give it a bounded
-- set of dispatchers, never a step closure (which captures its whole screen).
-- Keep slots across visits, but detach their targets before rebuilding/leaving.
local actions = {}
function ui.action(key, target)
  local slot = actions[key]
  if not slot then
    slot = {}
    slot.press = function()
      if slot.target then return slot.target() end
    end
    actions[key] = slot
  end
  slot.target = target
  return slot.press
end

function ui.releaseActions()
  for _, slot in pairs(actions) do slot.target = nil end
end

-- Modules a step loads only for itself are freed when the step closes, as
-- app/page_runtime.lua's unloadPackageKeys does for other pages; otherwise
-- every step visited leaves its codecs in package.loaded for the rest of the
-- session. A step calls notLoaded() before requiring them and returns the
-- result as `owned`; the shell passes it to unload(). A module that another
-- page or the background task had loaded first is not in the list, so it
-- stays loaded.
function ui.notLoaded(keys)
  local out = {}
  for i = 1, #keys do
    if package.loaded[keys[i]] == nil then out[#out + 1] = keys[i] end
  end
  return out
end

function ui.unload(keys)
  for i = 1, #keys do package.loaded[keys[i]] = nil end
end

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
  v.body, v.accent = nil, nil
  v.picture, v.caption, v.drawFn = nil, nil, nil
  v.side, v.split = false, nil
  v.arranged = false
  v.font = FONT_S
  v.rows = {}
  v.live, v.liveLines = nil, 0
  v.choices = nil
  v.textStop = nil
  self.buttonList = {}
end

-- body and accent wrapped to maxW in font: the lines, and where the accent
-- starts.
local function wrapText(wiz, body, accent, maxW, font)
  local lines = body and wiz.wrapLines(body, maxW, font) or {}
  local accentFrom = nil
  if accent and accent ~= "" then
    accentFrom = #lines + 1
    local extra = wiz.wrapLines(accent, maxW, font)
    for i = 1, #extra do lines[#lines + 1] = extra[i] end
  end
  return lines, accentFrom
end

-- title (FONT_STD), body (wrapped), accent (wrapped, in the accent colour: a
-- status or warning line), progress ("4 of 4", or true). Any may be nil.
-- With progress the title is the thing being worked on now (a servo, an
-- axis, a check, a mode): it is drawn in the accent colour, and a progress
-- string muted after it. A step's fixed titles stay plain. The body is in
-- FONT_S until row() knows the room it has (arrange()).
function Screen:text(title, body, accent, progress)
  local v = self.view
  local width = lcd.getWindowSize()
  v.title = title
  v.progress = progress
  v.body, v.accent = body, accent
  v.font = FONT_S
  v.lines, v.accentFrom = wrapText(self.wiz, body, accent, width - 2 * MARGIN, FONT_S)
end

function Screen:picture(layout, caption)
  self.view.picture = layout
  self.view.caption = caption
  self.view.side = true
end

-- fn(x, y, w, h, colors) draws in the space below the text, or with side
-- in the left half beside it (a picture, not a gauge that needs the width).
function Screen:draw(fn, caption, side)
  self.view.drawFn = fn
  self.view.caption = caption
  self.view.side = side and true or false
end

-- A live readout (gauges, bars) under the words: in the right column beside
-- a picture, or under the text when stacked. fn(x, y, w, h, colors);
-- lines is the least room it needs, in FONT_S lines.
function Screen:live(fn, lines)
  self.view.live = fn
  self.view.liveLines = lines or 2
end

local function liveHeight(v)
  if not v.live then return 0 end
  lcd.font(FONT_S)
  local _, lineH = lcd.getTextSize("Ag")
  return 4 + v.liveLines * lineH
end

-- Height of the words in font: the wrapped lines, the rows under them, and
-- the live readout.
local function wordsHeight(v, lines, font)
  lcd.font(font)
  local _, lineH = lcd.getTextSize("Ag")
  return #lines * lineH + ((#v.rows > 0) and (4 + #v.rows * (lineH + 2)) or 0) + liveHeight(v)
end

-- How the screen is laid out, once row() knows where the row starts
-- (view.bottom): the body font, and side by side or stacked. The first
-- that fits wins: side by side (a screen with a side picture) in FONT_STD
-- then FONT_S, then stacked in FONT_STD then FONT_S. FONT_STD is tried on
-- big screens only, and stacked FONT_S is the fallback whatever fits (the
-- layout before side by side existed). Stacked counts as fitting when the
-- words leave a picture or drawing at least STACKED_PICTURE_SHARE of the
-- room.
function Screen:arrange()
  local v = self.view
  v.split = nil
  v.arranged = true
  local width, height = lcd.getWindowSize()
  lcd.font(FONT_STD)
  local _, titleH = lcd.getTextSize("Ag")
  local top = v.top + (v.title and (titleH + 2) or 0)
  local room = (v.bottom or (height - 4)) - top
  local hasPicture = (v.picture or v.drawFn) and true or false
  local fonts = (width >= BIG_TEXT_MIN_W) and BIG_FIRST or SMALL_ONLY
  local leftW = floor(width * SIDE_SHARE)
  local colX = leftW + MARGIN
  -- One line of text and nothing else ("Ailerons?") would leave the right
  -- half empty: stacked, the picture gets the full width instead.
  local short = #v.rows == 0 and not v.live
    and #wrapText(self.wiz, v.body, v.accent, width - colX - MARGIN, FONT_S) <= 1
  if v.side and hasPicture and not short then
    for i = 1, #fonts do
      local font = fonts[i]
      local lines, accentFrom = wrapText(self.wiz, v.body, v.accent, width - colX - MARGIN, font)
      if wordsHeight(v, lines, font) <= room - 4 then
        v.lines, v.accentFrom, v.font = lines, accentFrom, font
        v.split = {top = top + 4, leftW = leftW, colX = colX}
        return
      end
    end
  end
  for i = 1, #fonts do
    local font = fonts[i]
    local lines, accentFrom = wrapText(self.wiz, v.body, v.accent, width - 2 * MARGIN, font)
    local left = room - wordsHeight(v, lines, font)
    if font == FONT_S or left >= (hasPicture and floor(room * STACKED_PICTURE_SHARE) or 0) then
      v.lines, v.accentFrom, v.font = lines, accentFrom, font
      return
    end
  end
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

-- The row of buttons: its top and height (the screen's size alone).
local function rowGeometry()
  local _, height = lcd.getWindowSize()
  local h = math.max(36, floor(height * 0.15))
  return height - h - 4, h
end

local function addButton(self, rect, key, s, font)
  local field
  if s.icon then
    field = form.addButton(nil, rect, {icon = s.icon, press = ui.action(key, s.press)})
  else
    field = form.addButton(nil, rect, {
      text = s.text,
      options = font + CENTERED,
      press = ui.action(key, s.press),
    })
  end
  -- The field is Ethos userdata: the flags live beside it.
  self.buttonList[#self.buttonList + 1] = {field = field, needsMotion = s.needsMotion, disabled = s.disabled}
  return field
end

-- One row of buttons along the bottom, always in the same order: Back on the
-- left, the screen's own buttons, the way forward on the right.
--   back     function; nil goes to the previous step (no Back on the first)
--   specs    the screen's own buttons, or nil:
--            {{text =, press =, weight =, primary =, needsMotion =, small =}, ...}
--   forward  {text =, press =, disabled =, needsMotion =}; nil for the
--            default, wiz.forward() (Next, Save and continue, or Save and
--            finish on the last step); false for none, on a question whose
--            answers are the way forward
-- Back and a plain Next are small chevron buttons at the two ends; a way
-- forward that saves, restarts or confirms keeps its words. The screen's own
-- buttons sit between them, NAV_GAP clear. Returns the field to focus: a
-- spec with primary =, else the way forward.
--
-- The rotary encoder visits fields in the order they are made, so the row
-- makes them left to right (Back, the screen's own, the way forward), and a
-- screen with a grid or choice list makes that first (it is above the row:
-- call grid()/choices() before row()).
function Screen:row(back, specs, forward)
  specs = specs or {}
  if back == nil and not self.wiz.isFirstStep() then back = self.wiz.previousStep end
  if forward == nil then forward = self.wiz.forward() end

  local width = lcd.getWindowSize()
  local y, h = rowGeometry()
  local room = width - self.wiz.FORM_RIGHT_PADDING
  local left, right = 0, room
  local focus, forwardField

  -- Where everything goes first, then the fields in screen order.
  if back then left = NAV_W + NAV_GAP end
  local forwardW, forwardSpec = 0, nil
  if forward then
    local plain = forward.text == NEXT
    forwardW = plain and NAV_W or floor(room * FORWARD_TEXT_SHARE)
    forwardSpec = {text = forward.text, icon = plain and NEXT_ICON or nil, press = forward.press,
      disabled = forward.disabled, needsMotion = forward.needsMotion}
    right = room - forwardW - NAV_GAP
  end

  if back then
    addButton(self, {x = 0, y = y, w = NAV_W, h = h}, "nav_back", {icon = PREV_ICON, press = back}, FONT_S)
  end
  if #specs > 0 then
    local total = 0
    for i = 1, #specs do total = total + (specs[i].weight or 1) end
    local free = right - left - BUTTON_GAP * (#specs - 1)
    local most = floor(room * ACTION_MAX_SHARE)
    local x = left
    for i = 1, #specs do
      local s = specs[i]
      local w = math.min(most, floor(free * (s.weight or 1) / total))
      local field = addButton(self, {x = x, y = y, w = w, h = h}, i, s, s.small and FONT_S or FONT_STD)
      if s.primary then focus = field end
      x = x + w + BUTTON_GAP
    end
  end
  if forwardSpec then
    local field = addButton(self, {x = room - forwardW, y = y, w = forwardW, h = h}, "nav_next", forwardSpec, FONT_S)
    if not forward.disabled then forwardField = field end
  end

  self.view.bottom = y - 4
  if not self.view.arranged then self:arrange() end
  self:refresh()
  return focus or forwardField
end

-- A grid or choice list is made before the row (see row()): where the row
-- will be, and the layout of the text above.
function Screen:beforeRow()
  local v = self.view
  if not v.bottom then
    local y = rowGeometry()
    v.bottom = y - 4
  end
  if not v.arranged then self:arrange() end
end

-- Buttons placed between the text and the row take room the text was laid
-- out with (arrange() chose the body font for the whole room): drop to
-- FONT_S if the bigger font no longer fits above top, and cut the body
-- short (paint(), which keeps the status line) if even that runs into it.
function Screen:fitTextAbove(top, titleBottom)
  local v = self.view
  local width = lcd.getWindowSize()
  lcd.font(v.font or FONT_S)
  local _, lineH = lcd.getTextSize("Ag")
  if v.font ~= FONT_S and titleBottom + #v.lines * lineH > top then
    v.font = FONT_S
    v.lines, v.accentFrom = wrapText(self.wiz, v.body, v.accent, width - 2 * MARGIN, FONT_S)
    lcd.font(FONT_S)
    _, lineH = lcd.getTextSize("Ag")
  end
  if titleBottom + #v.lines * lineH > top then v.textStop = top - 2 end
end

-- A few options, one per row between the text and the row (call it before
-- row(), so the encoder reaches them first): a button on the left and what
-- the option means beside it.
-- specs: {{text =, help =, current =, press =, disabled =, needsMotion =},
-- ...}; the current option's help is drawn lit. The list sits centred between
-- the text and the row, and the text above gives way. Returns the field to focus: the
-- current option, else nil.
function Screen:choices(specs)
  local focus
  local width, height = lcd.getWindowSize()
  local v = self.view
  self:beforeRow()
  local n = #specs
  local stop = (v.bottom or (height - 4)) - 4
  lcd.font(FONT_STD)
  local _, titleH = lcd.getTextSize("Ag")
  local titleBottom = v.top + (v.title and (titleH + 2) or 0) + 4
  -- Row height from the screen alone (so a status line that comes or goes
  -- never moves the buttons): CHOICES_SHARE of the room under the title.
  local h = floor(((stop - titleBottom) * CHOICES_SHARE - CHOICE_GAP * (n - 1)) / n)
  h = math.max(CHOICE_MIN_H, math.min(GRID_MAX_H, h))
  local listH = n * h + CHOICE_GAP * (n - 1)
  -- Centred in the room the body leaves, with one line kept for a status
  -- line: the body is fixed for the screen, so a status line coming or
  -- going still never moves the list (a longer one cuts the body short).
  lcd.font(v.font or FONT_S)
  local _, lineH = lcd.getTextSize("Ag")
  local bodyLines = v.accentFrom and (v.accentFrom - 1) or #v.lines
  local free = stop - (titleBottom + (bodyLines + 1) * lineH) - listH
  local top = stop - listH - ((free > 0) and floor(free / 2) or 0)
  self:fitTextAbove(top, titleBottom)
  local bw = floor(width * CHOICE_BUTTON_SHARE)
  local helpX = bw + 2 * MARGIN
  local helpW = width - helpX - MARGIN
  -- The help in the biggest font in which every one fits its row.
  local font = FONT_XS
  for _, f in ipairs((width >= BIG_TEXT_MIN_W) and HELP_FONTS_BIG or HELP_FONTS) do
    lcd.font(f)
    local _, fh = lcd.getTextSize("Ag")
    local fits = true
    for i = 1, n do
      if #self.wiz.wrapLines(specs[i].help or "", helpW, f) * fh > h then fits = false break end
    end
    if fits then font = f break end
  end
  v.choices = {x = helpX, font = font}
  for i, s in ipairs(specs) do
    local y = top + (i - 1) * (h + CHOICE_GAP)
    local field = addButton(self, {x = 0, y = y, w = bw, h = h}, "choice_" .. i, s, FONT_S)
    if s.current then focus = field end
    v.choices[i] = {y = y, h = h, current = s.current, lines = self.wiz.wrapLines(s.help or "", helpW, font)}
  end
  self:refresh()
  return focus
end

-- Many choices: a grid of buttons filling the space between the text and
-- the row (call it before row(), so the encoder reaches them first). A grid
-- screen has no picture. Returns the field to focus (a spec with primary
-- =), or nil.
function Screen:grid(specs, cols)
  local focus
  local width, height = lcd.getWindowSize()
  local v = self.view
  self:beforeRow()
  lcd.font(FONT_S)
  local _, th = lcd.getTextSize("Ag")
  local stop = (v.bottom or (height - 4)) - 4
  local rows = math.ceil(#specs / cols)
  -- The grid sits on the row, its height set by the screen alone, so a status
  -- line that comes or goes in the text above never moves it. Text that runs
  -- into it is cut short (paint(), which keeps the status line).
  local titleBottom = v.top + (v.title and (th + 8) or 0) + 4
  local h = math.max(GRID_MIN_H, math.min(GRID_MAX_H, floor(height * 0.12)))
  h = math.min(h, floor((stop - titleBottom - BUTTON_GAP * (rows - 1)) / rows))
  local top = stop - (rows * h + BUTTON_GAP * (rows - 1))
  self:fitTextAbove(top, titleBottom)
  local w = math.floor((width - self.wiz.FORM_RIGHT_PADDING - BUTTON_GAP * (cols - 1)) / cols)
  for i, s in ipairs(specs) do
    local col, r = (i - 1) % cols, math.floor((i - 1) / cols)
    local field = addButton(self, {x = col * (w + BUTTON_GAP), y = top + r * (h + BUTTON_GAP), w = w, h = h},
      "grid_" .. i, s, FONT_S)
    if s.primary then focus = field end
  end
  v.gridUsed = true
  self:refresh()
  return focus
end

-- Grey out the buttons that move something while the wizard can't.
function Screen:refresh()
  local canMove = self.wiz.canMove()
  for i = 1, #self.buttonList do
    local b = self.buttonList[i]
    if b.field and b.field.enable then
      local enabled = not b.disabled and (not b.needsMotion or canMove)
      if b.enabled ~= enabled then
        b.enabled = enabled
        b.field:enable(enabled)
      end
    end
  end
end

-- "label  value" rows from y, between x and right, stopping above stop.
-- Returns the y after the last row.
local function paintRows(v, x, right, y, colors, stop)
  local _, th = lcd.getTextSize("Ag")
  local room = right - x - 8
  for i = 1, #v.rows do
    if y > stop - th then break end
    local row = v.rows[i]
    local value = row[2] or ""
    lcd.color(colors.muted)
    lcd.drawText(x, y, row[1], LEFT)
    local lw = lcd.getTextSize(row[1])
    local vw = lcd.getTextSize(value)
    lcd.color(row[3] and colors.active or colors.text)
    if lw + vw + 16 <= room then
      lcd.drawText(right - 8, y, value, RIGHT)
    else
      -- No room beside the label: on its own line, shortened to fit.
      y = y + th
      if vw > room - 16 then value = ui.fit(value, room - 16) end
      lcd.drawText(x + 16, y, value, LEFT)
    end
    y = y + th + 2
  end
  return y
end

-- The picture or drawing in x, y, w, h, with its caption at the bottom.
local function paintPicture(v, x, y, w, h, colors)
  if v.caption then
    lcd.font(FONT_XS)
    local _, ch = lcd.getTextSize(v.caption)
    lcd.color(colors.muted)
    lcd.drawText(x + MARGIN, y + h - ch, v.caption, LEFT)
    h = h - ch
  end
  if v.picture then
    art.draw(v.picture, x, y, w, h, colors)
  elseif v.drawFn then
    v.drawFn(x + MARGIN, y, w - 2 * MARGIN, h, colors)
  end
end

function Screen:paint()
  local v = self.view
  local colors = art.colors()
  local width, height = lcd.getWindowSize()
  local y = v.top
  if v.title then
    lcd.font(FONT_STD)
    lcd.color(v.progress and colors.active or colors.text)
    lcd.drawText(MARGIN, y, v.title, LEFT)
    local tw, th = lcd.getTextSize(v.title)
    if type(v.progress) == "string" then
      lcd.color(colors.muted)
      lcd.drawText(MARGIN + tw + 12, y, v.progress, LEFT)
    end
    y = y + th + 2
  end
  local sp = v.split
  if sp then
    -- Side by side: the words in the right column, the picture on the left.
    local bottom = v.bottom or (height - 4)
    lcd.font(v.font or FONT_S)
    local _, lineH = lcd.getTextSize("Ag")
    local ty = sp.top
    for i = 1, #v.lines do
      lcd.color((v.accentFrom and i >= v.accentFrom) and colors.active or colors.text)
      lcd.drawText(sp.colX, ty, v.lines[i], LEFT)
      ty = ty + lineH
    end
    if #v.rows > 0 then ty = paintRows(v, sp.colX, width - MARGIN, ty + 4, colors, bottom) end
    if v.live then v.live(sp.colX, ty + 4, width - sp.colX - MARGIN, bottom - ty - 4, colors) end
    paintPicture(v, 0, sp.top, sp.leftW, bottom - sp.top, colors)
    return
  end
  lcd.font(v.font or FONT_S)
  -- Cut short by a grid (textStop): the body loses lines from its end, the
  -- accent lines (a status or warning) are kept.
  local _, lineH = lcd.getTextSize("Ag")
  local skipFrom, skipTo = nil, nil
  if v.textStop then
    local fit = math.max(0, floor((v.textStop - y) / lineH))
    local excess = #v.lines - fit
    if excess > 0 then
      local bodyEnd = (v.accentFrom or (#v.lines + 1)) - 1
      skipTo = bodyEnd
      skipFrom = math.max(1, bodyEnd - excess + 1)
    end
  end
  for i = 1, #v.lines do
    if not (skipFrom and i >= skipFrom and i <= skipTo) then
      if v.textStop and y + lineH > v.textStop then break end
      lcd.color((v.accentFrom and i >= v.accentFrom) and colors.active or colors.text)
      lcd.drawText(MARGIN, y, v.lines[i], LEFT)
      y = y + lineH
    end
  end
  if #v.rows > 0 then
    y = paintRows(v, MARGIN, width - MARGIN, y + 4, colors, v.bottom or height)
  end
  local bottom = v.bottom or (height - 4)
  if v.live then
    -- Its own room when a picture follows; all that is left otherwise.
    local lh = (v.picture or v.drawFn) and (liveHeight(v) - 4) or (bottom - y - 6)
    v.live(MARGIN, y + 4, width - 2 * MARGIN, lh, colors)
    y = y + 4 + lh
  end
  if v.choices then
    local c = v.choices
    lcd.font(c.font)
    local _, ch = lcd.getTextSize("Ag")
    for i = 1, #c do
      local row = c[i]
      local ly = row.y + floor((row.h - #row.lines * ch) / 2)
      lcd.color(row.current and colors.active or colors.text)
      for k = 1, #row.lines do
        lcd.drawText(c.x, ly, row.lines[k], LEFT)
        ly = ly + ch
      end
    end
  end
  if v.picture or v.drawFn then
    paintPicture(v, 0, y + 4, width, bottom - y - 6, colors)
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
