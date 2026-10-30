-- Behaviour check for Issue #2493: the tune advisor codec refuses a reply it does not
-- understand, instead of decoding it into plausible numbers.
--
-- Run it:
--     lua5.4 bin/tune_advisor_payload/verify_tune_advisor_payload.lua
--
-- What it drives: the real src/wfsuite/lib/msp_tune_advisor.lua, through the message
-- its read builder returns, so the reply goes through processReply exactly as the
-- transport hands it over. The replies are the simulator's own 48-byte reply (payload
-- version 2), replies packed here with string.pack from the firmware's layouts (msp.c,
-- MSP2_WING_TUNE_ADVISOR: version 2, and the 65-byte version 1 of snapshots 0.0.32 to
-- 0.0.38) so the codec is checked against the firmware's byte order and not against
-- itself, and variants of them.
--
-- Against unpatched master the version-3, short and long replies reach onData as
-- decoded numbers; the checks for those go red.

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

local tuneAdvisor = requireModule("lib/msp_tune_advisor.lua")

local function copy(buf)
  local out = {}
  for i = 1, #buf do out[i] = buf[i] end
  return out
end

-- Feeds one reply through the read message's processReply and records what happened.
local function deliver(buf)
  local got = {data = nil, reason = nil, refused = nil, errors = 0}
  local msg = tuneAdvisor.buildReadMessage(1,
  function(data) got.data = data end,
  function(reason, refused) got.errors = got.errors + 1; got.reason = reason; got.refused = refused end)
  msg.processReply(nil, buf)
  return got
end

-- The simulator reply for axis 1: the firmware's 48-byte layout, version 2.
local sim = tuneAdvisor.buildReadMessage(1, function() end, function() end).simulatorResponse

local function bytes(packed)
  local out = {}
  for i = 1, #packed do out[i] = packed:byte(i) end
  return out
end

local function near(x, y) return x ~= nil and math.abs(x - y) < 1e-9 end

-- The firmware's layouts, field by field (msp.c, MSP2_WING_TUNE_ADVISOR)
local LAYOUT_V2 = "<" ..
  "B B H" ..          -- version, flags (bits 0-1 axis, bit 2 collecting), seconds
  "I4 B B" ..         -- P | F << 10 | B << 20, iterm relax, rc rate
  "H B b B" ..        -- ffCount, ffGain x64, ffCorr x100, ffLagMs
  "BH BH BH" ..       -- setpoint bands: gain x64, count
  "BH BH BH" ..       -- throttle bands
  "H H B B" ..        -- fullCount, fullSatCount, fullRatio x100, fullMaxRate / 10
  "H H B B B h"       -- releases, bigRebounds, meanRebound x100, meanOvershoot x64, meanCounter x100, meanIterm x1000
local LAYOUT_V1 = "<" ..
  "B B H B" ..        -- version, collecting, seconds, axis
  "H H H B B" ..      -- P, F, B, iterm relax, rc rate
  "H h h H" ..        -- ffCount, ffGain, ffCorr (x1000), ffLagMs
  "hH hH hH" ..       -- setpoint bands
  "hH hH hH" ..       -- throttle bands
  "H H h H" ..        -- fullCount, fullSatCount, fullRatio, fullMaxRate
  "H H h h h h"       -- releases, bigRebounds, meanRebound, meanOvershoot, meanCounter, meanIterm

