-- Tune Advisor flight history: the per-aircraft CSV that tasks/tune_history.lua
-- writes on each disarm and app/pages/tune_advisor.lua reads back.
--
--   LOGS:/wfsuite/tune/<mcuId>/history.csv   (mcuId: the session's aircraft ID)
--   LOGS:/wfsuite/tune/<mcuId>/logs.ini      (model name, as the flight log folders)
--   LOGS:/wfsuite/tune/<mcuId>/changes.csv   (what the page's Apply wrote, see logChanges())
--
-- The FC's statistics are cleared after each capture, so a row is one flight.
-- One row per axis per flight; only the last MAX_FLIGHTS flights are kept,
-- since the page never looks further back.
--
-- A flight's rows may be followed by a mark line
--   contains,<date>,<flight_seconds>
-- saying that this flight's reading also holds the saved flight with that date
-- and seconds: the FC was not cleared between the two (an arm before the clear
-- after the save went through, or three failed clears), so its numbers hold
-- both. aggregate() then leaves that older flight out rather than counting it
-- twice. tasks/tune_history.lua writes it only on its own evidence; a reader
-- without it skips the line (it does not have a row's columns) and counts both.
--
-- aggregate() combines the newest flights flown on the newest flight's tune,
-- for one axis: counts add up, ratios are averaged weighted by the count they
-- came from. The FC's own gains are setpoint-squared weighted, so this is an
-- approximation across flights, close when flights are alike; the stop
-- figures (sums / releases on the FC) combine exactly.
--
-- Columns are this file's FIELDS, in order; tasks/ and app/ never spell them.
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.tune_history"] then
  return package.loaded["wfsuite.lib.tune_history"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ini = requireModule("lib/ini.lua")
local atomicWrite = requireModule("lib/atomic_write.lua")

local BASE_DIR = "LOGS:/wfsuite/tune"
local MAX_FLIGHTS = 5
local AXIS_COUNT = 3
local AXIS_NAMES = {"roll", "pitch", "yaw"}
local BAND_COUNT = 3

-- {csv name, key in the decoded axis table, format}; band fields carry
-- band (the band table's key) and index.
local FIELDS = {
  {"p", "P", "%d"}, {"f", "F", "%d"}, {"b", "B", "%d"}, {"relax", "relax", "%d"}, {"rc_rate", "rcRate", "%d"},
  -- The PID and rate profile the flight was flown on, 1-based as the session reports them, 0
  -- when the radio did not know (rfsuite #2785). The FC resets its statistics when they
  -- change, but the radio combines the saved rows itself.
  {"pid_profile", "pidProfile", "%d"}, {"rate_profile", "rateProfile", "%d"},
  {"ff_count", "ffCount", "%d"}, {"ff_gain", "ffGain", "%.3f"}, {"ff_corr", "ffCorr", "%.3f"},
  {"ff_lag_ms", "ffLagMs", "%d"},
}
local function addBands(band, labels)
  for i = 1, BAND_COUNT do
    FIELDS[#FIELDS + 1] = {labels[i] .. "_gain", "gain", "%.3f", band = band, index = i}
    FIELDS[#FIELDS + 1] = {labels[i] .. "_count", "count", "%d", band = band, index = i}
  end
end
addBands("spBands", {"sp40", "sp100", "sp200"})
addBands("thrBands", {"thr0", "thr30", "thr60"})
for _, f in ipairs({
  {"full_count", "fullCount", "%d"}, {"full_sat_count", "fullSatCount", "%d"},
  {"full_ratio", "fullRatio", "%.3f"}, {"full_max_rate", "fullMaxRate", "%d"},
  {"releases", "releases", "%d"}, {"big_rebounds", "bigRebounds", "%d"},
  {"mean_rebound", "meanRebound", "%.3f"}, {"mean_overshoot", "meanOvershoot", "%.3f"},
  {"mean_counter", "meanCounter", "%.3f"}, {"mean_iterm", "meanIterm", "%.3f"},
}) do FIELDS[#FIELDS + 1] = f end

-- The tune a flight was measured with: flights are only combined when these match
local TUNE_KEYS = {"P", "F", "B", "relax", "rcRate"}

-- The mark line (see the top of this file)
local MARK = "contains"

local HEADER
do
  local names = {"date", "flight_seconds", "axis"}
  for _, f in ipairs(FIELDS) do names[#names + 1] = f[1] end
  HEADER = table.concat(names, ",")
end

local tuneHistory = {MAX_FLIGHTS = MAX_FLIGHTS, AXIS_COUNT = AXIS_COUNT, TUNE_KEYS = TUNE_KEYS}

local function safeMkdir(path)
  if os and os.mkdir then pcall(os.mkdir, path) end
end

local function fileExists(path)
  local file = io.open(path, "rb")
  if not file then return false end
  pcall(function() file:close() end)
  return true
end

function tuneHistory.path(mcuId)
  return BASE_DIR .. "/" .. mcuId .. "/history.csv"
end

local function newAxis()
  local a = {spBands = {}, thrBands = {}}
  for i = 1, BAND_COUNT do
    a.spBands[i] = {gain = 0, count = 0}
    a.thrBands[i] = {gain = 0, count = 0}
  end
  for _, f in ipairs(FIELDS) do
    if not f.band then a[f[2]] = 0 end
  end
  return a
end

local function row(date, seconds, axis, a)
  local parts = {date, tostring(seconds), AXIS_NAMES[axis]}
  for _, f in ipairs(FIELDS) do
    local v = f.band and a[f.band][f.index][f[2]] or a[f[2]]
    parts[#parts + 1] = string.format(f[3], v or 0)
  end
  return table.concat(parts, ",")
end

local function splitLines(text)
  local lines = {}
  for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
  return lines
end

local ROW_COMMAS = #FIELDS + 2

-- A row's date, seconds and axis (1..3), or nil for a line that is not a row
local function rowKey(line)
  local date, seconds, name = line:match("^([^,]*),([^,]*),([^,]*),")
  if not date then return nil end
  local axis = nil
  for n = 1, AXIS_COUNT do
    if AXIS_NAMES[n] == name then axis = n end
  end
  if not axis or select(2, line:gsub(",", "")) ~= ROW_COMMAS then return nil end
  return date, tonumber(seconds) or 0, axis
end

-- A mark line's date and seconds, or nil
local MARK_PATTERN = "^" .. MARK .. ",([^,]*),([^,]*)$"
local function markOf(line)
  local date, seconds = line:match(MARK_PATTERN)
  if not date then return nil end
  return date, tonumber(seconds) or 0
end

-- The file's lines grouped into flights, oldest first, by read()'s rule (a new
-- flight where the date changes or an axis comes again): {date, seconds, lines,
-- mark}. A mark is kept with the flight whose row is the line just before it;
-- after any other line it marks nothing. Lines that are neither are dropped.
local function groupLines(lines)
  local flights, current, lastWasRow = {}, nil, false
  for i = 2, #lines do
    local line = lines[i]
    local date, seconds, axis = rowKey(line)
    if date then
      if not current or current.date ~= date or current.seen[axis] then
        current = {date = date, seconds = seconds, lines = {}, seen = {}}
        flights[#flights + 1] = current
      end
      current.seen[axis] = true
      current.lines[#current.lines + 1] = line
      lastWasRow = true
    else
      if lastWasRow and markOf(line) then current.mark = line end
      lastWasRow = false
    end
  end
  return flights
end

-- replies: three decoded lib/msp_tune_advisor.lua replies, roll/pitch/yaw.
-- Appends one flight and drops all but the newest MAX_FLIGHTS.
-- previous: {date, seconds} of a saved flight this one's numbers also hold (the
-- capture's evidence that the FC was not cleared since), or nil. The new flight
-- is marked as holding it only while that is still the file's newest flight:
-- after an erase or a lost save it is another one, and nothing is marked.
-- Nothing is ever removed for it.
-- Returns true when written, the date the flight was saved with, and whether
-- it was marked.
function tuneHistory.save(mcuId, modelName, replies, previous)
  local dir = BASE_DIR .. "/" .. mcuId
  safeMkdir("LOGS:")
  safeMkdir("LOGS:/wfsuite")
  safeMkdir(BASE_DIR)
  safeMkdir(dir)
  if not fileExists(dir .. "/logs.ini") then
    ini.save_ini_file(dir .. "/logs.ini", {model = {name = modelName}})
  end

  local path = tuneHistory.path(mcuId)
  local flights = {}
  local text = ini.load_file_as_string(path)
  if text then
    local lines = splitLines(text)
    -- A file written with other columns is started again
    if lines[1] == HEADER then flights = groupLines(lines) end
  end

  local date = os.date("%Y-%m-%d %H:%M:%S")
  local seconds = replies[1].seconds
  local last = flights[#flights]
  local mark = nil
  if previous and last and last.date == previous.date and last.seconds == previous.seconds then
    mark = MARK .. "," .. last.date .. "," .. tostring(last.seconds)
  end
  local out = {HEADER}
  for i = math.max(1, #flights - MAX_FLIGHTS + 2), #flights do
    local flight = flights[i]
    for j = 1, #flight.lines do out[#out + 1] = flight.lines[j] end
    if flight.mark then out[#out + 1] = flight.mark end
  end
  for axis = 1, AXIS_COUNT do out[#out + 1] = row(date, seconds, axis, replies[axis].a) end
  if mark then out[#out + 1] = mark end
  out[#out + 1] = ""
  return atomicWrite.write(path, table.concat(out, "\n")), date, mark ~= nil
end

-- The Tune Advisor's Apply record, beside the history: one row per setting
-- changed, with the value it replaced, so a change can be undone by hand,
-- and so the page can tell how far its own changes have moved a setting
-- (pilotValue()).
-- Kept by erase(): it is the pilot's record. Started afresh above 16 KiB (see compact()).
local CHANGES_HEADER = "date,axis,setting,from,to"

local ROW_PATTERN = "^([^,]*),([^,]*),([^,]*),(%-?%d+),(%-?%d+)$"
-- The record is started afresh once an Apply leaves it above this size (rfsuite #2807): it was
-- appended forever and read whole on every page open.
local COMPACT_BYTES = 16 * 1024

local function changesPath(mcuId)
  return BASE_DIR .. "/" .. mcuId .. "/changes.csv"
end

-- The record before the last restart, kept until the next one
local function backupPath(path)
  return path .. ".old"
end

local function axisOf(name)
  for n = 1, AXIS_COUNT do
    if AXIS_NAMES[n] == name then return n end
  end
  return nil
end

-- Calls fn(date, axis, key, from, to) for every row that parses, oldest first, reading the file
-- line by line rather than as one string. Returns the bytes read and the rows that parsed, or nil
-- when the file cannot be opened or a read fails (a failed read is not taken for the end of the
-- file).
local function eachRow(path, fn)
  local file = io.open(path, "rb")
  if not file then return nil end
  local bytes, rows, failed = 0, 0, false
  while true do
    local line, err = file:read("L")
    if not line then
      failed = err ~= nil
      break
    end
    bytes = bytes + #line
    local date, axisName, key, from, to = line:gsub("[\r\n]+$", ""):match(ROW_PATTERN)
    local axis = axisOf(axisName)
    if axis then
      rows = rows + 1
      if fn then fn(date, axis, key, tonumber(from), tonumber(to)) end
    end
  end
  pcall(function() file:close() end)
  if failed then return nil end
  return bytes, rows
end

-- A restart that stopped after the record was moved to the backup leaves no live record. The
-- backup is the full record: it is put back before anything is appended, so the next Apply does
-- not start a record of its own beside it. Returns false when it cannot be put back.
local function recover(path)
  if fileExists(path) then return true end
  local backup = backupPath(path)
  if not fileExists(backup) then return true end
  pcall(os.rename, backup, path)
  atomicWrite.discardTemp(path)
  return fileExists(path)
end

-- Starts the record afresh with one row per setting: the page's newest unbroken chain of its
-- own changes, from the value it started at to the value it ended at. pilotValue() follows only
-- that chain back from the current value, so it answers the same as over the whole record for
-- every setting and current value. The new record is staged beside the old one; the old one is
-- kept as the backup.
local function compact(path)
  local chains, order = {}, {}
  local read, rowsRead = eachRow(path, function(date, axis, key, from, to)
    local id = axis .. "|" .. key
    local c = chains[id]
    if c and c.to == from then
      c.to, c.date = to, date
    elseif c then
      c.from, c.to, c.date = from, to, date
    else
      chains[id] = {axis = axis, key = key, from = from, to = to, date = date}
      order[#order + 1] = id
    end
  end)
  -- A failed read, or a file with no rows of ours, is left as it is
  if not read or rowsRead == 0 then return false end

  local handle = atomicWrite.stage(path)
  if not handle then return false end
  local ok = pcall(function()
    handle:write(CHANGES_HEADER, "\n")
    for _, id in ipairs(order) do
      local c = chains[id]
      handle:write(string.format("%s,%s,%s,%d,%d\n", c.date, AXIS_NAMES[c.axis], c.key, c.from, c.to))
    end
  end)
  if not ok then
    atomicWrite.abort(handle, path)
    return false
  end
  -- The full record becomes the backup. Without it the restart does not go ahead.
  local backup = backupPath(path)
  pcall(os.remove, backup)
  pcall(os.rename, path, backup)
  if fileExists(path) or not fileExists(backup) then
    atomicWrite.abort(handle, path)
    recover(path)
    return false
  end

  -- Ethos' file:write/close do not report failures uniformly, so the new record is read back:
  -- one row per chain, or the backup is put back in its place.
  local committed = atomicWrite.commit(handle, path)
  local _, rows = eachRow(path)
  if not committed or rows ~= #order then
    pcall(os.remove, path)
    recover(path)
    return false
  end
  return true
end

-- changes: {key, from, to} as the Tune Advisor page builds them
function tuneHistory.logChanges(mcuId, axis, changes)
  local path = changesPath(mcuId)
  if not recover(path) then return false end
  local isNew = not fileExists(path)
  local file = io.open(path, "a")
  if not file then return false end
  local date = os.date("%Y-%m-%d %H:%M:%S")
  if isNew then file:write(CHANGES_HEADER, "\n") end
  for _, c in ipairs(changes) do
    file:write(string.format("%s,%s,%s,%d,%d\n", date, AXIS_NAMES[axis], c.key, c.from, c.to))
  end
  file:close()
  -- A restart that fails keeps the full record: the Apply above is already in it
  if (eachRow(path) or 0) > COMPACT_BYTES then compact(path) end
  return true
end

-- The Apply record, oldest first: {axis, key, from, to} per row, read line by line. Every row
-- that parses is read, whatever the header says: logChanges() appends to the file as it is, so
-- a header check would lose every later record. A missing file, or one with no such rows, reads
-- as no changes. An interrupted restart leaves only the backup, which is read instead.
function tuneHistory.readChanges(mcuId)
  local changes = {}
  local path = changesPath(mcuId)
  if not fileExists(path) then path = backupPath(path) end
  eachRow(path, function(_, axis, key, from, to)
    changes[#changes + 1] = {axis = axis, key = key, from = from, to = to}
  end)
  return changes
end

-- The value the pilot last set by hand for one setting (a TUNE_KEYS name):
-- from the current value, follows the Apply record back while each change
-- ended at the value the next one started from. A change made by hand breaks
-- that chain, so the value it set counts as the pilot's.
function tuneHistory.pilotValue(changes, axis, key, value)
  for i = #changes, 1, -1 do
    local c = changes[i]
    if c.axis == axis and c.key == key then
      if c.to ~= value then break end
      value = c.from
    end
  end
  return value
end

function tuneHistory.erase(mcuId)
  if os and os.remove then pcall(os.remove, tuneHistory.path(mcuId)) end
end

-- Returns the saved flights, oldest first: {date, seconds, axes = {a, a, a},
-- contains}, contains being the {date, seconds} of a saved flight this one's
-- reading also holds (a mark line, see the top of this file), else nil.
-- A missing or foreign file reads as no flights.
function tuneHistory.read(mcuId)
  local flights = {}
  local text = ini.load_file_as_string(tuneHistory.path(mcuId))
  if not text then return flights end
  local lines = splitLines(text)
  if lines[1] ~= HEADER then return flights end

  local current, lastWasRow = nil, false
  for i = 2, #lines do
    local cols = {}
    for v in (lines[i] .. ","):gmatch("([^,]*),") do cols[#cols + 1] = v end
    local axis = nil
    for n = 1, AXIS_COUNT do
      if AXIS_NAMES[n] == cols[3] then axis = n end
    end
    local isRow = axis ~= nil and #cols == #FIELDS + 3
    if not isRow and lastWasRow then
      -- A mark belongs to the flight whose row is just before it
      local markDate, markSeconds = markOf(lines[i])
      if markDate then current.contains = {date = markDate, seconds = markSeconds} end
    end
    lastWasRow = isRow
    if isRow then
      if not current or current.date ~= cols[1] or current.axes[axis] then
        current = {date = cols[1], seconds = tonumber(cols[2]) or 0, axes = {}}
        flights[#flights + 1] = current
      end
      local a = newAxis()
      for n, f in ipairs(FIELDS) do
        local v = tonumber(cols[n + 3]) or 0
        if f.band then a[f.band][f.index][f[2]] = v else a[f[2]] = v end
      end
      current.axes[axis] = a
    end
  end
  return flights
end

-- Flights are combined only on the same tune and the same PID and rate profile, and only when
-- both profiles are known: two profiles can hold the same P, F, B and RC Rate and differ in
-- everything else (rfsuite #2785). The profiles are not TUNE_KEYS, which Apply checks on the FC.
local function sameTune(a, b)
  for _, k in ipairs(TUNE_KEYS) do
    if a[k] ~= b[k] then return false end
  end
  if (a.pidProfile or 0) < 1 or (a.rateProfile or 0) < 1 then return false end
  return a.pidProfile == b.pidProfile and a.rateProfile == b.rateProfile
end

-- weighted running mean: adds value v with weight w to out[key] over total
local function addMean(out, key, v, w, total)
  if total > 0 then out[key] = out[key] + (v - out[key]) * w / total end
end

local function addBand(bands, src)
  for i = 1, BAND_COUNT do
    local b, s = bands[i], src[i]
    b.count = b.count + s.count
    addMean(b, "gain", s.gain, s.count, b.count)
  end
end

-- Adds one flight's axis table `a` to the running total `out`
local function addFlight(out, a)
  out.ffCount = out.ffCount + a.ffCount
  addMean(out, "ffGain", a.ffGain, a.ffCount, out.ffCount)
  addMean(out, "ffCorr", a.ffCorr, a.ffCount, out.ffCount)
  addMean(out, "ffLagMs", a.ffLagMs, a.ffCount, out.ffCount)
  addBand(out.spBands, a.spBands)
  addBand(out.thrBands, a.thrBands)

  out.fullCount = out.fullCount + a.fullCount
  out.fullSatCount = out.fullSatCount + a.fullSatCount
  addMean(out, "fullRatio", a.fullRatio, a.fullCount, out.fullCount)
  if a.fullMaxRate > out.fullMaxRate then out.fullMaxRate = a.fullMaxRate end

  out.releases = out.releases + a.releases
  out.bigRebounds = out.bigRebounds + a.bigRebounds
  addMean(out, "meanRebound", a.meanRebound, a.releases, out.releases)
  addMean(out, "meanOvershoot", a.meanOvershoot, a.releases, out.releases)
  addMean(out, "meanCounter", a.meanCounter, a.releases, out.releases)
  addMean(out, "meanIterm", a.meanIterm, a.releases, out.releases)
end

-- One axis (1 roll, 2 pitch, 3 yaw) over the newest flights on the newest
-- flight's tune. Returns the combined axis table (shaped like a decoded reply's
-- `a`; all zeros with no flights), the flights used and their total seconds.
-- A flight that a counted newer one contains (a mark line) is left out: it
-- neither counts nor ends the count.
function tuneHistory.aggregate(flights, axis)
  local out = newAxis()
  local newest = flights[#flights] and flights[#flights].axes[axis]
  if not newest then return out, 0, 0 end
  for _, k in ipairs(TUNE_KEYS) do out[k] = newest[k] end

  local used, seconds = 0, 0
  local held = nil   -- "date|seconds" of the flights a counted one contains
  for i = #flights, 1, -1 do
    if used >= MAX_FLIGHTS then break end
    local flight = flights[i]
    local key = held and (tostring(flight.date) .. "|" .. tostring(flight.seconds))
    if key and held[key] then
      -- In the reading of a newer flight already counted: left out rather than
      -- counted twice, and what it holds in turn too
      held[key] = nil
      if flight.contains then held[flight.contains.date .. "|" .. tostring(flight.contains.seconds)] = true end
    else
      local a = flight.axes[axis]
      -- The newest flight always counts; an older one only on the same tune and profiles
      if not a or (i < #flights and not sameTune(a, newest)) then break end
      used = used + 1
      seconds = seconds + flight.seconds
      if flight.contains then
        held = held or {}
        held[flight.contains.date .. "|" .. tostring(flight.contains.seconds)] = true
      end
      addFlight(out, a)
    end
  end
  out.ffLagMs = math.floor(out.ffLagMs + 0.5)
  return out, used, seconds
end

package.loaded["wfsuite.lib.tune_history"] = tuneHistory
return tuneHistory
