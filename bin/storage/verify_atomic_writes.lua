-- Behaviour check for the write path behind settings and logs.
--
-- Run it:
--     lua5.4 bin/storage/verify_atomic_writes.lua

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local SUITE = ROOT .. "/src/wfsuite"

local failures = 0
local checks = 0

local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print(string.format("  ok    %s", label))
  else
    failures = failures + 1
    print(string.format("  FAIL  %s", label))
    if detail then print("        " .. tostring(detail)) end
  end
end

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

local function shellQuote(s)
  if IS_WINDOWS then return '"' .. s .. '"' end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function makeDir(path)
  if IS_WINDOWS then
    os.execute("mkdir " .. shellQuote(path) .. " 2>nul")
  else
    os.execute("mkdir -p " .. shellQuote(path))
  end
end

local function removeTree(path)
  if IS_WINDOWS then
    os.execute("rmdir /s /q " .. shellQuote(path:gsub("/", "\\")) .. " 2>nul")
  else
    os.execute("rm -rf " .. shellQuote(path))
  end
end

local SCRATCH_ROOT = (os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP")
  or (IS_WINDOWS and "." or "/tmp")) .. "/wfsuite_atomic_writes"
removeTree(SCRATCH_ROOT)
makeDir(SCRATCH_ROOT)

local realIoRead = io.read
io.read = function(a, b)
  if type(a) == "userdata" and (b == "L" or b == "l" or b == "*l") then return a:read("l") end
  return realIoRead(a, b)
end

package.loaded["wfsuite.lib.require"] = function(name)
  local key = "wfsuite." .. name:gsub("%.lua$", ""):gsub("/", ".")
  local cached = package.loaded[key]
  if cached ~= nil then return cached end
  local chunk, err = loadfile(SUITE .. "/" .. name)
  if not chunk then error(err) end
  local ok, result = pcall(chunk)
  if not ok then error(result) end
  package.loaded[key] = (result == nil) and true or result
  return package.loaded[key]
end

local requireModule = package.loaded["wfsuite.lib.require"]
local ini = requireModule("lib/ini.lua")
local atomicWrite = requireModule("lib/atomic_write.lua")

local function pathFor(name)
  return SCRATCH_ROOT .. "/" .. name
end

