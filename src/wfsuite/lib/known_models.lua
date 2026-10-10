-- Lists the flight controller configuration stores recorded on the radio SD card
-- (lib/model_preferences.lua), with no active connection.
--
-- What it reads:
--   * models/<id>.ini files under this suite's root folder
--   * each file's craft name (lib/model_preferences.lua's craftNameOf())
--   * each file's modification timestamp (os.stat().mtime)
--
-- Loaded on demand only (never at boot). Each record is { id, name, path, modified }.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ini = requireModule("lib/ini.lua")
local modelPreferences = requireModule("lib/model_preferences.lua")

local known_models = {}

local function modifiedOf(path)
  if not (os and os.stat) then return nil end
  local ok, info = pcall(os.stat, path)
  if not ok or type(info) ~= "table" or type(info.mtime) ~= "table" then return nil end
  local m = info.mtime
  return { year = m.year, month = m.month, day = m.day, hour = m.hour, minute = m.minute, second = m.second }
end

function known_models.list()
  local out = {}
  if not (system and system.listFiles) then return out end

  local ok, files = pcall(system.listFiles, modelPreferences.MODELS_DIR)
  if not ok or type(files) ~= "table" then return out end

  local ids = {}
  for i = 1, #files do
    -- "<id>.ini" only. The listing also carries "..", sub-directories and the ".tmp" a
    -- write in flight leaves behind (lib/atomic_write.lua), none of which end in ".ini".
    local id = type(files[i]) == "string" and files[i]:match("^(.+)%.ini$") or nil
    if id then ids[#ids + 1] = id end
  end

  -- The bare sort: the comparison happens in C, and the order must not depend on how the
  -- firmware happens to list the directory.
  table.sort(ids)

  for i = 1, #ids do
    -- The file as it is called, not as pathFor() would spell the id: a name this suite
    -- never wrote is read from where it is.
    local path = modelPreferences.MODELS_DIR .. "/" .. ids[i] .. ".ini"
    -- A store that will not parse is still a store: the record stays, without a name.
    local parsed, raw = pcall(ini.load_ini_file, path)
    out[i] = {
      id = ids[i],
      name = parsed and modelPreferences.craftNameOf(raw) or nil,
      path = path,
      modified = modifiedOf(path),
    }
  end

  return out
end

return known_models
