-- Crash-safe file replacement for the files WFSuite owns on the SD card.
--
-- io.open(path, "w") truncates the target on open. Stage content in a sibling
-- temp file, flush and close it, and only then swap it into place so an
-- interrupted write leaves the previous file intact.

if package.loaded["wfsuite.lib.atomic_write"] then
  return package.loaded["wfsuite.lib.atomic_write"]
end

local atomicWrite = {}

function atomicWrite.tempPath(path)
  return path .. ".tmp"
end

local function fileExists(path)
  local file = io.open(path, "rb")
  if not file then return false end
  pcall(function() file:close() end)
  return true
end

local function writeDirect(path, data)
  local file = io.open(path, "w")
  if not file then return false end
  local ok = pcall(function()
    file:write(data)
    if file.flush then file:flush() end
  end)
  pcall(function() file:close() end)
  return ok
end

local function readWholeFile(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local content = nil
  if file.read then
    local ok, res = pcall(function() return file:read("*a") end)
    if ok and type(res) == "string" then
      content = res
    end
  end
  if content == nil then
    if file.seek then pcall(function() file:seek("set", 0) end) end
    local chunks = {}
    while true do
      local ok, chunk = pcall(io.read, file, "L")
      if not ok or not chunk then break end
      if not chunk:match("\n$") then chunk = chunk .. "\n" end
      chunks[#chunks + 1] = chunk
    end
    content = table.concat(chunks)
  end
  pcall(function() file:close() end)
  return content
end

function atomicWrite.discardTemp(path)
  if not (os and os.remove) or type(path) ~= "string" or path == "" then return false end
  local ok, res = pcall(os.remove, atomicWrite.tempPath(path))
  return (ok and res) and true or false
end

function atomicWrite.stage(path)
  if type(path) ~= "string" or path == "" then return nil end
  return io.open(atomicWrite.tempPath(path), "w")
end

function atomicWrite.commit(handle, path)
  if not handle then return false end
  if type(path) ~= "string" or path == "" then return false end

  local closed = pcall(function()
    if handle.flush then handle:flush() end
    handle:close()
  end)
  if not closed then return false end

  local temp = atomicWrite.tempPath(path)

  if not (os and os.rename) then
    local data = readWholeFile(temp)
    if not data then return false end
    local ok = writeDirect(path, data)
    atomicWrite.discardTemp(path)
    return ok
  end

  pcall(os.rename, temp, path)

  if fileExists(temp) then
    pcall(os.remove, path)
    pcall(os.rename, temp, path)
  end

  if fileExists(temp) then
    local data = readWholeFile(temp)
    local ok = data ~= nil and writeDirect(path, data)
    if ok then atomicWrite.discardTemp(path) end
    return ok == true
  end

  return true
end

function atomicWrite.abort(handle, path)
  if handle then pcall(function() handle:close() end) end
  if type(path) == "string" then atomicWrite.discardTemp(path) end
end

function atomicWrite.write(path, data)
  local handle = atomicWrite.stage(path)
  if not handle then return false end
  local ok = pcall(function() handle:write(tostring(data or "")) end)
  if not ok then
    atomicWrite.abort(handle, path)
    return false
  end
  return atomicWrite.commit(handle, path)
end

package.loaded["wfsuite.lib.atomic_write"] = atomicWrite
return atomicWrite
