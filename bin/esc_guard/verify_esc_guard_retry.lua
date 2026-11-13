-- Behaviour check for the retry behaviour of the ESC protocol menu guard.
-- Ported from rotorflight-lua-ethos-suite#2422 (issue #2387 there).
--
-- Run it:
--     lua5.4 bin/esc_guard/verify_esc_guard_retry.lua
--
-- What it drives, and why:
--   * The real src/wfsuite/app/esc_protocol_guard.lua, together with the
--     real lib/msp_esc_sensor_config.lua, so the decode path is the
--     production one. Only the bus and os.clock() are stubbed, which lets
--     the sequence be stepped instead of waited out.
--   * The defect under test is a STATE, not a call: `attempted` stayed set
--     after a timeout or a bus error, and only open() cleared it. One
--     transient moment -- FC mid-reboot, queue momentarily full, link dropped
--     and back -- greyed out all ten tiles in esc_forward_menu until the pilot
--     left the section and came back.
--   * app/servo_bus_guard.lua had the same latch and was covered here
--     (cases 8, 9 and 11, and half of 13) until MSP API 22.16 made a servo a
--     servo: there is one Servos page now, nothing to gate on a bus output,
--     and that guard is gone. The case numbers are kept.
--
-- Cases, each against a false expectation:
--   1. A successful read latches -- 20 further ticks issue no second request.
--   2. Timeout, then a retry after the backoff, then success enables the tile.
--   3. Bus error, then a retry after the backoff, then success enables the tile.
--   4. No retry storm: nothing inside the backoff window, exactly one after it.
--   5. Protocol 0 ("NONE") counts as answered and is not retried.
--   6. open() breaks the backoff and reads immediately.
--   7. A late reply from a superseded request changes nothing.
--  10. esc_protocol_guard: a late reply after timeout enables the tile and
--      prevents a second request/glitch when the backoff expires.
--  12. esc_protocol_guard: link loss resets state and invalidates pending token;
--      reconnect triggers an immediate read.
--  13. Link loss during the backoff window clears nextAttemptAt so reconnect
--      does not wait out the remaining backoff.
--  14. An in-flight request aborted by link loss does not apply late reply.
--
-- Cases 2 and 3 must go RED against the pre-change file -- there
-- `attempted` stays set and the second attempt never happens.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local arg1 = ...
local ROOT = (arg1 or (scriptDir() .. "/../..")):gsub("\\", "/")
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

-- ── Clock ───────────────────────────────────────────────────────────────────
-- The guard measures its deadlines with os.clock(). For a reproducible test the
-- clock is set here rather than waited on.
local CLOCK = 1000.0
_G.os.clock = function() return CLOCK end
local function advance(seconds) CLOCK = CLOCK + seconds end

-- ── Bus stub ────────────────────────────────────────────────────────────────
-- Collects the MSP requests. Replies are delivered through processReply /
-- errorHandler of the request in question, the way the MSP stack would.
local requests = {}

