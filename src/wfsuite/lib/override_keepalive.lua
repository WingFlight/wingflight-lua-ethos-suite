-- Keeps timed bench overrides alive (wingflight-firmware API 22.14+).
--
-- From API 22.14 the FC drops a servo, mixer or mode override that carries a
-- timeout unless it is re-sent within that time, so a radio that is switched
-- off or a link that drops while a page holds a servo cannot leave it held.
-- A page sets an override here instead of sending it once; tick(), run from
-- tasks/background.lua, re-sends every active one every REFRESH_S
-- regardless of which page is open, and clear() stops it (the page still
-- sends the OFF value itself).
--
-- Against older firmware supported() is false and callers send their
-- overrides untimed, as before.
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.override_keepalive"] then
  return package.loaded["wfsuite.lib.override_keepalive"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")

local MIN_API_MAJOR = 22
local MIN_API_MINOR = 14
-- Telemetry links are slow and lossy: a 10 s timeout refreshed every 3 s
-- survives two lost refreshes (each also retried by the queue).
local TIMEOUT_MS = 10000
local REFRESH_S = 3

local keepalive = {TIMEOUT_MS = TIMEOUT_MS}

-- key -> {build = fn() -> msp message, sentAt = os.clock() of last send}
local active = {}
local connected = false
local apiMajor, apiMinor

bus.subscribe("session.update", function(snapshot)
  connected = snapshot.connected == true
  apiMajor = snapshot.apiVersionMajor
  apiMinor = snapshot.apiVersionMinor
end)

function keepalive.supported()
  return apiMajor == MIN_API_MAJOR and (apiMinor or 0) >= MIN_API_MINOR
end

-- build() returns a fresh MSP message carrying TIMEOUT_MS; it is sent now
-- and on every refresh. Replaces any override already set under `key`.
function keepalive.set(key, build)
  local entry = active[key]
  if entry then
    entry.build = build
  else
    entry = {build = build}
    active[key] = entry
  end
  entry.sentAt = os.clock()
  bus.publish("msp.request", build())
end

function keepalive.clear(key)
  active[key] = nil
end

-- Clears every key starting with `prefix` (plain match).
function keepalive.clearPrefix(prefix)
  local n = #prefix
  for key in pairs(active) do
    if key:sub(1, n) == prefix then active[key] = nil end
  end
end

function keepalive.isActive(key)
  return active[key] ~= nil
end

function keepalive.tick(now)
  if next(active) == nil or not connected then return end
  for _, entry in pairs(active) do
    if now - entry.sentAt >= REFRESH_S then
      entry.sentAt = now
      bus.publish("msp.request", entry.build())
    end
  end
end

package.loaded["wfsuite.lib.override_keepalive"] = keepalive
return keepalive
