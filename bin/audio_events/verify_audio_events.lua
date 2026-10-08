-- Behaviour check for the Settings -> Audio -> Events split.
--
-- Ported from rotorflight-lua-ethos-suite PR #2508 (issue #2308).
--
-- Run it:
--     lua bin/audio_events/verify_audio_events.lua
--
-- What it drives, and why:
--   * The real app/pages/settings_audio_events_*.lua pages and their shared
--     helper, loaded under an Ethos form stub, opened exactly the way
--     app/menu_container.lua opens them: page.open(opts) with the four
--     set*Handler setters, and the cleanup handler fired the way
--     app/tool.lua:close() fires it.
--   * The real lib/settings_store.lua is read for its DEFAULTS.events key
--     list, so "every event is still configurable" is checked against the
--     store itself rather than against a list this file also wrote.
--
-- Why a harness at all: nothing in the build or the package step can see a
-- page that stopped offering a setting. The failure mode that matters here is
-- quiet -- a key that no page edits any more simply loses its toggle, and the
-- pilot finds out in the air. So the load-bearing check is the coverage one:
-- every key in DEFAULTS.events is edited by exactly one category page.
--
-- Which cases go RED on a bad split:
--   1. a key is edited by no page                     -> case 1
--   2. a key is edited by two pages                   -> case 1
--   3. a page edits a key the store never had          -> case 1
--   4. a page builds another category's fields         -> case 2
--   5. a page's fields do not reach the store on save -> case 4
--   6. a page marks itself dirty / never re-arms Save -> case 4
--   7. a page keeps writing after it was left         -> case 3
--   8. the old monolithic page is still reachable     -> case 5
--   9. a menu entry points at a page that is not there -> case 5
--  10. an unassigned number field returns out of bounds -> case 6

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local SUITE = (ROOT .. "/src/wfsuite"):gsub("\\", "/")

local checks, failures = 0, 0

local out = print

local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    out(string.format("  ok    %s", label))
  else
    failures = failures + 1
    out(string.format("  FAIL  %s", label))
    if detail then out("        " .. tostring(detail)) end
  end
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local content = f:read("*a")
  f:close()
  return (content:gsub("\r\n", "\n"))
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- ── the categories, and the keys each one edits ─────────────────────────────

local CATEGORIES = {
  {key = "voltage",      file = "settings_audio_events_voltage.lua"},
  {key = "esc",          file = "settings_audio_events_esc.lua"},
  {key = "fuel",         file = "settings_audio_events_fuel.lua"},
  {key = "state",        file = "settings_audio_events_state.lua"},
  {key = "status",       file = "settings_audio_events_status.lua"},
  {key = "announcement", file = "settings_audio_events_announcement.lua"},
}

