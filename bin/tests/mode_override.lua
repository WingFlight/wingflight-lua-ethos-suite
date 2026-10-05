-- Run from the repository root with Lua 5.3+: lua bin/tests/mode_override.lua
-- Checks the timed bench overrides of wingflight-firmware API 22.14:
-- lib/msp_mode_override.lua and lib/msp_servo_override.lua against the
-- firmware's wire format (src/main/msp/msp.c), and lib/override_keepalive.lua
-- re-sending held overrides until they are released, only on 22.14+ and only
-- while connected.

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

local sent = {}
local sessionHandler
local stubs = {
  ["lib/bus.lua"] = {
    publish = function(event, message)
      if event == "msp.request" then sent[#sent + 1] = message end
    end,
    subscribe = function(event, fn)
      if event == "session.update" then sessionHandler = fn end
      return fn
    end,
    unsubscribe = function() end,
  },
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

local clock = 100
os.clock = function() return clock end

local requireModule = package.loaded["wfsuite.lib.require"]
local keepalive = requireModule("lib/override_keepalive.lua")
local modeOverride = requireModule("lib/msp_mode_override.lua")
local servoOverride = requireModule("lib/msp_servo_override.lua")

local function bytes(t) return table.concat(t, ",") end
local function last() return sent[#sent] end
local function lastOf(command)
  for i = #sent, 1, -1 do
    if sent[i].command == command then return sent[i] end
  end
end
local function session(minor, connected)
  sessionHandler({connected = connected ~= false, apiVersionMajor = 22, apiVersionMinor = minor})
end

-- Wire format
local p = modeOverride.encode({modeOverride.BOX_PASSTHROUGH}, 3000)
check("mode write: U16 timeout, U8 count, ids", bytes(p) == "184,11,1,12", bytes(p))
p = modeOverride.encode({}, 10000)
check("mode write: empty list holds the setup state", bytes(p) == "16,39,0", bytes(p))
p = modeOverride.encode({}, 0)
check("mode write: timeout 0 clears", bytes(p) == "0,0,0", bytes(p))
local msg = modeOverride.buildWriteMessage({modeOverride.BOX_ANGLE}, 500)
check("mode write is an MSPv2 write", msg.command == 0x5F1B and msg.isWrite == true)
local data = modeOverride.decode({0x10, 0x27, 2, 1, 12, offset = 4})
check("mode read: decodes from the start of the reply",
  data.remainingMs == 10000 and #data.ids == 2 and data.ids[1] == 1 and data.ids[2] == 12)
msg = servoOverride.buildWriteMessage(2, 0, nil, nil, 10000)
check("servo write: optional trailing timeout", bytes(msg.payload) == "2,0,0,16,39", bytes(msg.payload))
msg = servoOverride.buildWriteMessage(2, 0)
check("servo write: untimed is unchanged", bytes(msg.payload) == "2,0,0", bytes(msg.payload))
msg = servoOverride.buildWriteAllMessage(0, nil, nil, 10000)
check("servo write all: optional trailing timeout", bytes(msg.payload) == "0,0,16,39", bytes(msg.payload))

-- Older firmware: untimed, no keepalive, no forced modes
session(13)
sent = {}
servoOverride.holdAll(servoOverride.OVERRIDE_CENTER)
check("22.13: servo override sent untimed", #sent == 1 and bytes(sent[1].payload) == "0,0")
check("22.13: modes can't be forced", modeOverride.hold({modeOverride.BOX_PASSTHROUGH}) == false and #sent == 1)
clock = 110
keepalive.tick(clock)
check("22.13: nothing re-sent", #sent == 1)
servoOverride.releaseAll()

-- 22.14: held overrides are re-sent until released
session(14)
sent = {}
local refused
check("22.14: mode hold accepted", modeOverride.hold({modeOverride.BOX_PASSTHROUGH}, function(r) refused = r end))
check("mode hold sends at once", #sent == 1 and bytes(sent[1].payload) == "16,39,1,12")
servoOverride.hold(3, servoOverride.OVERRIDE_CENTER)
check("servo hold sends timed", #sent == 2 and bytes(sent[2].payload) == "3,0,0,16,39", bytes(sent[2].payload))

clock = 112
keepalive.tick(clock)
check("no refresh before the interval", #sent == 2)
clock = 113
keepalive.tick(clock)
check("both refreshed at the interval", #sent == 4)

session(14, false)
clock = 120
keepalive.tick(clock)
check("nothing sent while disconnected", #sent == 4)
session(14)

lastOf(modeOverride.WRITE_COMMAND).errorHandler("max_retries")
check("a link error keeps the holds", modeOverride.isHeld() and refused == nil)

modeOverride.release()
check("mode release clears on the FC", bytes(last().payload) == "0,0,0" and not modeOverride.isHeld())
servoOverride.releaseAll()
check("servo release all sends OFF untimed", bytes(last().payload) == "209,7")
local before = #sent
clock = 200
keepalive.tick(clock)
check("nothing re-sent after release", #sent == before)

modeOverride.hold({modeOverride.BOX_ANGLE}, function(r) refused = r end)
lastOf(modeOverride.WRITE_COMMAND).errorHandler(true)
check("an FC refusal drops the mode hold and reports it", not modeOverride.isHeld() and refused == true)
before = #sent
clock = 300
keepalive.tick(clock)
check("a refused hold stops refreshing", #sent == before)

modeOverride.hold({})
check("an empty hold keeps the setup state with nothing forced",
  modeOverride.isHeld() and bytes(lastOf(modeOverride.WRITE_COMMAND).payload) == "16,39,0")
modeOverride.release()

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
