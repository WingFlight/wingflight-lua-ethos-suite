-- Local flight timer state owned by the background task.
--
-- A short link loss while the model is still armed does not end the flight:
-- the time flown is banked, flightCounted survives, and on reconnect the
-- clock restarts on top of the banked total. Disarming, or a gap longer than
-- RECONNECT_GRACE_SECONDS, closes the flight. Ported from
-- rotorflight-lua-ethos-suite PR #2405; bin/flight_record/verify_flight_record.lua
-- drives this state machine.

local flight_timer = {}

-- A flight counts towards stats.flightcount once it has run this long.
local FLIGHT_COUNT_SECONDS = 25

-- How long a link loss may last and still be called the same flight. The
-- window bounds *merging*, never splitting: a gap that outlasts it yields two
-- records instead of one wrong one, because two flights merged into one
-- corrupt the peaks and the flight count, while one flight split in two only
-- costs a file boundary.
local RECONNECT_GRACE_SECONDS = 30

local state = {
  start = nil,
  live = 0,
  session = 0,
  flightCounted = false,
  -- The session total when the current flight began, so a flight's own time
  -- is session - flightBase, which stays right across a link loss.
  flightBase = 0,
  -- Set when a flight was running when the link dropped; its time is already
  -- folded into `session`.
  resumable = false,
  lostAt = nil,
}

local function roundedSeconds(value)
  value = tonumber(value) or 0
  if value < 0 then value = 0 end
  return math.floor(value + 0.5)
end

local function snapshot()
  return {
    timerLive = roundedSeconds(state.live),
    timerSession = roundedSeconds(state.session),
    timerFlightCounted = state.flightCounted == true,
  }
end

local function sameSnapshot(a, b)
  return a.timerLive == b.timerLive
    and a.timerSession == b.timerSession
    and a.timerFlightCounted == b.timerFlightCounted
end

local function elapsedSince(start, now)
  local segment = now - start
  if segment < 0 then segment = 0 end
  return segment
end

local function graceExpired(now)
  return (now - state.lostAt) > RECONNECT_GRACE_SECONDS
end

function flight_timer.reset()
  state.start = nil
  state.live = 0
  state.session = 0
  state.flightCounted = false
  state.flightBase = 0
  state.resumable = false
  state.lostAt = nil
end

-- Bank the running segment and stop the clock without reporting a finished
-- segment: the link has ended, not the flight.
local function freeze(now)
  state.session = state.session + elapsedSince(state.start, now)
  state.start = nil
  state.live = state.session
  state.resumable = true
  state.lostAt = now
end

-- Close the open flight for good. Returns the event the caller persists, or
-- nil when no time was flown. A flight held open across a link loss reports
-- the whole flight, not just the part after the drop.
local function closeFlight(now)
  if state.start then
    state.session = state.session + elapsedSince(state.start, now)
    state.start = nil
  end
  local flown = state.session - state.flightBase
  local event = nil
  if flown > 0 then
    event = {
      finishedSegment = roundedSeconds(flown),
      session = roundedSeconds(state.session),
    }
  end
  state.flightBase = state.session
  state.resumable = false
  state.lostAt = nil
  state.live = state.session
  return event
end

-- A step can both close an abandoned flight and count a new one, so the two
-- share one event rather than the second overwriting the first.
local function addEvent(existing, extra)
  if not extra then return existing end
  if not existing then return extra end
  for k, v in pairs(extra) do existing[k] = v end
  return existing
end

function flight_timer.update(connected, armed, now)
  local before = snapshot()
  now = tonumber(now) or os.clock()
  local event = nil

  if connected ~= true then
    if state.start then
      -- Mid-flight link loss: hold the flight open across the gap.
      freeze(now)
    elseif state.resumable then
      if graceExpired(now) then
        event = closeFlight(now)
      end
    else
      -- Nothing running and nothing held. The `resumable` arm above matters:
      -- the link stays down for many ticks, and later ones must not wipe the
      -- flight being held.
      flight_timer.reset()
    end
  elseif armed == true then
    if state.resumable then
      if not graceExpired(now) then
        -- Same flight: `session` already carries the time flown before the
        -- drop, so the clock restarts on top of it.
        state.resumable = false
        state.lostAt = nil
        state.start = now
      else
        -- Gone too long to be the same flight: close it (its time is banked)
        -- and begin a new one from here.
        event = closeFlight(now)
        state.start = now
        state.flightCounted = false
      end
    elseif not state.start then
      state.start = now
      state.flightCounted = false
      state.flightBase = state.session
    end
    -- Measured from the start of the flight, not of the current leg: testing
    -- only this leg would let a flight held across a drop count twice, or a
    -- flight that passed the threshold before the drop never count.
    local flown = state.session - state.flightBase + elapsedSince(state.start, now)
    state.live = state.session + elapsedSince(state.start, now)
    if flown >= FLIGHT_COUNT_SECONDS and not state.flightCounted then
      state.flightCounted = true
      event = addEvent(event, {flightCounted = true})
    end
  elseif armed == false then
    -- Disarmed while connected, or reconnected disarmed: the flight is over,
    -- including one held open across a drop.
    if state.start or state.resumable then
      event = closeFlight(now)
    end
    state.live = state.session
  else
    -- Connected but the arm state is not known yet (just reconnected): keep
    -- holding unless the grace window has run out.
    if state.resumable and graceExpired(now) then
      event = closeFlight(now)
    end
    state.live = state.session
  end

  local after = snapshot()
  return not sameSnapshot(before, after), after, event
end

-- True while a flight that was running at link loss can still be resumed.
-- tasks/logging.lua reads this (as session.flightResumable) to decide between
-- holding its file open and starting a new one, so the grace window is decided
-- in one place.
function flight_timer.resumable(now)
  if not state.resumable then return false end
  now = tonumber(now) or os.clock()
  return not graceExpired(now)
end

-- True while a flight is running or held open across a link loss.
function flight_timer.inProgress(now)
  return state.start ~= nil or flight_timer.resumable(now)
end

function flight_timer.current()
  return snapshot()
end

return flight_timer
