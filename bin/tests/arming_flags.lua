-- Run from the repository root with Lua 5.3+: lua bin/tests/arming_flags.lua
-- Checks lib/arming_flags.lua and drives the real Tools -> Diagnostics ->
-- FBL Status page with a mocked form, bus and MSP replies. Pins that the value
-- column only ever holds "OK" or a count, and the reasons get full-width rows
-- (the joined list used to be cut off the right edge on narrow screens).

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

local function tag(bit) return "@i18n(app.modules.fblstatus.arming_disable_flag_" .. bit .. ")@" end
local OK = "@i18n(app.modules.fblstatus.ok)@"
local HEADING = "@i18n(app.modules.fblstatus.arming_flags_active_list)@"
local ARM_SWITCH = 2 ^ 27

-- ---------------------------------------------------------------------------
-- Loader: real app/lib files, stubs for what needs a radio or an FC.
-- ---------------------------------------------------------------------------

local msp = {}      -- pending MSP replies by module name
local headerOpts    -- the page header's callbacks; onReload re-polls
local stubs = {
  ["lib/bus.lua"] = {
    publish = function(event, message)
      if event == "msp.request" then msp[message.module] = message end
    end,
    subscribe = function(_, fn) return fn end,
    unsubscribe = function() end,
  },
  ["app/close_key.lua"] = {shouldHandleClose = function() return false end},
  ["app/header.lua"] = {build = function(_, opts)
    headerOpts = opts
    return {setReloadEnabled = function() end, focusReload = function() end}
  end},
  ["lib/msp_status.lua"] = {buildReadMessage = function(ok, err)
    return {module = "status", ok = ok, err = err}
  end},
  ["lib/msp_dataflash_summary.lua"] = {buildReadMessage = function(ok, err)
    return {module = "dataflash", ok = ok, err = err}
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

-- A form that records each static text: its text, colour, and whether it was
-- laid out full-width (a rect) or in the default value column (nil).
local texts
local function newField(rect, text)
  local field = {rect = rect, text = text}
  function field:value(v) self.text = v end
  function field:color(c) self.colour = c end
  texts[#texts + 1] = field
  return field
end
form = {
  clear = function() texts = {} end,
  addLine = function(label) return {label = label} end,
  getFieldSlots = function() return {{x = 0, y = 0, w = 200, h = 30}} end,
  addStaticText = function(_, rect, text) return newField(rect, text) end,
}
lcd = {getWindowSize = function() return 472, 320 end}
GREEN, RED, LEFT = "green", "red", 0

local libOk, armingFlags = pcall(package.loaded["wfsuite.lib.require"], "lib/arming_flags.lua")

-- ---------------------------------------------------------------------------
-- lib/arming_flags.lua
-- ---------------------------------------------------------------------------

if not libOk then
  check("lib/arming_flags.lua loads", false, armingFlags)
else
  check("no flags: nothing active, summary OK",
    #armingFlags.active(0) == 0 and armingFlags.summary(0) == OK)
  local a = armingFlags.active(2 ^ 1 + 2 ^ 12 + 2 ^ 26)
  check("active flags are named, lowest bit first",
    #a == 3 and a[1] == tag(1) and a[2] == tag(12) and a[3] == tag(26),
    table.concat(a, " | "))
  local s = armingFlags.summary(3)
  check("summary is a count, never a name", s:find("arming_flags_active_fmt", 1, true) and not s:find("flag_", 1, true), s)
  local w = armingFlags.active(2 ^ 7 + ARM_SWITCH)
  check("ARM_SWITCH beside a real reason is left out", #w == 1 and w[1] == tag(7), table.concat(w, " | "))
  local only = armingFlags.active(ARM_SWITCH)
  check("ARM_SWITCH on its own is the reason", #only == 1 and only[1] == tag(27), table.concat(only, " | "))
  local u = armingFlags.active(2 ^ 30)
  check("an unnamed bit is shown as its mask, not dropped", #u == 1 and u[1] == "0x40000000", table.concat(u, " | "))
  local reuse = {"stale", "stale", "stale"}
  armingFlags.active(2 ^ 3, reuse)
  check("a reused list is cleared in place", #reuse == 1 and reuse[1] == tag(3), table.concat(reuse, " | "))
end

-- ---------------------------------------------------------------------------
-- app/pages/diagnostics_fblstatus.lua
-- ---------------------------------------------------------------------------

local function openPage()
  for k in pairs(msp) do msp[k] = nil end
  local page = assert(loadfile(ROOT .. "app/pages/diagnostics_fblstatus.lua"))()
  page.open({})
  return texts[1]   -- the Arming Flags value field is the page's first line
end

local function reply(mask)
  if not msp.status then headerOpts.onReload() end
  local status = msp.status
  msp.status = nil
  if msp.dataflash then msp.dataflash.ok({flags = 0}); msp.dataflash = nil end
  status.ok({arming_disable_flags = mask, reboot_required = 0})
end

local function fullWidthRows()
  local rows = {}
  for _, f in ipairs(texts) do
    if f.rect and f.text ~= "" then rows[#rows + 1] = f.text end
  end
  return rows
end

do
  local arming = openPage()
  reply(2 ^ 1 + 2 ^ 12 + 2 ^ 16)
  check("page: the value column holds a count, not the names",
    arming.text:find("arming_flags_active_fmt", 1, true) ~= nil and not arming.text:find("flag_", 1, true),
    "value=" .. tostring(arming.text))
  check("page: the value is red while arming is blocked", arming.colour == RED, tostring(arming.colour))
  local rows = fullWidthRows()
  check("page: a heading and one full-width row per reason",
    #rows == 4 and rows[1] == HEADING and rows[2] == tag(1) and rows[3] == tag(12) and rows[4] == tag(16),
    table.concat(rows, " | "))
end

do
  local arming = openPage()
  reply(2 ^ 1 + 2 ^ 12)
  local before = #texts
  reply(2 ^ 1 + 2 ^ 12)
  check("page: an unchanged mask adds no lines", #texts == before, before .. " -> " .. #texts)
  reply(0)
  check("page: cleared flags show OK in green", arming.text == OK and arming.colour == GREEN,
    tostring(arming.text) .. " " .. tostring(arming.colour))
  check("page: cleared flags empty their rows", #fullWidthRows() == 0, table.concat(fullWidthRows(), " | "))
  reply(2 ^ 5)
  local rows = fullWidthRows()
  check("page: rows are reused when flags return", #texts == before and #rows == 2 and rows[2] == tag(5),
    before .. " -> " .. #texts .. ": " .. table.concat(rows, " | "))
end

print()
if failures == 0 then
  print(string.format("all %d checks passed", checks))
  os.exit(0)
end
print(string.format("%d of %d checks FAILED", failures, checks))
os.exit(1)
