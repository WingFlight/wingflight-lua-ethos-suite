-- Behaviour check for the Servos page (MSP API 22.16: a servo is a servo).
--
-- Run it:
--     lua5.4 bin/servos_page/verify_servos_page.lua
--
-- What it drives, and why:
--   * The real app/pages/servos.lua, the real app/page_runtime.lua and the real
--     MSP servo-config module. The status and servo-config reads are recorded
--     and answered by the scenario; the write builder stays real, so the
--     command number and the payload are the ones the firmware would receive.
--   * The list: one tile per servo in use (MSP_STATUS servo_count, which is the
--     servos in use and no longer "PWM outputs + bus channels"), capped at the
--     firmware's 24, and nothing else. The page does not offer the PWM update
--     rate, and reads only the status to build the list.
--   * A save from a tile: one MSP_SET_SERVO_CONFIGURATION (212) carrying the
--     tile's own index and the seven-field record, 15 bytes. There is one index
--     space now, so no MSP_SET_SERVO_CONFIG (124) and no offset.
--
-- This replaces bin/pwm_servo_write, which pinned the PWM page listing only the
-- PWM outputs and writing them raw: the split it guarded no longer exists.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  local last = 0
  for i = 1, #path do
    local ch = path:sub(i, i)
    if ch == "/" or ch == string.char(92) then last = i end
  end
  if last == 0 then return "." end
  return path:sub(1, last - 1)
end

local ROOT = scriptDir() .. "/../.."
local SUITE = ROOT .. "/src/wfsuite"

local function resolvePath(name)
  local f = io.open(name, "r")
  if f then f:close() return name end
  return SUITE .. "/" .. name
end

local realLoadfile = loadfile
loadfile = function(path, mode, env)
  if type(path) == "string" then path = resolvePath(path) end
  if env ~= nil then return realLoadfile(path, mode, env)
  elseif mode ~= nil then return realLoadfile(path, mode)
  else return realLoadfile(path) end
end

local function requireModule(name)
  local key = "wfsuite." .. name:gsub("%.lua$", ""):gsub("/", ".")
  local cached = package.loaded[key]
  if cached ~= nil then return cached end
  local chunk, err = loadfile(resolvePath(name))
  if not chunk then error(err) end
  local ok, result = pcall(chunk)
  if not ok then error(result) end
  package.loaded[key] = (result == nil) and true or result
  return package.loaded[key]
end
package.loaded["wfsuite.lib.require"] = requireModule

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then print(string.format("  ok    %s", label))
  else
    failures = failures + 1
    print(string.format("  FAIL  %s", label))
    if detail then print("        " .. tostring(detail)) end
  end
end

local function anything()
  local t = {}
  return setmetatable(t, {
    __index = function() return function() return anything() end end,
    __call = function() return anything() end,
  })
end

local function bytes(payload)
  return table.concat(payload or {}, ",")
end

-- ---------------------------------------------------------------------------
-- Stubs
-- ---------------------------------------------------------------------------

lcd = anything()
lcd.getWindowSize = function() return 800, 480 end
-- The path stands in for the mask, so a tile's icon can be read back.
lcd.loadMask = function(path) return path end
system = anything()