print("the firmware's 48-byte reply, payload version 2")
do
  check("the layout is 48 bytes, within one CRSF frame", string.packsize(LAYOUT_V2) == 48,
    "packsize " .. string.packsize(LAYOUT_V2))
  check("the simulator reply is 48 bytes", #sim == 48, "length " .. #sim)
  local got = deliver(copy(sim))
  check("it decodes and reaches onData", got.data ~= nil and got.errors == 0,
    "errors " .. got.errors .. ", reason " .. tostring(got.reason))
  check("a reply that decodes is not a refusal", got.refused == nil,
    "refused " .. tostring(got.refused))
  check("the simulator's tune comes back", got.data ~= nil and got.data.axis == 1 and got.data.a.P == 105
    and got.data.a.F == 65 and got.data.a.B == 35 and got.data.a.relax == 5 and got.data.a.rcRate == 18,
    got.data and ("P " .. got.data.a.P .. " F " .. got.data.a.F .. " B " .. got.data.a.B))
end

print("a version 2 reply packed from the firmware's layout decodes field by field")
do
  local packed = string.pack(LAYOUT_V2,
    2, 1 + 4, 300,                             -- version 2; pitch (axis 1), collecting
    196 + 150 * 1024 + 25 * 1024 * 1024, 7, 40,
    1500, 98, -50, 90,                         -- ffGain 98/64, ffCorr -0.50
    97, 1341, 99, 163, 66, 50,
    79, 385, 99, 763, 111, 356,
    87, 25, 38, 40,                            -- fullRatio 0.38, fullMaxRate 400
    35, 18, 15, 94, 2, -42)                    -- meanIterm -0.042
  local got = deliver(bytes(packed))
  local d = got.data
  local a = d and d.a or {}
  check("it decodes", d ~= nil, tostring(got.reason))
  check("flags: axis and collecting", d ~= nil and d.axis == 2 and d.collecting == true,
    d and ("axis " .. d.axis))
  check("the packed gains: P, F, B", a.P == 196 and a.F == 150 and a.B == 25,
    tostring(a.P) .. "/" .. tostring(a.F) .. "/" .. tostring(a.B))
  check("the rest of the tune", a.relax == 7 and a.rcRate == 40)
  check("feed-forward: count, gain, correlation, lag", a.ffCount == 1500 and near(a.ffGain, 98 / 64)
    and near(a.ffCorr, -0.5) and a.ffLagMs == 90, tostring(a.ffGain) .. " " .. tostring(a.ffCorr))
  check("bands: gain x64 and count", a.spBands and near(a.spBands[1].gain, 97 / 64)
    and a.spBands[3].count == 50 and near(a.thrBands[3].gain, 111 / 64) and a.thrBands[2].count == 763)
  check("full stick", a.fullCount == 87 and a.fullSatCount == 25 and near(a.fullRatio, 0.38)
    and a.fullMaxRate == 400, tostring(a.fullMaxRate))
  check("stops", a.releases == 35 and a.bigRebounds == 18 and near(a.meanRebound, 0.15)
    and near(a.meanOvershoot, 94 / 64) and near(a.meanCounter, 0.02) and near(a.meanIterm, -0.042),
    tostring(a.meanIterm))
  check("seconds", d ~= nil and d.seconds == 300)
end

print("a 65-byte version 1 reply (snapshots 0.0.32 to 0.0.38) is still read")
do
  local packed = string.pack(LAYOUT_V1,
    1, 1, 147, 0,                              -- version 1, collecting, roll
    105, 65, 35, 5, 18,
    1491, 1530, 970, 90,
    1520, 1341, 1540, 163, 1030, 50,
    1240, 385, 1540, 763, 1730, 356,
    87, 25, 380, 395,
    35, 18, 150, 1470, 20, 3)
  check("the layout is 65 bytes", #packed == 65, "length " .. #packed)
  local got = deliver(bytes(packed))
  local d = got.data
  local a = d and d.a or {}
  check("it decodes and reaches onData", d ~= nil and got.errors == 0, tostring(got.reason))
  check("its tune and figures are the reply's", d ~= nil and d.axis == 1 and d.collecting == true
    and a.P == 105 and a.F == 65 and a.relax == 5 and a.rcRate == 18 and near(a.ffGain, 1.53)
    and a.fullMaxRate == 395 and near(a.thrBands[3].gain, 1.73) and near(a.meanIterm, 0.003),
    tostring(a.ffGain))
end

-- Every refusal below must be marked as one. The history task reads that flag to tell a
-- deterministic answer from a lost link, and it is the flag that stops the five-second retry.
local function checkRefused(label, got)
  check(label .. ": it is marked refused", got.refused == true,
    "refused " .. tostring(got.refused))
end

print("payload version 3 (a layout this suite does not know)")
do
  local v3 = copy(sim)
  v3[1] = 3
  local got = deliver(v3)
  check("onData is not called with a decoded record", got.data == nil,
    "decoded version " .. tostring(got.data and got.data.version))
  check("onError is called with the reason", got.errors == 1 and type(got.reason) == "string"
    and got.reason:find("version 3", 1, true) ~= nil,
    "errors " .. got.errors .. ", reason " .. tostring(got.reason))
  checkRefused("version 3", got)
end

print("version 1 with the version 2 length (48 bytes)")
do
  local mixed = copy(sim)
  mixed[1] = 1
  local got = deliver(mixed)
  check("onData is not called", got.data == nil)
  checkRefused("version 1, 48 bytes", got)
end

print("a truncated reply (47 bytes)")
do
  local short = copy(sim)
  short[#short] = nil
  local got = deliver(short)
  check("onData is not called", got.data == nil,
    "decoded, with the missing bytes as zeros")
  check("onError is called with the reason", got.errors == 1 and type(got.reason) == "string",
    "errors " .. got.errors)
  checkRefused("truncated", got)
end

print("a longer reply (49 bytes)")
do
  local long = copy(sim)
  long[#long + 1] = 0
  local got = deliver(long)
  check("onData is not called", got.data == nil)
  check("onError is called with the reason", got.errors == 1 and type(got.reason) == "string",
    "errors " .. got.errors)
  checkRefused("longer", got)
end

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
