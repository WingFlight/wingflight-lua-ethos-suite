-- Run from the repository root with Lua 5.3 or later:
-- lua bin/tests/dashboard_text.lua
-- Mocked metrics verify layout and caching, not physical radio font geometry.
FONT_XXS, FONT_XS, FONT_S, FONT_STD = 1, 2, 3, 4
FONT_L, FONT_XL, FONT_XXL, FONT_XXXXL = 5, 6, 7, 8
local font, measurements = FONT_XS, 0
local draws = {}
local function measure(text)
  local length = assert(utf8.len(text), 'Split UTF-8 character')
  return length * (font + 3), font + 8
end
lcd = {
  font = function(value) font = value end,
  getTextSize = function(text) measurements = measurements + 1; return measure(text) end,
  getWindowSize = function() return 480, 320 end,
  color = function() end,
  drawText = function(x, y, text) draws[#draws + 1] = {x=x, y=y, text=text, width=measure(text)} end,
}
package.loaded['wfsuite.lib.require'] = function() return {version={}} end
local context = assert(loadfile('src/wfsuite/widgets/dashboard/context.lua'))()
local utils = context.widgets.dashboard.utils
local function equal(actual, expected)
  assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))
end

for _,text in ipairs({'Übergrößen', 'Élévation', '传感器配置', 'Flight 😀'}) do
  local trimmed = utils.trimLastUtf8Char(text)
  equal(utf8.len(trimmed), utf8.len(text)-1)
  for width=1,150 do
    local fitted = utils.fitText(text, width, FONT_XS)
    assert(measure(fitted)<=width)
  end
end
equal(utils.fitText('ABCDE', 0, FONT_XS), '')
equal(utils.fitText('ABCDE', 14, FONT_XS), '')
equal(utils.fitText('ABCDE', 15, FONT_XS), '...')
equal(utils.fitText('AB   CCCCC', 30, FONT_XS), 'AB...')
equal(utils.fitText('@i18n(example)@', 10, FONT_XS), '@i18n(example)@')
equal(utils.fitText(nil, 10, FONT_XS), nil)

for _,width in ipairs({75,125,200}) do
  for _,value in ipairs({'ACTIVE','Boot-Grace-Zeit','Neustart erforderlich','RX-Wiederherstellung fehlgeschlagen','接收器连接失败😀'}) do
    local resolved, rendered, actualWidth = utils.resolveAndFitValue(value, FONT_L, width, 80)
    assert(actualWidth<=width)
    assert(resolved<=FONT_L)
    assert(utf8.len(rendered))
  end
end
local resolved, rendered = utils.resolveAndFitValue('ACTIVE', FONT_L, 125, 80)
equal(resolved, FONT_L); equal(rendered, 'ACTIVE')
resolved, rendered = utils.resolveAndFitValue('Boot-Grace-Zeit', FONT_L, 75, 80)
equal(resolved, FONT_XS); equal(rendered, 'Boot-Grace-Zeit')
resolved, rendered = utils.resolveAndFitValue(string.rep('W',100), nil, 25, 80)
equal(resolved, FONT_XXS)
assert(measure(rendered)<=25)

local function layout(box, value, title, width, alignment)
  return utils.prepareTextLayout(box,10,20,width,100,title,'bottom','center',FONT_XS,2,
    0,0,0,0,0,value,nil,FONT_L,alignment,0,0,0,0,0)
end
local longValue = 'RX-Wiederherstellung fehlgeschlagen'
local longTitle = 'Langer Titel mit Umlauten ÄÖÜ'
for _,alignment in ipairs({'left','center','right'}) do
  local box={}
  local cached=layout(box,longValue,longTitle,75,alignment)
  equal(cached.value,longValue); equal(cached.title,longTitle)
  assert(cached.renderValue~=longValue and cached.renderTitle~=longTitle)
  local before=measurements
  for _=1,20 do
    equal(layout(box,longValue,longTitle,75,alignment),cached)
    utils.paintTextLayout(cached,1,1)
  end
  equal(measurements,before) -- no new fitting or measuring on unchanged paints
  for _,draw in ipairs(draws) do
    assert(draw.x>=10 and draw.x+draw.width<=85, 'Text escaped its tile')
  end
  draws={}
  local changed=layout(box,'IDLE','Ready',200,alignment)
  equal(changed,cached) -- reuse the layout table on invalidation
  equal(changed.renderValue,'IDLE'); equal(changed.renderTitle,'Ready')
  assert(measurements>before)
end

-- Legacy uncached box users also get fitted values and titles.
local args={}
args[1],args[2],args[3],args[4]=10,20,75,100
args[5],args[6],args[7],args[8],args[9],args[10]=longTitle,'bottom','center',FONT_XS,2,1
for i=11,15 do args[i]=0 end
args[16],args[18],args[19],args[20]=longValue,FONT_L,'center',1
for i=21,25 do args[i]=0 end
utils.box(table.unpack(args,1,31))
for _,draw in ipairs(draws) do
  assert(draw.x>=10 and draw.x+draw.width<=85, 'Legacy text escaped its tile')
end

-- Bounded truncation cache prevents rebuilding unchanged legacy labels.
utils.fitText(longValue, 55, FONT_XS)
local before=measurements
utils.fitText(longValue, 55, FONT_XS)
equal(measurements,before)
context.widgets.dashboard.clearCaches({theme=true})
utils.fitText(longValue, 55, FONT_XS)
assert(measurements>before, 'Theme cleanup did not invalidate text cache')
print('Dashboard text checks passed: UTF-8, bounds, font stepping, cached and legacy layouts, cleanup')
