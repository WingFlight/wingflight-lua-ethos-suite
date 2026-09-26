-- Legacy MSP config opcodes, answered from addressed parameter access.
--
-- Step 5 of the firmware's parameter-addressing-design.md deletes the
-- hand-written MSP config catalogue. This suite's pages speak it (lib/msp_*.lua
-- build legacy requests and decode legacy replies), so instead of rewriting
-- every page, the MSP queue hands requests for opcodes it has a codec for to
-- this module, which answers them itself: a reply is assembled from
-- MSP2_WING_PARAM_READs, a setter becomes MSP2_WING_PARAM_WRITEs. Pages and
-- their decoders see the same bytes the firmware's own opcode returned.
--
-- It is the Lua twin of the configurator's src/js/param/virtual_msp.js, and
-- must produce the same bytes (bin/tests/msp-virtual compares the two). What each
-- opcode's bytes mean comes from the codec pack for the exact firmware build
-- (codecs/<build id>.lua, made by the firmware's src/utils/wf_lua_pack.py,
-- which documents the binary op encoding). Opcodes without a codec are not
-- handled here and go to the firmware as before.
--
-- Arithmetic only, no bitwise operators, like lib/mspcodec.lua, so it runs
-- unmodified on every Lua the radio may have.
--
-- How a request is answered: expand() turns the legacy message into a short
-- chain of ordinary queue messages (PARAM_READ / PARAM_WRITE), each put at
-- the *front* of the queue so the job completes before anything queued
-- behind it. Each sub-message's reply queues the next; the last delivers the
-- assembled reply to the original message's processReply. Retries, timeouts
-- and transports are the queue's, unchanged. Any failure reaches the original
-- message's errorHandler.

local Virtual = {}
Virtual.__index = Virtual

local PARAM_READ = 0x5F22
local PARAM_WRITE = 0x5F23
local SYSTEM_CONFIG_PGN = 18
local CHUNK = 128 -- MSP-over-telemetry buffers are 192 in / 320 out

-- op flags (wf_lua_pack.py)
local F_OPTIONAL, F_INDEXED, F_SIGNED, F_WIRE_SIGNED = 1, 2, 4, 8
local F_PID, F_RATE, F_TV, F_CHECK = 16, 32, 64, 128

local floor = math.floor

local function hasFlag(flags, bit)
  return floor(flags / bit) % 2 == 1
end

-- Little-endian unsigned integer from a string at 1-based `pos`.
local function strUInt(s, pos, n)
  local v = 0
  for i = n - 1, 0, -1 do
    v = v * 256 + s:byte(pos + i)
  end
  return v
end

local function toSigned(v, n)
  local half = 2 ^ (8 * n - 1)
  if v >= half then return v - 2 * half end
  return v
end

-- Little-endian integer from a byte table at 1-based `pos`.
local function tabUInt(t, pos, n)
  local v = 0
  for i = n - 1, 0, -1 do
    v = v * 256 + (t[pos + i] or 0)
  end
  return v
end