local busStub = {
  publish = function(topic, message)
    if topic ~= "msp.request" then return end
    requests[#requests + 1] = message
  end,
}

-- ── Ethos and suite environment ─────────────────────────────────────────────
_G.system = {
  getVersion = function() return { simulation = false, radio = { name = "stub" } } end,
}

package.path = SUITE .. "/?.lua;" .. package.path

-- The suite resolves its module paths the way tool.lua:3 does:
--   package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
-- and loadfile("lib/bus.lua") from inside that. Both are paths WITHOUT a
-- directory part. A prefix on loadfile gives this harness the same route.
local realLoadfile = loadfile
local SUITE_PREFIX = SUITE .. "/"
_G.loadfile = function(path, ...)
  if type(path) == "string" and path:match("%.lua$") then
    local absolute = (path:sub(1, 1) == "/" or path:match("^%a:")) and path or (SUITE_PREFIX .. path)
    return realLoadfile(absolute, ...)
  end
  return realLoadfile(path, ...)
end

-- The real require replacement, except that the bus counts instead of sending.
-- Everything else -- msp_esc_sensor_config, mspcodec -- is the real module, so
-- the decode path under test is the one that runs on the radio.
local requireStub = function(name)
  if name == "lib/bus.lua" then return busStub end
  return realLoadfile(SUITE_PREFIX .. name)()
end
package.loaded["wfsuite.lib.require"] = requireStub

local escSensorConfig = requireStub("lib/msp_esc_sensor_config.lua")
local esc_protocol_guard = realLoadfile(SUITE_PREFIX .. "app/esc_protocol_guard.lua", ...)()

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function requestCount() return #requests end

-- Builds the real payload of an ESC_SENSOR_CONFIG read and answers that request
-- with it, the way the FC would.
--
-- The request NUMBER is required and is not silently defaulted. A "reply to the
-- most recent request" helper would, against the pre-change file, re-answer the
-- first request -- whose token was still valid -- and light the tile up even
-- though no second request had been made. The test would have stayed green
-- with the defect present. This helper reports failure when that request does
-- not exist.
local function reply(number, protocol)
  local msg = requests[number]
  if not msg then return false end
  local field = escSensorConfig.encode({ protocol = protocol })
  local buf = {}
  for i = 1, #field do buf[i] = field[i] end
  buf.offset = 1
  msg.processReply(nil, buf)
  return true
end

local function busError(number)
  local msg = requests[number]
  if not msg then return false end
  msg.errorHandler()
  return true
end

local function newGuard(connected)
  requests = {}
  return esc_protocol_guard.new({
    canRequest = function() return connected ~= false end,
  })
end

-- Tiles from src/wfsuite/app/tool.lua's esc_forward_menu -- all of them carry an
-- escProtocolId.
local BLHELI = { escProtocolId = 1 }
local SCORPION = { escProtocolId = 4 }

local RETRY_INTERVAL = 5.0   -- must match RETRY_INTERVAL in esc_protocol_guard.lua
local REQUEST_TIMEOUT = 3.0  -- must match REQUEST_TIMEOUT in esc_protocol_guard.lua

-- ── case 1: a successful read latches ───────────────────────────────────────
local g = newGuard()
g.open()
check("case 1  open() reads exactly once", requestCount() == 1, "was " .. requestCount())
check("case 1  the first request can be answered", reply(1, 1) == true)
check("case 1  the matching tile is enabled", g.isEntryEnabled(BLHELI) == true)
check("case 1  a foreign tile stays disabled", g.isEntryEnabled(SCORPION) == false)
for _ = 1, 20 do
  advance(0.1)
  g.wakeup()
end
check("case 1  no second read after success", requestCount() == 1,
  "was " .. requestCount())

-- ── case 2: timeout, then success ───────────────────────────────────────────
g = newGuard()
g.open()
check("case 2  open() reads exactly once", requestCount() == 1)
advance(REQUEST_TIMEOUT + 0.1)
g.wakeup()                              -- deadline passed -> failure
check("case 2  no tile is enabled after the timeout", g.isEntryEnabled(BLHELI) == false)
for _ = 1, 10 do
  advance(0.2)
  g.wakeup()
end
check("case 2  nothing is sent inside the backoff window", requestCount() == 1,
  "was " .. requestCount())
advance(RETRY_INTERVAL)
g.wakeup()
check("case 2  a retry is issued after the backoff", requestCount() == 2,
  "was " .. requestCount())
check("case 2  the second request can be answered", reply(2, 1) == true)
check("case 2  the second attempt enables the tile", g.isEntryEnabled(BLHELI) == true)
check("case 2  two requests in total", requestCount() == 2, "was " .. requestCount())

-- ── case 3: bus error, then success ─────────────────────────────────────────
g = newGuard()
g.open()
check("case 3  the first request can be answered", busError(1) == true)
check("case 3  no tile is enabled after the bus error", g.isEntryEnabled(BLHELI) == false)
advance(RETRY_INTERVAL)
g.wakeup()
check("case 3  a retry is issued after the backoff", requestCount() == 2,
  "was " .. requestCount())
check("case 3  the second request can be answered", reply(2, 4) == true)
check("case 3  the second attempt enables the tile", g.isEntryEnabled(SCORPION) == true)

-- ── case 4: no retry storm ──────────────────────────────────────────────────
g = newGuard()
g.open()
busError(1)
for _ = 1, 50 do
  advance(0.09)                          -- 4.5 s, inside the window
  g.wakeup()
end
check("case 4  50 ticks inside the window issue no request", requestCount() == 1,
  "was " .. requestCount())
advance(RETRY_INTERVAL)
for _ = 1, 50 do
  g.wakeup()                             -- all in the same tick, no time passes
end
check("case 4  one request after the backoff is enough", requestCount() == 2,
  "was " .. requestCount())

-- ── case 5: protocol 0 is an answer, not a failure ──────────────────────────
g = newGuard()
g.open()
check("case 5  the first request can be answered", reply(1, 0) == true)
check("case 5  protocol 0 counts as read", requestCount() == 1)
check("case 5  with no ESCs every tile stays disabled", g.isEntryEnabled(BLHELI) == false)
for _ = 1, 20 do
  advance(0.5)
  g.wakeup()
end
check("case 5  protocol 0 is not read again", requestCount() == 1,
  "was " .. requestCount())

-- ── case 6: open() does not wait ────────────────────────────────────────────
g = newGuard()
g.open()
busError(1)
g.open()                                 -- pilot leaves the menu and comes back
check("case 6  open() breaks the backoff window", requestCount() == 2,
  "was " .. requestCount())
check("case 6  the second request can be answered", reply(2, 7) == true)
check("case 6  the tile is enabled immediately", g.isEntryEnabled({ escProtocolId = 7 }) == true)

-- ── case 7: a late reply from a superseded request ──────────────────────────
g = newGuard()
g.open()
busError(1)                              -- the first request fails
advance(RETRY_INTERVAL)
g.wakeup()
check("case 7  there is a second, newer request", requestCount() == 2,
  "was " .. requestCount())
-- The first request replies late, with a still-valid token.
check("case 7  the late reply can be delivered", reply(1, 1) == true)
check("case 7  the late reply enables nothing", g.isEntryEnabled(BLHELI) == false)
check("case 7  the second request can be answered", reply(2, 1) == true)
check("case 7  the current reply enables the tile", g.isEntryEnabled(BLHELI) == true)

-- ── case 10: esc guard, late reply after timeout prevents retry and UI glitch ──
g = newGuard()
g.open()
check("case 10 open() reads exactly once", requestCount() == 1)
advance(REQUEST_TIMEOUT + 0.1)
g.wakeup() -- deadline passed -> timeout fail()
check("case 10 tile disabled after timeout", g.isEntryEnabled(BLHELI) == false)
advance(0.4)
check("case 10 late reply arrives before retry", reply(1, 1) == true)
check("case 10 late reply enables tile", g.isEntryEnabled(BLHELI) == true)
advance(RETRY_INTERVAL)
g.wakeup()
check("case 10 tile stays enabled after backoff window", g.isEntryEnabled(BLHELI) == true)
check("case 10 no duplicate request issued", requestCount() == 1,
  "was " .. requestCount())

-- ── case 12: esc guard, link loss resets state and reconnect reads immediately ─
local connected = true
requests = {}
g = esc_protocol_guard.new({
  canRequest = function() return connected end,
})
g.open()
check("case 12 initial read succeeds", reply(1, 1) == true)
check("case 12 initial tile enabled", g.isEntryEnabled(BLHELI) == true)
connected = false
g.wakeup()
check("case 12 tile disabled on link loss", g.isEntryEnabled(BLHELI) == false)
connected = true
g.wakeup()
check("case 12 reconnect triggers immediate read", requestCount() == 2,
  "was " .. requestCount())
check("case 12 second read answered with new protocol", reply(2, 4) == true)
check("case 12 new protocol enabled", g.isEntryEnabled(SCORPION) == true)
check("case 12 old protocol disabled", g.isEntryEnabled(BLHELI) == false)

-- ── case 13: link loss during backoff clears the retry wait ───────────────────
connected = true
requests = {}
g = esc_protocol_guard.new({
  canRequest = function() return connected end,
})
g.open()
advance(REQUEST_TIMEOUT + 0.1)
g.wakeup() -- timeout -> backoff armed for +5.0s
advance(0.5)
connected = false
g.wakeup() -- link loss during backoff clears nextAttemptAt
advance(0.1) -- 0.6s total after timeout, far before 5.0s backoff expiry
connected = true
g.wakeup()
check("case 13 ESC guard reads immediately after link loss in backoff", requestCount() == 2,
  "was " .. requestCount())

-- ── case 14: aborted request on link loss does not apply late reply ───────────
connected = true
requests = {}
g = esc_protocol_guard.new({
  canRequest = function() return connected end,
})
g.open()
check("case 14 request 1 issued", requestCount() == 1)
connected = false
g.wakeup() -- aborts request 1, increments token
connected = true
g.wakeup() -- request 2 issued
check("case 14 request 2 issued upon reconnect", requestCount() == 2,
  "was " .. requestCount())
check("case 14 aborted request 1 delivers late", reply(1, 1) == true)
check("case 14 aborted reply is ignored", g.isEntryEnabled(BLHELI) == false)
check("case 14 request 2 delivers reply", reply(2, 4) == true)
check("case 14 current reply is accepted", g.isEntryEnabled(SCORPION) == true)

-- ── Verdict ─────────────────────────────────────────────────────────────────
out("")
out(string.rep("-", 60))
out(string.format("checks: %d   failures: %d", checks, failures))
if failures > 0 then
  out("")
  out("FAILED")
  os.exit(1)
end
out("ALL CHECKS PASSED")