local function readDefaultsEventKeys()
  local src = readFile(SUITE .. "/lib/settings_store.lua")
  local block = src:match("events%s*=%s*{(.-)\n  },\n")
  if not block then return nil, "no events block found in lib/settings_store.lua" end
  local keys, seen, raw = {}, {}, 0
  for name in block:gmatch("\n%s+([%a_][%w_]*)%s*=") do
    raw = raw + 1
    if not seen[name] then
      seen[name] = true
      keys[#keys + 1] = name
    end
  end
  table.sort(keys)
  return keys, nil, raw
end

local function readPageFields(file)
  local src = readFile(SUITE .. "/app/pages/" .. file)
  local declared = {}
  for label, key in src:gmatch('"(@i18n%b()@)"%s*,%s*"([%w_]+)"') do
    declared[#declared + 1] = {label = label, key = key}
  end
  return declared, src
end

local function countAddCallSites(src)
  local n = 0
  for _ in src:gmatch("%f[%a]add[%a]+%s*%(") do n = n + 1 end
  return n
end

-- ── Ethos environment ──────────────────────────────────────────────────────

local SUITE_PREFIX = SUITE .. "/"
package.path = SUITE_PREFIX .. "?.lua;" .. package.path
_G.PREFIX = SUITE_PREFIX

local realLoadfile = loadfile

_G.loadfile = function(path, ...)
  if type(path) == "string" and path:match("%.lua$") then
    local absolute = path:sub(1, 1) == "/" and path or (SUITE_PREFIX .. path)
    return realLoadfile(absolute, ...)
  end
  return realLoadfile(path, ...)
end

_G.package = package
_G.package.loaded = package.loaded
_G.os = os
_G.math = math
_G.string = string
_G.table = table

_G.print = function() end
_G.lcd = {
  getWindowSize = function() return 480, 320 end,
  getTextSize = function(t) return #t, 12 end,
  drawRectangle = function() end,
  drawText = function() end,
  drawBitmap = function() end,
  setColor = function() end,
  font = function() return 1 end,
  color = function() end,
}
_G.model = { get = function() return 0 end, name = function() return "stub" end }
_G.system = {
  getVersion = function() return { simulation = false, radio = { name = "stub" } } end,
  getMemoryUsage = function() return {} end,
  formatBytes = function(n) return tostring(n) end,
}
_G.radio = { getActiveProfileId = function() return 1 end, getProfileId = function() return 1 end }

_G.TIME_LEFT = 1
_G.TEXT_LEFT = 2
_G.LEFT = 3
_G.CENTERED = 4
_G.RIGHT = 5
_G.TOP_LEFT = 6
_G.FONT_XS = 10
_G.FONT_S = 20
_G.FONT_M = 30
_G.FONT_L = 40
_G.FONT_XL = 50

_G.EVT_CLOSE = 0x01
_G.EVT_KEY = 0x02
_G.EVT_EXIT_BREAK = 0x03
_G.EVT_KEY_DOWN_BREAK = 0x04
_G.KEY_ENTER_LONG = 0x05
_G.KEY_RTN_BREAK = 0x06
_G.KEY_EXIT_BREAK = 0x07
_G.KEY_ENTER_BREAK = 0x08

-- ── Ethos form stub ─────────────────────────────────────────────────────────

local fields = {}
local lines = {}
local dialogs = {}
local cleared = 0

local function slotsStub(count)
  local out = {}
  for i = 1, (count or 6) do
    out[i] = {x = (i - 1) * 80, y = 0, w = 80, h = 30}
  end
  return out
end

local function widget(kind, label, get, set)
  local w = {kind = kind, label = label, get = get, set = set, enabled = nil}
  w.focus = function() end
  w.show = function() end
  w.hide = function() end
  w.enable = function(_, on) w.enabled = on end
  w.suffix = function(_, s) w.suffixText = s end
  w.decimals = function(_, d) w.decimalsCount = d end
  return w
end

local function addField(kind, line, get, set, extra)
  local w = widget(kind, line.label, get, set)
  for k, v in pairs(extra or {}) do w[k] = v end
  fields[#fields + 1] = w
  return w
end

_G.form = {
  addLine = function(label)
    local line = {label = label, index = #lines + 1}
    lines[#lines + 1] = line
    return line
  end,
  clear = function()
    fields = {}
    lines = {}
    cleared = cleared + 1
  end,
  addBooleanField = function(line, _, get, set) return addField("bool", line, get, set) end,
  addNumberField = function(line, _, min, max, get, set)
    return addField("number", line, get, set, {min = min, max = max})
  end,
  addChoiceField = function(line, _, choices, get, set)
    return addField("choice", line, get, set, {choices = choices})
  end,
  addStaticText = function() return widget("text") end,
  addButton = function() return widget("button") end,
  addTextButton = function() return widget("textbutton") end,
  height = function() return 320 end,
  getFieldSlots = function(_, hints) return slotsStub(type(hints) == "table" and #hints or 6) end,
  openDialog = function(args)
    dialogs[#dialogs + 1] = args
    return {close = function() end}
  end,
}

-- ── header stub ─────────────────────────────────────────────────────────────

local headerOpts = nil
local headerHandle = nil

local function headerStub()
  return {
    build = function(_, opts)
      headerOpts = opts
      headerHandle = {
        focusMenu = function() end,
        focusSave = function() end,
        focusReload = function() end,
        focusTool = function() end,
        setTitle = function() end,
        setSaveEnabled = function(on) headerHandle.saveEnabled = on end,
        setReloadEnabled = function() end,
      }
      return headerHandle
    end,
  }
end

-- ── settings store stub ─────────────────────────────────────────────────────

local DEFAULT_EVENTS = {}

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = deepCopy(v) end
  return out
end

local function deepSame(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deepSame(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local saves = 0
local published = {}
local snapshot = {events = {}}
local loadedSnapshots = {}

local function newStore()
  saves = 0
  published = {}
  snapshot = {events = deepCopy(DEFAULT_EVENTS)}
  loadedSnapshots = {}
  dialogs = {}
  headerOpts, headerHandle = nil, nil
end

package.loaded["wfsuite.lib.settings_store"] = {
  load = function()
    local t = deepCopy(snapshot)
    loadedSnapshots[#loadedSnapshots + 1] = t
    return t
  end,
  clone = function(t) return deepCopy(t) end,
  same = deepSame,
  save = function(t)
    saves = saves + 1
    snapshot = deepCopy(t)
  end,
}
package.loaded["wfsuite.lib.bus"] = {
  subscribe = function() return function() end end,
  unsubscribe = function() end,
  publish = function(topic, message)
    if topic == "settings.update" then published[#published + 1] = message end
  end,
}
package.loaded["wfsuite.app.header"] = headerStub()

-- ── helpers ────────────────────────────────────────────────────────────────

local function makeOpts()
  local installed = {}
  local opts = {backs = 0, installed = installed}
  local function setter(name)
    return function(handler) installed[name] = handler end
  end
  opts.setEventHandler = setter("setEventHandler")
  opts.setWakeupHandler = setter("setWakeupHandler")
  opts.setPaintHandler = setter("setPaintHandler")
  opts.setCleanupHandler = setter("setCleanupHandler")
  opts.onBack = function() opts.backs = opts.backs + 1 end
  return opts
end

local function openCategory(category, fresh)
  if fresh ~= false then newStore() end
  local page = dofile(SUITE .. "/app/pages/" .. category.file)
  local opts = makeOpts()
  page.open(opts)
  return opts, fields, headerHandle, headerOpts
end

local function storedEvents()
  return deepCopy(snapshot).events
end

-- ── setup: one key list, shared by every case ───────────────────────────────

local DEFAULT_KEYS, DEFAULT_ERR, DEFAULT_RAW = readDefaultsEventKeys()

out("Settings -> Audio -> Events category pages")
out("")
if DEFAULT_KEYS then
  for _, k in ipairs(DEFAULT_KEYS) do DEFAULT_EVENTS[k] = 0 end
end

-- ── case 1: coverage ───────────────────────────────────────────────────────

out("case 1: every settings.events key is edited by exactly one category page")
do
  check("the store's events block could be read", DEFAULT_KEYS ~= nil, DEFAULT_ERR)

  if DEFAULT_KEYS then
    out("        DEFAULTS.events has " .. #DEFAULT_KEYS .. " keys")
    check("every assignment in the store's events block was read",
      DEFAULT_RAW == #DEFAULT_KEYS,
      DEFAULT_RAW .. " assignments, " .. #DEFAULT_KEYS ..
      " distinct keys -- a half-read block would understate the key count")

    local editedBy = {}
    local scanComplete = true

    for _, category in ipairs(CATEGORIES) do
      local declared, src = readPageFields(category.file)
      local callSites = countAddCallSites(src)
      if #declared ~= callSites then
        scanComplete = false
        out(string.format("        %s: %d add* call sites but %d fields parsed",
          category.file, callSites, #declared))
      end
      for _, d in ipairs(declared) do
        editedBy[d.key] = editedBy[d.key] or {}
        table.insert(editedBy[d.key], category.key)
      end
    end

    check("every add* call site was parsed, so the coverage number is complete",
      scanComplete, "a missed call site would understate coverage and let a dropped key pass")

    local missing, doubled, extra = {}, {}, {}
    for _, k in ipairs(DEFAULT_KEYS) do
      local owners = editedBy[k]
      if owners == nil or #owners == 0 then
        missing[#missing + 1] = k
      elseif #owners > 1 then
        doubled[#doubled + 1] = k .. " (" .. table.concat(owners, ", ") .. ")"
      end
    end
    for _, k in ipairs(sortedKeys(editedBy)) do
      if DEFAULT_EVENTS[k] == nil then
        extra[#extra + 1] = k .. " (" .. table.concat(editedBy[k], ", ") .. ")"
      end
    end

    check(string.format("no key lost its toggle (%d keys, all covered)", #DEFAULT_KEYS),
      #missing == 0, table.concat(missing, ", "))
    check("no key is offered on two pages", #doubled == 0, table.concat(doubled, ", "))
    check("no page edits a key the store does not have", #extra == 0, table.concat(extra, ", "))
  end
end

-- ── case 2: one category per open ──────────────────────────────────────────

out("")
out("case 2: a page builds only its own fields")
do
  local perPage = {}
  local total = 0
  local widths = {}

  for _, category in ipairs(CATEGORIES) do
    local _, built = openCategory(category)
    local declared = readPageFields(category.file)
    check(string.format("%s: %d fields built, %d fields declared", category.file, #built, #declared),
      #built == #declared,
      "a page building more than it declares is building another category's fields")
    perPage[#perPage + 1] = #built
    widths[#widths + 1] = #built
    total = total + #built
  end

  if DEFAULT_KEYS then
    check(string.format("the category pages together build exactly the store's key count (%d)", total),
      total == #DEFAULT_KEYS, "the split must neither drop a field nor duplicate one")
    local widest = 0
    for _, n in ipairs(widths) do if n > widest then widest = n end end
    check("no single page builds the whole set any more (widest: " .. widest .. ")",
      widest < #DEFAULT_KEYS, "per page: " .. table.concat(widths, ", "))
  end
end

-- ── case 3: dispose drops the snapshot ─────────────────────────────────────

out("")
out("case 3: a page that has been left keeps nothing and writes nothing")
do
  for _, category in ipairs(CATEGORIES) do
    local opts, built = openCategory(category)

    local handler = opts.installed.setCleanupHandler
    check(string.format("%s: installed a cleanup handler", category.file), handler ~= nil)
    local ok, err = true, nil
    if handler then ok, err = pcall(handler) end
    check(string.format("%s: cleanup did not raise", category.file), ok, err)
    check(string.format("%s: cleanup released the cleanup handler", category.file),
      opts.installed.setCleanupHandler == nil,
      "the tool would keep calling into a disposed page")

    local pristine = {}
    for i, snap in ipairs(loadedSnapshots) do pristine[i] = deepCopy(snap) end
    local before = storedEvents()

    local raisedCount = 0
    for _, w in ipairs(built) do
      local probe = (w.kind == "bool") and (not (w.get() == true)) or 6
      if not pcall(w.set, probe) then raisedCount = raisedCount + 1 end
    end
    check(string.format("%s: no field raised after teardown", category.file), raisedCount == 0,
      raisedCount .. " field(s) raised")

    local mutated = {}
    for i, snap in ipairs(loadedSnapshots) do
      if not deepSame(pristine[i], snap) then mutated[#mutated + 1] = "snapshot " .. i end
    end
    check(string.format("%s: no field wrote into a snapshot the page had let go of", category.file),
      #mutated == 0, table.concat(mutated, ", "))
    check(string.format("%s: the settings store is untouched", category.file),
      deepSame(before, storedEvents()))
  end
end

-- ── case 4: the save round trip, field by field ────────────────────────────

out("")
out("case 4: every field a page builds reaches the store on save")
do
  for _, category in ipairs(CATEGORIES) do
    local opts, built, handle, hops = openCategory(category)
    local declared = readPageFields(category.file)

    check(string.format("%s: a freshly opened page is not dirty", category.file),
      handle.saveEnabled == false, "saveEnabled=" .. tostring(handle.saveEnabled))

    local aligned = #built == #declared
    for i = 1, math.min(#built, #declared) do
      if built[i].label ~= declared[i].label then
        aligned = false
        out(string.format("        %s: field %d is labelled %s but its source line says %s",
          category.file, i, tostring(built[i].label), tostring(declared[i].label)))
      end
    end
    check(string.format("%s: every field matches the source line that declares it", category.file),
      aligned, string.format("%d built, %d declared", #built, #declared))

    local probes = {}
    for i, w in ipairs(built) do
      local probe
      if w.kind == "bool" then
        probe = not (w.get() == true)
      elseif w.kind == "number" then
        probe = 6
      else
        probe = w.choices[#w.choices][2]
      end
      probes[i] = probe
      w.set(probe)
    end

    check(string.format("%s: editing every field arms Save", category.file),
      handle.saveEnabled == true, "saveEnabled=" .. tostring(handle.saveEnabled))

    hops.onSave()
    local modal = dialogs[#dialogs]
    check(string.format("%s: a dirty save asks first", category.file), modal ~= nil,
      "saving straight through would skip the confirmation the pilot relies on")
    if modal then
      modal.buttons[1].action()
      check(string.format("%s: OK wrote the settings store once", category.file), saves == 1,
        "saves=" .. saves)
      check(string.format("%s: settings.update was published once", category.file), #published == 1,
        "published=" .. #published)
      check(string.format("%s: Save is disarmed again after saving", category.file),
        handle.saveEnabled == false, "saveEnabled=" .. tostring(handle.saveEnabled))
    end

    openCategory(category, false)
    local reopened = fields
    local wrong = {}
    for i = 1, math.min(#reopened, #declared) do
      local got = reopened[i].get()
      if got ~= probes[i] then
        wrong[#wrong + 1] = string.format("%s reads %s (typed %s)",
          declared[i].key, tostring(got), tostring(probes[i]))
      end
    end
    check(string.format("%s: all %d fields read back what was typed, after re-opening",
      category.file, #declared), #wrong == 0, table.concat(wrong, ", "))

    hops.onBack()
    check(string.format("%s: going back pops the screen once", category.file), opts.backs == 1,
      "backs=" .. opts.backs)
  end
end

-- ── case 5: the menu reaches six real pages ────────────────────────────────

out("")
out("case 5: the menu in tool.lua reaches exactly these category pages")
do
  local tool = readFile(SUITE .. "/app/tool.lua")

  check("the monolithic page is gone from the menu",
    not tool:find('script = "app/pages/settings_audio_events.lua"', 1, true),
    "settings_audio_events.lua as a menu entry would be a second copy of every event")
  check("the monolithic page file is gone from the tree",
    not fileExists(SUITE .. "/app/pages/settings_audio_events.lua"),
    "a stale page file is what the next rename would silently resurrect")
  check("the Events tile is a menu now",
    tool:find('menuId = "settings_audio_events_menu"', 1, true) ~= nil)

  local block = tool:match("settings_audio_events_menu%s*=%s*{(.-)\n  },\n")
  check("settings_audio_events_menu is declared", block ~= nil)
  if block then
    local scripts = {}
    for s in block:gmatch('script = "([^"]+)"') do scripts[#scripts + 1] = s end
    check(string.format("the menu lists %d entries", #CATEGORIES), #scripts == #CATEGORIES,
      "found " .. #scripts .. " script entries")

    local reachable, orphans = {}, {}
    for i, category in ipairs(CATEGORIES) do
      local expected = "app/pages/" .. category.file
      check(category.file .. " is menu slot " .. i, scripts[i] == expected,
        "slot " .. i .. " holds " .. tostring(scripts[i]))
      check(category.file .. " exists", fileExists(SUITE .. "/" .. expected),
        "menu entry " .. expected .. " points at nothing")
      reachable[expected] = true
    end
    for _, category in ipairs(CATEGORIES) do
      local p = "app/pages/" .. category.file
      if not reachable[p] then orphans[#orphans + 1] = category.file end
    end
    check("no category page is orphaned", #orphans == 0, table.concat(orphans, ", "))
  end
end

-- ── case 6: unassigned number fields return within bounds ──────────────────

out("")
out("case 6: unassigned number fields return within declared bounds")
do
  snapshot = {events = {}}
  for _, category in ipairs(CATEGORIES) do
    local _, built = openCategory(category, false)
    for _, w in ipairs(built) do
      if w.kind == "number" then
        local got = w.get()
        check(string.format("%s: '%s' default is within [%s, %s] (got %s)",
          category.file, tostring(w.label), tostring(w.min), tostring(w.max), tostring(got)),
          got ~= nil and got >= w.min and got <= w.max,
          string.format("got %s outside [%s, %s]", tostring(got), tostring(w.min), tostring(w.max)))
      end
    end
  end
end

out("")
out(string.rep("-", 60))
out(string.format("checks: %d   failures: %d", checks, failures))
out("form.clear() calls: " .. cleared)
if failures > 0 then
  out("")
  out("FAILED")
  os.exit(1)
end
out("ALL CHECKS PASSED")