local function readFile(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("a")
  file:close()
  return data
end

local function sizeOf(path)
  local data = readFile(path)
  return data and #data or -1
end

local function seed(path, content)
  local file = assert(io.open(path, "w"))
  file:write(content)
  file:close()
end

local function recordWriteHandles(watched, observed, run)
  local realOpen = io.open
  io.open = function(name, mode)
    local handle = realOpen(name, mode)
    if handle and (mode == "w" or mode == "wb") then
      observed[#observed + 1] = {
        path = name,
        sizeAtOpen = sizeOf(name),
        watchedAtOpen = watched and sizeOf(watched) or nil,
      }
    end
    return handle
  end
  local ok, err = pcall(run)
  io.open = realOpen
  if not ok then error(err) end
end

local function openedPaths(observed)
  local names = {}
  for _, o in ipairs(observed) do names[#names + 1] = tostring(o.path) end
  return table.concat(names, ", ")
end

local function onlyTempFiles(observed)
  if #observed == 0 then return false end
  for _, o in ipairs(observed) do
    if not tostring(o.path):match("%.tmp$") then return false end
  end
  return true
end

local function settings(interval, extra)
  local data = {general = {log_sample_interval = interval}}
  if extra then
    for section, params in pairs(extra) do data[section] = params end
  end
  return data
end

print("1. a save of an existing file never truncates it")
do
  local path = pathFor("watched.ini")
  os.remove(path)
  os.remove(path .. ".tmp")
  seed(path, "[general]\nlog_sample_interval=3\n\n[events]\nvoltage=true\n\n")
  local seeded = sizeOf(path)

  local observed = {}
  recordWriteHandles(path, observed, function()
    check("save reports success", ini.save_ini_file(path, settings(9)) == true)
  end)

  check("the live settings file is never opened for writing", onlyTempFiles(observed),
    "opened: " .. openedPaths(observed))
  check("the live settings file still held its contents during the write",
    observed[1] ~= nil and observed[1].watchedAtOpen == seeded,
    "held " .. tostring(observed[1] and observed[1].watchedAtOpen) .. " of " .. seeded .. " bytes")
  check("no temp file is left behind", sizeOf(path .. ".tmp") == -1)
  local reloaded = ini.load_ini_file(path)
  check("the new value is in place", reloaded and reloaded.general
    and reloaded.general.log_sample_interval == 9)
end

print("2. a save that is interrupted leaves the previous file complete")
do
  local path = pathFor("interrupted.ini")
  os.remove(path)
  os.remove(path .. ".tmp")
  ini.save_ini_file(path, settings(7, {events = {voltage = true, becalertvalue = 6.5}}))
  local before = readFile(path)

  local handle = assert(atomicWrite.stage(path))
  handle:write("[general]\nlog_sample_interval=1\n")
  handle:close()

  check("a half-written temp file is what is left on the card", sizeOf(path .. ".tmp") > 0)
  check("the live file is byte-identical to before the write", readFile(path) == before)
  check("the live file was not truncated", sizeOf(path) == #before and #before > 0)
  local reloaded = ini.load_ini_file(path)
  check("the live file still parses with its previous values",
    reloaded and reloaded.general and reloaded.general.log_sample_interval == 7)
end

print("3. the next save cleans up after an interrupted one")
do
  local path = pathFor("interrupted.ini")
  check("save after a crash reports success", ini.save_ini_file(path, settings(4)) == true)
  local reloaded = ini.load_ini_file(path)
  check("the new value is in place, not the truncated temp's",
    reloaded and reloaded.general and reloaded.general.log_sample_interval == 4)
  check("no temp file is left behind", sizeOf(path .. ".tmp") == -1)
  check("only one file exists for this target", sizeOf(path) > 0)
end

print("4. a rename that refuses to overwrite an existing file")
do
  local path = pathFor("rename.ini")
  os.remove(path)
  os.remove(path .. ".tmp")
  ini.save_ini_file(path, settings(1))

  local realRename = os.rename
  os.rename = function(old, new)
    if sizeOf(new) >= 0 then return nil, "EEXIST" end
    return realRename(old, new)
  end
  local ok = ini.save_ini_file(path, settings(2))
  os.rename = realRename

  check("save still reports success", ok == true)
  local reloaded = ini.load_ini_file(path)
  check("the second save's value is in place",
    reloaded and reloaded.general and reloaded.general.log_sample_interval == 2,
    reloaded and reloaded.general and reloaded.general.log_sample_interval)
  check("no temp file is left behind", sizeOf(path .. ".tmp") == -1)
end

print("5. a radio build without os.rename at all")
do
  local path = pathFor("norename.ini")
  os.remove(path)
  os.remove(path .. ".tmp")
  local realRename = os.rename
  os.rename = nil

  local shimmedIoRead = io.read
  io.read = realIoRead
  local first = ini.save_ini_file(path, settings(4))
  local second = ini.save_ini_file(path, settings(5))
  io.read = shimmedIoRead
  os.rename = realRename

  check("a fresh save still succeeds", first == true)
  check("an overwrite still succeeds", second == true)
  local reloaded = ini.load_ini_file(path)
  check("the overwrite's value is in place",
    reloaded and reloaded.general and reloaded.general.log_sample_interval == 5,
    reloaded and reloaded.general and reloaded.general.log_sample_interval)
  check("no temp file is left behind", sizeOf(path .. ".tmp") == -1)
end

print("6. a write that fails part way through")
do
  local path = pathFor("boom.ini")
  os.remove(path)
  os.remove(path .. ".tmp")
  ini.save_ini_file(path, settings(9))
  local before = readFile(path)

  local exploding = setmetatable({}, {__tostring = function() error("write failed") end})
  local ok = ini.save_ini_file(path, {general = {log_sample_interval = 10}, evil = {boom = exploding}})

  check("save reports failure", ok == false)
  check("the live file is untouched", readFile(path) == before)
  check("the live file still holds its previous value", (readFile(path) or ""):match("log_sample_interval=9") ~= nil)
  check("the abandoned temp file is removed", sizeOf(path .. ".tmp") == -1)
end

print("7. a log header is staged the same way a settings file is")
do
  local path = pathFor("2026-01-01_00-00-00.csv")
  os.remove(path)
  os.remove(path .. ".tmp")
  local observed = {}
  recordWriteHandles(path, observed, function()
    check("writing the header reports success",
      atomicWrite.write(path, "time, voltage\n") == true)
  end)
  check("the CSV is not opened for writing directly", onlyTempFiles(observed),
    "opened: " .. openedPaths(observed))
  check("the header is in place afterwards", (readFile(path) or ""):match("^time, voltage") ~= nil,
    string.format("read back %q", tostring(readFile(path))))
  check("no temp file is left behind", sizeOf(path .. ".tmp") == -1)
end

removeTree(SCRATCH_ROOT)

print()
if failures == 0 then
  print(string.format("all %d checks passed", checks))
  os.exit(0)
end
print(string.format("%d of %d checks FAILED", failures, checks))
os.exit(1)
