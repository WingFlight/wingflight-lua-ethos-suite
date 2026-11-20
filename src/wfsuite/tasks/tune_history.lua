-- Tune Advisor capture, owned by the background task.
--
-- The FC measures the rate loop while you fly (lib/msp_tune_advisor.lua) but
-- keeps it in RAM. On each disarm this reads all three axes, saves them as
-- one flight (lib/tune_history.lua: the last few flights per aircraft), then
-- clears the FC so the next flight is measured on its own. The Tune Advisor
-- page works from the saved flights, not from the FC.
--
-- Event-driven from "session.update", no scheduler job: a capture is armed
-- by a disarm and runs once the link and aircraft identity are there, so a
-- flight that ends during a link loss is still captured on reconnect (the
-- FC kept the numbers). Nothing is saved for a flight with no rate flight
-- (flight_seconds 0). If the clear never gets through before the next arm,
-- that next flight's reading also holds this one's data: the FC cannot tell.
-- That reading is then saved marked as containing the saved flight, which the
-- page leaves out rather than counting it twice, when this task can tell
-- (containsHeld): no clear answered and no new link since that save, the same
-- PID and rate profile and tune, more seconds and no count smaller. Nothing
-- saved is ever removed for it; where it cannot tell, both are kept.
--
-- Paced so telemetry keeps flowing. Over S.Port and FBUS each 48-byte reply
-- takes 11 telemetry frames (14 from firmware before payload version 2), every one a sensor frame the FC does not
-- send, and the FC then holds sensors back for another 250 ms after the last
-- one. Read back to back, and retried every few seconds when a reply is lost,
-- that kept current, ESC and other sensors off the radio for as long as the
-- model sat disarmed. So the first read waits START_SECONDS after the disarm
-- (the pilot is reading the landing numbers, and the flight-stats sync goes
-- first), each later request waits GAP_SECONDS, a failed axis is asked again
-- on its own, and after MAX_FAILURES link errors or MAX_SAVE_FAILURES failed
-- writes the capture waits for the next disarm. The FC keeps the numbers, so
-- that disarm still saves them.
--
-- Publishes "tune_history.state" (retained, see lib/bus.lua) whenever it
-- changes, so the Tune Advisor page can hold its advice until the flight is in:
--   "reading"  disarmed with this flight not saved yet, or its clear still to go
--   "failed"   gave up after MAX_FAILURES link errors or MAX_SAVE_FAILURES failed writes
--   "idle"     anything else
--
-- Clocked by tasks/background.lua's scheduler (wakeup(), every 0.5 s), not by
-- "session.update" alone: the session publishes only when its snapshot
-- changes, so a quiet bench, or exactly the sensor dropout this pacing is
-- about, could leave a wait that never ends. "session.update" only records
-- the arm state, link and aircraft.
--
-- bus is the instance tasks/background.lua already loaded, passed in as this
-- chunk's argument -- see the equivalent note atop tasks/session.lua.
local bus = ...
local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local tuneAdvisor = requireModule("lib/msp_tune_advisor.lua")
local tuneHistory = requireModule("lib/tune_history.lua")

local START_SECONDS = 5           -- after a disarm, before the first read
local GAP_SECONDS = 2             -- between one answered request and the next
local RETRY_SECONDS = 5           -- after a link error, before asking again
local MAX_FAILURES = 3            -- link errors per disarm before waiting for the next one
local MAX_SAVE_FAILURES = 3       -- failed history writes per disarm before waiting for the next one

local lastArmed = nil             -- last known arm state; a link loss (nil) keeps it
local pending = false             -- a disarm has not been captured yet
local clearPending = false        -- saved, the FC not cleared yet
local busy = false                -- a request is out
local refusedOnFc = false         -- the FC holds a flight this layout refused: no clear, it would erase that flight
local nextAt = 0                  -- no request before this os.clock()
local failures = 0                -- link errors since the last disarm
local saveFailures = 0            -- history write failures since the last disarm
local capture = {mcuId = nil, modelName = nil, replies = {}}
-- The latest session snapshot's fields this task reads, copied rather than
-- holding on to the snapshot table
local link = {armed = nil, connected = false, mcuId = nil, apiVersionSupported = nil, craftName = nil,
  pidProfile = nil, rateProfile = nil}
local lastSeconds = {}            -- by mcuId: flight_seconds of the last flight saved
local held = {}                   -- by mcuId: the last flight saved (heldOf), until a clear for it is answered or a new link
local clearTarget = nil           -- mcuId the clear out was sent to
local state = nil                 -- last "tune_history.state" published

local function publishState()
  local now
  if lastArmed ~= false then
    now = "idle"
  elseif pending then
    now = nextAt == math.huge and "failed" or "reading"
  elseif clearPending and not refusedOnFc and nextAt ~= math.huge then
    now = "reading"
  else
    now = "idle"
  end
  if now ~= state then
    state = now
    bus.publish("tune_history.state", now)
  end
end