-- Append the two's complement of `value` as `n` little-endian bytes.
local function putInt(out, value, n)
  local m = 2 ^ (8 * n)
  value = value % m -- Lua's % is floored, so negatives wrap as in C
  for _ = 1, n do
    out[#out + 1] = floor(value % 256)
    value = floor(value / 256)
  end
end

-- Decode one codec string into a header and a list of op tables.
local function decode(s)
  local codec = {
    dir = s:byte(1),
    indexW = s:byte(2),
    indexMax = strUInt(s, 3, 2),
    lenKind = s:byte(5),
    len = strUInt(s, 6, 2),
    ops = {},
  }
  local nops = strUInt(s, 8, 2)
  local p = 10
  for i = 1, nops do
    local kind = s:byte(p)
    local op
    if kind == 1 then
      op = { kind = 1, w = s:byte(p + 1), pgn = strUInt(s, p + 2, 2), off = strUInt(s, p + 4, 2),
             size = s:byte(p + 6), flags = s:byte(p + 7) }
      p = p + 8
      if hasFlag(op.flags, F_CHECK) then
        op.min = toSigned(strUInt(s, p, 4), 4)
        op.max = toSigned(strUInt(s, p + 4, 4), 4)
        p = p + 8
      end
    elseif kind == 2 then
      op = { kind = 2, w = s:byte(p + 1), value = toSigned(strUInt(s, p + 2, 4), 4), flags = 0 }
      p = p + 6
    elseif kind == 3 then
      op = { kind = 3, w = s:byte(p + 1), flags = s:byte(p + 2) }
      p = p + 3
    elseif kind == 4 then
      op = { kind = 4, len = strUInt(s, p + 1, 2), pgn = strUInt(s, p + 3, 2), off = strUInt(s, p + 5, 2),
             flags = s:byte(p + 7) }
      p = p + 8
    else
      return nil, "unknown op kind " .. tostring(kind)
    end
    codec.ops[i] = op
  end
  return codec
end

local function needsSelection(codec)
  for i = 1, #codec.ops do
    local f = codec.ops[i].flags
    if hasFlag(f, F_PID) or hasFlag(f, F_RATE) or hasFlag(f, F_TV) then return true end
  end
  return false
end

function Virtual.new(pack)
  return setmetatable({ pack = pack }, Virtual)
end

-- Load the pack for a build ID; nil (and the reason) if the suite has none.
function Virtual.load(buildId, dir)
  local path = (dir or "codecs/") .. tostring(buildId) .. ".lua"
  local chunk = loadfile(path)
  if not chunk then return nil, "no codec pack " .. path end
  local ok, pack = pcall(chunk)
  if not ok or type(pack) ~= "table" or pack.build ~= buildId then
    return nil, "codec pack " .. path .. " is not for build " .. tostring(buildId)
  end
  return Virtual.new(pack)
end

function Virtual:handles(msg)
  local s = self.pack.codecs[msg.command]
  if not s then return false end
  -- A reply codec answers a plain request only; a request with arguments
  -- (a page, an index) is not what the codec describes.
  if s:byte(1) == 0 and msg.payload and #msg.payload > 0 then return false end
  return true
end

-- Byte offset of an op in its group, for the selection / element index.
function Virtual:offset(op, selection, index)
  local g = self.pack.groups[op.pgn]
  local elem = floor(g[1] / g[2])
  local f = op.flags
  if hasFlag(f, F_PID) then return op.off + selection.pid * elem end
  if hasFlag(f, F_RATE) then return op.off + selection.rate * elem end
  if hasFlag(f, F_TV) then return op.off + selection.tv * elem end
  if hasFlag(f, F_INDEXED) then return op.off + index * elem end
  return op.off
end

-- Build the chain for `msg` and put its first step at the front of the queue.
function Virtual:expand(msg, queue)
  local codec, err = decode(self.pack.codecs[msg.command])
  if not codec then
    if msg.errorHandler then msg.errorHandler(err) end
    return
  end

  local job = { selection = nil, bytes = {} }

  local function fail(reason)
    if msg.errorHandler then msg.errorHandler(reason) end
  end

  local function push(step)
    table.insert(queue.pending, 1, step)
  end

  local run -- run(i): queue step i, or finish

  local function readStep(pgn, off, len, store)
    return {
      command = PARAM_READ,
      payload = { pgn % 256, floor(pgn / 256), off % 256, floor(off / 256), len % 256, floor(len / 256) },
      processReply = function(_, buf)
        if not buf or #buf < len then return fail("param_read_short") end
        store(buf)
      end,
      errorHandler = fail,
    }
  end

  local function writeStep(pgn, off, bytes, after)
    local payload = { pgn % 256, floor(pgn / 256), off % 256, floor(off / 256) }
    for i = 1, #bytes do payload[#payload + 1] = bytes[i] end
    return {
      command = PARAM_WRITE,
      payload = payload,
      isWrite = true,
      processReply = function() after() end,
      errorHandler = fail,
    }
  end

  -- The board's profile selection, when the codec addresses a profile.
  local function withSelection(continue)
    if not needsSelection(codec) then return continue() end
    local sel = self.pack.selection
    local lo = math.min(sel.pid, sel.rate, sel.tv)
    local hi = math.max(sel.pid, sel.rate, sel.tv)
    push(readStep(SYSTEM_CONFIG_PGN, lo, hi - lo + 1, function(buf)
      job.selection = { pid = buf[sel.pid - lo + 1], rate = buf[sel.rate - lo + 1], tv = buf[sel.tv - lo + 1] }
      continue()
    end))
  end

  if codec.dir == 0 then
    -- Reply: read the span each group needs, then assemble.
    withSelection(function()
      local placed, spans, order = {}, {}, {}
      for i = 1, #codec.ops do
        local op = codec.ops[i]
        if op.kind == 1 or op.kind == 4 then
          local at = self:offset(op, job.selection, 0)
          local len = op.kind == 1 and op.size or op.len
          placed[i] = at
          local s = spans[op.pgn]
          if not s then
            spans[op.pgn] = { lo = at, hi = at + len }
            order[#order + 1] = op.pgn
          else
            if at < s.lo then s.lo = at end
            if at + len > s.hi then s.hi = at + len end
          end
        end
      end

      local reads = {}
      for _, pgn in ipairs(order) do
        local s = spans[pgn]
        local at = s.lo
        while at < s.hi do
          local len = math.min(CHUNK, s.hi - at)
          reads[#reads + 1] = { pgn = pgn, off = at, len = len }
          at = at + len
        end
      end

      local function assemble()
        local out = {}
        for i = 1, #codec.ops do
          local op = codec.ops[i]
          if op.kind == 2 then
            putInt(out, op.value, op.w)
          elseif op.kind == 1 then
            local v = tabUInt(job.bytes[op.pgn], placed[i] + 1, op.size)
            if hasFlag(op.flags, F_SIGNED) then v = toSigned(v, op.size) end
            putInt(out, v, op.w) -- C: sign-extend signed fields, zero-extend unsigned
          elseif op.kind == 4 then
            local b = job.bytes[op.pgn]
            for k = 1, op.len do out[#out + 1] = b[placed[i] + k] or 0 end
          end
        end
        if msg.processReply then msg.processReply(msg, out) end
      end

      local i = 0
      run = function()
        i = i + 1
        local r = reads[i]
        if not r then return assemble() end
        push(readStep(r.pgn, r.off, r.len, function(buf)
          local g = job.bytes[r.pgn]
          if not g then g = {}; job.bytes[r.pgn] = g end
          for k = 1, r.len do g[r.off + k] = buf[k] end
          run()
        end))
      end
      run()
    end)
    return
  end

  -- Setter: parse the payload as the firmware would, refuse where it did.
  local data = msg.payload or {}
  local n = #data
  if codec.lenKind == 1 and n ~= codec.len then return fail("refused") end
  if codec.lenKind == 2 and n < codec.len then return fail("refused") end
  local pos = 1
  local index = 0
  if codec.indexW > 0 then
    if n < codec.indexW then return fail("refused") end
    index = tabUInt(data, 1, codec.indexW)
    pos = 1 + codec.indexW
    if index >= codec.indexMax then return fail("refused") end
  end

  withSelection(function()
    local patches, order = {}, {}
    for i = 1, #codec.ops do
      local op = codec.ops[i]
      local w = op.w
      if pos + w - 1 > n then
        if not hasFlag(op.flags, F_OPTIONAL) then return fail("refused") end
      elseif op.kind == 3 then
        pos = pos + w
      elseif op.kind == 1 then
        local v = tabUInt(data, pos, w)
        if hasFlag(op.flags, F_WIRE_SIGNED) then v = toSigned(v, w) end
        pos = pos + w
        if op.min and (v < op.min or v > op.max) then return fail("refused") end
        local bytes = {}
        putInt(bytes, v, op.size) -- the store truncates to the field
        local at = self:offset(op, job.selection, index)
        local p = patches[op.pgn]
        if not p then p = {}; patches[op.pgn] = p; order[#order + 1] = op.pgn end
        for k = 1, op.size do p[at + k - 1] = bytes[k] end
      else
        return fail("refused")
      end
    end

    -- Contiguous runs, in chunks the telemetry buffers take.
    local writes = {}
    for _, pgn in ipairs(order) do
      local p = patches[pgn]
      local offs = {}
      for off in pairs(p) do offs[#offs + 1] = off end
      table.sort(offs)
      local s = 1
      while s <= #offs do
        local e = s
        while e < #offs and offs[e + 1] == offs[e] + 1 and e - s + 1 < CHUNK do e = e + 1 end
        local bytes = {}
        for k = s, e do bytes[#bytes + 1] = p[offs[k]] end
        writes[#writes + 1] = { pgn = pgn, off = offs[s], bytes = bytes }
        s = e + 1
      end
    end

    local i = 0
    run = function()
      i = i + 1
      local w = writes[i]
      if not w then
        if msg.processReply then msg.processReply(msg, {}) end
        return
      end
      push(writeStep(w.pgn, w.off, w.bytes, run))
    end
    run()
  end)
end

-- Should the queue hand `msg` to expand()? The policy: a reply opcode is
-- answered here only once this connection has seen the firmware's own reply
-- to it match what expand() builds, byte for byte. The first request for an
-- opcode goes to the firmware as always -- the page gets the real reply at
-- once -- and the comparison runs behind it. Setters are not taken yet: the
-- firmware still has them, and a wrong setter would write, not just show,
-- the wrong bytes (the configurator gates them the same way).
function Virtual:intercept(msg, queue)
  if not self:handles(msg) then return false end
  local cmd = msg.command
  if self.pack.codecs[cmd]:byte(1) ~= 0 then return false end
  self.verified = self.verified or {}
  local state = self.verified[cmd]
  if state == true then
    self:expand(msg, queue)
    return true
  end
  if state == nil then
    self.verified[cmd] = "pending"
    local original = msg.processReply
    msg.processReply = function(m, buf)
      -- Copy first: a transport may reuse its receive buffer.
      local real = {}
      for i = 1, #(buf or {}) do real[i] = buf[i] end
      if original then original(m, buf) end
      self:expand({
        command = cmd,
        processReply = function(_, mine)
          local same = #mine == #real
          for i = 1, #real do
            if not same then break end
            same = mine[i] == real[i]
          end
          self.verified[cmd] = same
          if self.onVerified then self.onVerified(cmd, same) end
        end,
        errorHandler = function(reason)
          self.verified[cmd] = false
          if self.onVerified then self.onVerified(cmd, false, reason) end
        end,
      }, queue)
    end
  end
  return false
end


return Virtual