local dialogs = {}
local tiles = {}
form = anything()
form.clear = function() end
form.invalidate = function() end
form.height = function() return 0 end
form.openDialog = function(opts) dialogs[#dialogs + 1] = opts end
form.addButton = function(_, _, opts)
  tiles[#tiles + 1] = opts
  return anything()
end
local lastHeaderOpts = nil
package.loaded["wfsuite.app.header"] = {
  build = function(_, opts) lastHeaderOpts = opts; return anything() end,
}
package.loaded["wfsuite.app.close_key"] = {shouldHandleClose = function() return true end}
package.loaded["wfsuite.app.progress_dialog"] = {
  SPEED = {DEFAULT = 1},
  open = function() return {value = function() end, close = function() end} end,
}
package.loaded["wfsuite.app.tile_grid"] = {
  metrics = function() return 3, 120, 90, 4, 0 end,
  fitLabel = function(text) return text end,
}
package.loaded["wfsuite.lib.memstats"] = {print = function() end}
package.loaded["wfsuite.lib.debug_log"] = anything()
package.loaded["wfsuite.lib.settings_store"] = {
  load = function() return {} end,
  saveConfirmEnabled = function() return false end,
  clone = function(t) return t end,
  save = function() return true end,
}

-- Status: a stub with a recorded read, answered by the scenario.
package.loaded["wfsuite.lib.msp_status"] = {
  buildReadMessage = function(onData, onError)
    return {kind = "statusRead", onData = onData, onError = onError}
  end,
}

-- Servo config: the real module. The reads are recorded for the scenario; the write
-- builder stays real, so the command and the payload are the firmware's.
do
  local servoConfig = requireModule("lib/msp_servo_config.lua")
  local realForIndex = servoConfig.forIndex
  servoConfig.forIndex = function(index)
    local servo = realForIndex(index)
    servo.buildReadMessage = function(onData, onError)
      return {kind = "servoRead", onData = onData, onError = onError}
    end
    return servo
  end
end

-- Keep the runtime of the open editor, so the scenario can mark its page dirty.
local runtimeRef = nil
do
  local fieldLayout = requireModule("app/field_layout.lua")
  local realBuildSingle = fieldLayout.buildSingle
  fieldLayout.buildSingle = function(runtime, ...)
    runtimeRef = runtime
    return realBuildSingle(runtime, ...)
  end
end

local sent = {}
local bus = requireModule("lib/bus.lua")
bus.subscribe("msp.request", function(m) sent[#sent + 1] = m end)

local page = requireModule("app/pages/servos.lua")

-- ---------------------------------------------------------------------------
-- Scenario driver
-- ---------------------------------------------------------------------------

local function servoFixture()
  return {mid = 1500, min = -600, max = 600, rneg = 500, rpos = 500, speed = 0, flags = 0}
end

-- Answers the recorded reads of the given kinds. fixtureFor(kind) returns the data,
-- or nil to refuse the read.
local function answerReads(kinds, fixtureFor)
  local answered = 0
  for _, m in ipairs(sent) do
    if kinds[m.kind] and not m.answered then
      m.answered = true
      answered = answered + 1
      local data = fixtureFor(m.kind)
      if data == nil then m.onError("refused") else m.onData(data) end
    end
  end
  return answered
end

local currentWake = nil
local function runWakeups(n)
  for _ = 1, n do if currentWake then currentWake() end end
end

local function countWrites(command)
  local n = 0
  for _, m in ipairs(sent) do
    if m.command == command and m.isWrite then n = n + 1 end
  end
  return n
end

-- Opens the page on a bench with the given servo count, then the list. Returns
-- the tiles and how many reads the page sent to build the list.
local function openList(servoCount)
  sent, tiles, dialogs = {}, {}, {}
  lastHeaderOpts, runtimeRef, currentWake = nil, nil, nil
  page.open({
    onBack = function() end,
    setWakeupHandler = function(fn) currentWake = fn end,
  })
  local reads = #sent
  answerReads({statusRead = true}, function()
    return {servo_count = servoCount}
  end)
  runWakeups(1)
  return tiles, reads
end

-- Presses tile k, lets its read complete, changes the page with `edit` and saves
-- it, as the Save button does. Returns the first write of `command` the page sent.
local function saveTile(k, readKind, fixture, command, edit)
  tiles[k].press()
  for _ = 1, 10 do
    if answerReads({[readKind] = true}, function() return fixture end) == 0 then break end
  end
  runWakeups(5)
  if not runtimeRef or not lastHeaderOpts or not lastHeaderOpts.onSave then
    return nil, "the editor did not open"
  end
  if edit then edit(runtimeRef.data) end
  runtimeRef:setDirty(true)
  local before = #sent
  local ok, err = pcall(function() lastHeaderOpts.onSave() end)
  if not ok then return nil, "Save raised: " .. tostring(err) end
  for i = before + 1, #sent do
    local m = sent[i]
    if m.isWrite and m.command == command then return m, nil end
  end
  return nil, "Save sent no cmd " .. command .. " write"
end

-- ---------------------------------------------------------------------------
-- The list and a servo save
-- ---------------------------------------------------------------------------

local SCENARIOS = {
  {
    label = "four PWM outputs, no bus output: 4 servos in use",
    servoCount = 4, expectServos = 4, tile = 2, expectIndex = 1,
  },
  {
    label = "four PWM outputs and a 24-channel F.Bus output: 24 servos in use",
    servoCount = 24, expectServos = 24, tile = 24, expectIndex = 23,
  },
  {
    label = "no PWM outputs, a 16-channel bus output: 18 servos in use",
    servoCount = 18, expectServos = 18, tile = 9, expectIndex = 8,
  },
  {
    label = "a servo count past the firmware's 24 is not trusted",
    servoCount = 40, expectServos = 24, tile = 1, expectIndex = 0,
  },
}

for _, s in ipairs(SCENARIOS) do
  print(s.label)
  local _, reads = openList(s.servoCount)
  local servoTiles = #tiles
  check("the list is built from the status read alone", reads == 1, "reads sent: " .. reads)
  check("the list shows every servo in use, and no other tile",
    servoTiles == s.expectServos,
    "tiles shown: " .. servoTiles .. ", expected " .. s.expectServos)
  if servoTiles >= s.tile then
    local write, why = saveTile(s.tile, "servoRead", servoFixture(), 212)
    check("the save completes", write ~= nil, why)
    check("the servo is written once, with MSP_SET_SERVO_CONFIGURATION (212) and never 124",
      countWrites(212) == 1 and countWrites(124) == 0,
      "cmd 212 writes: " .. countWrites(212) .. ", cmd 124 writes: " .. countWrites(124))
    local payload = write and write.payload
    check("the index in the payload is the tile's own servo, with no offset",
      payload ~= nil and payload[1] == s.expectIndex,
      "payload[1] = " .. tostring(payload and payload[1]) .. ", expected " .. s.expectIndex)
    check("the payload is the index and the seven-field record, 15 bytes",
      payload ~= nil and bytes(payload) == s.expectIndex .. ",220,5,168,253,88,2,244,1,244,1,0,0,0,0",
      bytes(payload))
  else
    check("the save completes", false, "tile " .. s.tile .. " does not exist")
  end
end

print("tile icons")
openList(24)
check("servos 1 to 16 have their numbered icon",
  tiles[1].icon == "app/gfx/servo1.png" and tiles[16].icon == "app/gfx/servo16.png",
  tostring(tiles[1].icon) .. " / " .. tostring(tiles[16].icon))
check("servos 17 to 24 share an icon that exists",
  tiles[17].icon == "app/gfx/servos.png" and tiles[24].icon == "app/gfx/servos.png",
  tostring(tiles[17].icon) .. " / " .. tostring(tiles[24].icon))
do
  local missing = {}
  for i = 1, #tiles do
    local f = io.open(SUITE .. "/" .. tiles[i].icon, "rb")
    if f then f:close() else missing[#missing + 1] = tiles[i].icon end
  end
  check("every tile's icon file is in the suite", #missing == 0, table.concat(missing, ", "))
end

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