local function modelName()
  if link.craftName and link.craftName ~= "" then return link.craftName end
  if model and model.name then
    local ok, name = pcall(model.name)
    if ok and name and name ~= "" then return name end
  end
  return "Unknown"
end

local function clearReplies()
  for i = #capture.replies, 1, -1 do capture.replies[i] = nil end
end

local function waitFor(seconds)
  busy = false
  nextAt = os.clock() + seconds
end

-- A link error, or replies that are not one flight. After MAX_FAILURES,
-- nothing more until the next disarm resets the count.
local function failed()
  failures = failures + 1
  if failures >= MAX_FAILURES then
    busy = false
    nextAt = math.huge
    return
  end
  waitFor(RETRY_SECONDS)
end

local function onCleared()
  waitFor(0)
  clearPending = false
  if clearTarget then held[clearTarget] = nil end  -- so its next reading contains no saved flight
  publishState()
end

-- Four answers, and only the last is worth repeating.
--
--   reason == true  the FC's MSP error reply: no tune advisor in this firmware. Nothing
--                   to capture and nothing to clear, so this task stops until the pilot
--                   disarms again.
--   refused == true the FC answered, in a layout this suite does not know (see
--                   lib/msp_tune_advisor.lua's decode). Deterministic: the same reply comes
--                   back on every request, so RETRY_SECONDS would buy nothing but three
--                   reads every five seconds for as long as the model sits disarmed and
--                   connected. This flight is therefore not captured, said so once, and the
--                   NEXT disarm asks again -- once. `clearPending` is left alone on purpose:
--                   the flight controller holds a real flight in this case, and dropping it
--                   to save the retries would throw away data this suite could read once it
--                   knows the layout.
--   "cleared"       the queue was emptied (arming, a link loss, a transport change). Not
--                   this request's fault, so not counted against MAX_FAILURES. The axes
--                   already read are dropped: the FC may have restarted, and its next
--                   answers would be another flight's.
--   anything else   the link. Asked again shortly, from the axis that failed; the axes
--                   already read are kept.
local function handleError(reason, refused)
  if reason == true then
    clearReplies()
    busy = false
    pending = false
    clearPending = false
    return
  end
  if refused then
    clearReplies()
    busy = false
    pending = false
    refusedOnFc = true
    print("[tune_history] reply refused, flight not captured: " .. tostring(reason))
    return
  end
  if reason == "cleared" then
    clearReplies()
    waitFor(RETRY_SECONDS)
    return
  end
  failed()
end

local function onError(reason, refused)
  handleError(reason, refused)
  publishState()
end

local function sendClear()
  busy = true
  clearTarget = link.mcuId
  bus.publish("msp.request", tuneAdvisor.buildClearMessage(onCleared, onError))
end

local onData

local function requestAxis(axis)
  busy = true
  bus.publish("msp.request", tuneAdvisor.buildReadMessage(axis, onData, onError))
end

-- The counts the FC only ever adds to until its statistics are reset
-- (wingflight-firmware src/main/flight/tune_advisor.c: incremented, and zeroed
-- only by tuneAdvisorReset()): a reading that holds a saved flight has none
-- smaller than it. Not ffCount, the count of the best feedforward lag: that
-- lag can move.
local GROWING = {"fullCount", "fullSatCount", "releases", "bigRebounds"}
local BAND_COUNT = 3

-- What a later reading is checked against: per axis the tune and the growing
-- counts, in one array, with the profiles and the date and seconds the flight
-- was saved with
local function heldOf(replies, date, seconds)
  local v, n = {}, 0
  for axis = 1, tuneAdvisor.AXIS_COUNT do
    local a = replies[axis].a
    for _, k in ipairs(tuneHistory.TUNE_KEYS) do n = n + 1; v[n] = a[k] end
    for _, k in ipairs(GROWING) do n = n + 1; v[n] = a[k] or 0 end
    for i = 1, BAND_COUNT do
      n = n + 1; v[n] = a.spBands[i].count
      n = n + 1; v[n] = a.thrBands[i].count
    end
  end
  return {pid = link.pidProfile, rate = link.rateProfile, date = date, seconds = seconds, v = v}
end

-- Whether this reading holds the held flight as well: the FC was not cleared
-- since it was saved (a clear it answered drops it, and so does a new link: a
-- pack swapped restarts the FC), it flew on the same known profiles and tune
-- (a tune change restarts its statistics), it counts more seconds, and none of
-- its counts is smaller. False and the first test that failed otherwise.
local function containsHeld(h, replies, seconds)
  if not h then return false, "no saved flight held" end
  local pid, rate = link.pidProfile, link.rateProfile
  if pid == nil or rate == nil or pid ~= h.pid or rate ~= h.rate then return false, "profiles" end
  if seconds <= h.seconds then return false, "seconds" end
  local v, n = h.v, 0
  for axis = 1, tuneAdvisor.AXIS_COUNT do
    local a = replies[axis].a
    for _, k in ipairs(tuneHistory.TUNE_KEYS) do
      n = n + 1
      if a[k] ~= v[n] then return false, "tune" end
    end
    for _, k in ipairs(GROWING) do
      n = n + 1
      if (a[k] or 0) < v[n] then return false, "count" end
    end
    for i = 1, BAND_COUNT do
      n = n + 1
      if a.spBands[i].count < v[n] then return false, "count" end
      n = n + 1
      if a.thrBands[i].count < v[n] then return false, "count" end
    end
  end
  return true
end

-- All three axes are in: save them as one flight, then clear the FC.
local function finishCapture()
  local replies = capture.replies
  local mcuId, seconds = capture.mcuId, replies[1].seconds
  -- One flight has one flight time on every axis. Anything else is an FC that
  -- restarted or flew between two reads: start again.
  for i = 2, #replies do
    if replies[i].seconds ~= seconds then
      clearReplies()
      failed()
      return
    end
  end
  -- 0: no rate flight. Same as last time: the clear after that flight never
  -- got through and nothing new was flown.
  if seconds > 0 and lastSeconds[mcuId] ~= seconds then
    -- A flight saved before and not cleared off the FC since: this reading may hold it too
    local previous = nil
    local contains, why = containsHeld(held[mcuId], replies, seconds)
    if contains then previous = held[mcuId] end
    local ok, date, marked = tuneHistory.save(mcuId, capture.modelName, replies, previous)
    if not ok then
      -- Keep the replies for another write attempt, but do not retry forever:
      -- the FC still holds the flight until a successful save and clear.
      saveFailures = saveFailures + 1
      print("[tune_history] cannot write " .. tuneHistory.path(mcuId))
      if saveFailures >= MAX_SAVE_FAILURES then
        busy = false
        nextAt = math.huge
      else
        waitFor(RETRY_SECONDS)
      end
      return
    end
    saveFailures = 0
    lastSeconds[mcuId] = seconds
    held[mcuId] = heldOf(replies, date, seconds)
    if marked then
      print("[tune_history] reading holds the saved flight (FC not cleared): saved as containing it")
    elseif previous == nil and why ~= "no saved flight held" then
      print("[tune_history] saved flight not held in this reading (" .. tostring(why) .. ")")
    end
    bus.publish("tune_history.saved", mcuId)
  end
  clearReplies()
  pending = false
  if seconds > 0 then clearPending = true end
  waitFor(GAP_SECONDS)
end

onData = function(data)
  local replies = capture.replies
  -- A reply carries only the command number, so a late answer to the previous request can
  -- arrive as the answer to this one. It names its axis: one that is not the axis asked for is
  -- not stored, and that axis is asked again, counted like a link error so a reply that keeps
  -- naming another axis cannot loop (rfsuite #2787).
  if data.axis ~= #replies + 1 then
    failed()
    publishState()
    return
  end
  replies[#replies + 1] = data
  if #replies < tuneAdvisor.AXIS_COUNT then
    waitFor(GAP_SECONDS)
  else
    finishCapture()
  end
  publishState()
end

-- Sends the next request when one is due
local function advance()
  if not (pending or clearPending) or busy or link.armed ~= false or link.connected ~= true then return end
  if not link.mcuId or link.apiVersionSupported == false then return end
  if os.clock() < nextAt then return end

  if pending then
    -- Another aircraft since the last answer: its axes, not these
    if #capture.replies > 0 and capture.mcuId ~= link.mcuId then clearReplies() end
    if #capture.replies == 0 then
      refusedOnFc = false
      capture.mcuId = link.mcuId
      capture.modelName = modelName()
    end
    if #capture.replies >= tuneAdvisor.AXIS_COUNT then
      finishCapture()             -- a save that failed, tried again
    else
      requestAxis(#capture.replies + 1)
    end
  elseif not refusedOnFc then
    sendClear()
  end
end

local function onSessionUpdate(snapshot)
  if not snapshot then return end
  local armed = snapshot.isArmed
  if armed == true then
    pending = false               -- the next disarm captures this flight too
  elseif armed == false and lastArmed == true then
    pending = true
    failures = 0
    saveFailures = 0
    clearReplies()
    nextAt = os.clock() + START_SECONDS
  end
  if armed ~= nil then lastArmed = armed end
  -- A new link: a fresh pack restarted the FC, which the radio cannot tell from
  -- the same one, so no saved flight is taken to be held in its next reading
  if snapshot.connected == true and link.connected ~= true then
    for k in pairs(held) do held[k] = nil end
  end
  link.armed = armed
  link.connected = snapshot.connected
  link.pidProfile = snapshot.pidProfile
  link.rateProfile = snapshot.rateProfile
  link.mcuId = snapshot.mcuId
  link.apiVersionSupported = snapshot.apiVersionSupported
  link.craftName = snapshot.craftName

  advance()
  publishState()
end

-- tasks/background.lua's scheduler, every 0.5 s
local function wakeup()
  advance()
  publishState()
end

bus.subscribe("session.update", onSessionUpdate)

return {wakeup = wakeup}
