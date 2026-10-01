-- Run from the repository root with Lua 5.3+: lua bin/tests/gps_arm_without_fix.lua
-- Checks lib/msp_gps_rescue.lua and drives the real Setup -> GPS Navigation page
-- with a mocked form, bus and MSP replies. Pins that the "Arm w/o GPS Fix" row
-- writes back MSP_GPS_RESCUE with only byte 21 changed, and that the page still
-- works (row disabled, no rescue write) when the FC does not report the field.

local ROOT = "src/wfsuite/"

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print("  ok    " .. label)
  else
    failures = failures + 1
    print("  FAIL  " .. label)
    if detail then print("        " .. tostring(detail)) end
  end
end

local NAV_READ, NAV_WRITE = 0x5F16, 0x5F17
local RESCUE_READ, RESCUE_WRITE = 135, 225
local EEPROM_WRITE = 250
local ARM_LABEL = "@i18n(app.modules.gps_nav_config.arm_without_fix)@"

-- ---------------------------------------------------------------------------
-- Loader: real app/lib files, stubs for what needs a radio or an FC.
-- ---------------------------------------------------------------------------

local sent = {}     -- every published MSP message, in order
local headerOpts
local stubs = {
  ["lib/bus.lua"] = {
    publish = function(event, message)
      if event == "msp.request" then sent[#sent + 1] = message end
    end,
    subscribe = function(_, fn) return fn end,
    unsubscribe = function() end,
  },
  ["app/close_key.lua"] = {shouldHandleClose = function() return false end},
  ["app/header.lua"] = {build = function(_, opts)
    headerOpts = opts
    return {
      setSaveEnabled = function() end, setReloadEnabled = function() end,
      focusMenu = function() end, focusSave = function() end, focusReload = function() end,
    }
  end},
  ["app/progress_dialog.lua"] = {open = function()
    return {value = function() end, close = function() end}
  end},
}
local cache = {}
package.loaded["wfsuite.lib.require"] = function(path)
  if stubs[path] then return stubs[path] end
  if cache[path] == nil then
    local result = assert(loadfile(ROOT .. path))()
    cache[path] = result == nil and true or result
  end
  return cache[path]
end

-- A form that records each field by its line label.
local fieldsByLabel
local function newField(label, get, set)
  local field = {label = label, get = get, set = set, enabled = true}
  function field:enable(v) self.enabled = v end
  function field:suffix() end
  function field:step() end
  fieldsByLabel[label] = field
  return field
end
form = {
  clear = function() fieldsByLabel = {} end,
  addLine = function(label) return {label = label} end,
  addChoiceField = function(line, _, _, get, set) return newField(line.label, get, set) end,
  addNumberField = function(line, _, _, _, get, set) return newField(line.label, get, set) end,
  openDialog = function(d) d.buttons[1].action() end,   -- press OK
  invalidate = function() end,
}

local function bytes(n, fill)
  local t = {}
  for i = 1, n do t[i] = fill and fill(i) or i end
  return t
end

-- A 24-byte MSP_GPS_RESCUE reply: byte i holds i, except byte 21 (the flag).
local function rescueReply(flag, n)
  local t = bytes(n or 24)
  if #t >= 21 then t[21] = flag end
  return t
end

local function reply(message, buf)
  buf.offset = 1
  message.processReply(message, buf)
end

-- ---------------------------------------------------------------------------
-- lib/msp_gps_rescue.lua
-- ---------------------------------------------------------------------------

local codec = package.loaded["wfsuite.lib.require"]("lib/msp_gps_rescue.lua")

check("decode: a reply without the field is nil", codec.decode(rescueReply(0, 21)) == nil)
do
  local c = codec.decode(rescueReply(1))
  check("decode: reads the flag at byte 21", c and c.allow_arming_without_fix == 1)
  c.allow_arming_without_fix = 0
  local p = codec.buildWriteMessage(c).payload
  local same = #p == 24
  for i = 1, 24 do
    if i ~= 21 and p[i] ~= i then same = false end
  end
  check("write: only byte 21 changes, length kept", same and p[21] == 0, table.concat(p, ","))
  check("write: does not alter the decoded raw bytes", c.raw[21] == 1)
end

-- ---------------------------------------------------------------------------
-- app/pages/gps_nav_config.lua
-- ---------------------------------------------------------------------------

local function openPage()
  for k in pairs(sent) do sent[k] = nil end
  local page = assert(loadfile(ROOT .. "app/pages/gps_nav_config.lua"))()
  page.open({})
  return fieldsByLabel[ARM_LABEL]
end

local function commands()
  local t = {}
  for i, m in ipairs(sent) do t[i] = string.format("0x%X", m.command) end
  return table.concat(t, " ")
end

local navReply = bytes(16, function() return 0 end)

do
  local arm = openPage()
  check("page: the arming row exists and starts disabled", arm and arm.enabled == false)
  check("page: nav config is read first", #sent == 1 and sent[1].command == NAV_READ, commands())
  reply(sent[1], navReply)
  check("page: then MSP_GPS_RESCUE is read", #sent == 2 and sent[2].command == RESCUE_READ, commands())
  reply(sent[2], rescueReply(0))
  check("page: the row is enabled and shows Off", arm.enabled == true and arm.get() == 0)

  arm.set(1)
  headerOpts.onSave()
  check("page: save writes nav config first", sent[3] and sent[3].command == NAV_WRITE, commands())
  sent[3].processReply()
  local w = sent[4]
  check("page: then MSP_SET_GPS_RESCUE", w and w.command == RESCUE_WRITE, commands())
  local untouched = w and #w.payload == 24
  for i = 1, 24 do
    if w and i ~= 21 and w.payload[i] ~= i then untouched = false end
  end
  check("page: the rescue write carries ON and keeps every other byte",
    untouched and w.payload[21] == 1, w and table.concat(w.payload, ","))
  w.processReply()
  check("page: then the EEPROM commit", sent[5] and sent[5].command == EEPROM_WRITE, commands())
end

do
  local arm = openPage()
  reply(sent[1], navReply)
  sent[2].errorHandler("timeout")
  check("page: a failed rescue read leaves the row disabled", arm.enabled == false)
  check("page: and the nav fields usable", fieldsByLabel["@i18n(app.modules.gps_nav_config.rth_altitude)@"].enabled == true)
  arm.set(1)
  headerOpts.onSave()
  sent[3].processReply()
  check("page: save then skips the rescue write", sent[4] and sent[4].command == EEPROM_WRITE, commands())
end

do
  local arm = openPage()
  reply(sent[1], navReply)
  reply(sent[2], rescueReply(1, 20))
  check("page: a reply from firmware without the field leaves the row disabled", arm.enabled == false)
end

print()
if failures == 0 then
  print(string.format("all %d checks passed", checks))
  os.exit(0)
end
print(string.format("%d of %d checks FAILED", failures, checks))
os.exit(1)
