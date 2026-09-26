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
local PACK_FORMAT = 2

-- op kinds (wf_lua_pack.py)
local K_FIELD, K_CONST, K_SKIP, K_DATA, K_SELECT, K_STR_OUT, K_STR_IN = 1, 2, 3, 4, 5, 6, 7

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

-- Decode one codec string into a header and a list of op tables. Every op
-- that touches a group gets `size` (its bytes there); every op gets `w` (its
-- request/reply bytes; 0 for a string, whose length varies).
local function decode(s)
  local codec = {
    dir = s:byte(1),
    indexW = s:byte(2),
    indexMax = strUInt(s, 3, 2),
    indexStride = strUInt(s, 5, 2),
    lenKind = s:byte(7),
    len = strUInt(s, 8, 2),
    ops = {},
  }
  local nops = strUInt(s, 10, 2)
  local p = 12
  for i = 1, nops do
    local kind = s:byte(p)
    local op
    if kind == K_FIELD then
      op = { kind = kind, w = s:byte(p + 1), pgn = strUInt(s, p + 2, 2), off = strUInt(s, p + 4, 2),
             size = s:byte(p + 6), flags = s:byte(p + 7) }
      p = p + 8
      if hasFlag(op.flags, F_CHECK) then
        op.min = toSigned(strUInt(s, p, 4), 4)
        op.max = toSigned(strUInt(s, p + 4, 4), 4)
        p = p + 8
      end
    elseif kind == K_CONST then
      op = { kind = kind, w = s:byte(p + 1), value = toSigned(strUInt(s, p + 2, 4), 4), flags = 0 }
      p = p + 6
    elseif kind == K_SKIP then
      op = { kind = kind, w = s:byte(p + 1), flags = s:byte(p + 2) }
      p = p + 3
    elseif kind == K_DATA then
      local len = strUInt(s, p + 1, 2)
      op = { kind = kind, w = len, size = len, pgn = strUInt(s, p + 3, 2), off = strUInt(s, p + 5, 2),
             flags = s:byte(p + 7) }
      p = p + 8
    elseif kind == K_SELECT then
      op = { kind = kind, w = s:byte(p + 1), pgn = strUInt(s, p + 2, 2), off = strUInt(s, p + 4, 2),
             size = s:byte(p + 6), flags = s:byte(p + 7),
             selPgn = strUInt(s, p + 8, 2), selOff = strUInt(s, p + 10, 2), selSize = s:byte(p + 12),
             stride = strUInt(s, p + 13, 2), count = strUInt(s, p + 15, 2) }
      p = p + 17
    elseif kind == K_STR_OUT then
      op = { kind = kind, w = 0, size = strUInt(s, p + 1, 2), pgn = strUInt(s, p + 3, 2),
             off = strUInt(s, p + 5, 2), flags = s:byte(p + 7) }
      p = p + 8
    elseif kind == K_STR_IN then
      op = { kind = kind, w = 0, max = strUInt(s, p + 1, 2), size = strUInt(s, p + 3, 2),
             pgn = strUInt(s, p + 5, 2), off = strUInt(s, p + 7, 2), flags = s:byte(p + 9) }
      p = p + 10
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

-- The index a request selects (its first bytes), or nil where the firmware
-- refuses the request's length or index.
local function requestIndex(codec, data)
  local n = #data
  if codec.lenKind == 1 and n ~= codec.len then return nil end
  if codec.lenKind == 2 and n < codec.len then return nil end
  if codec.indexW == 0 then return 0 end
  if n < codec.indexW then return nil end
  local index = tabUInt(data, 1, codec.indexW)
  if index >= codec.indexMax then return nil end
  return index
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
  if pack.format ~= PACK_FORMAT then
    return nil, "codec pack " .. path .. " is format " .. tostring(pack.format) .. ", not " .. PACK_FORMAT
  end
  return Virtual.new(pack)
end

function Virtual:handles(msg)
  local s = self.pack.codecs[msg.command]
  if not s then return false end
  if s:byte(1) ~= 0 then return true end
  -- A reply codec answers a plain request, or one of exactly its index; other
  -- arguments (a page, a mode) are not what the codec describes.
  local n = msg.payload and #msg.payload or 0
  local indexW = s:byte(2)
  if indexW == 0 then return n == 0 end
  local want = s:byte(7) == 1 and strUInt(s, 8, 2) or indexW
  return n == want
end

-- Byte offset of an op in its group, for the selection / element index.
function Virtual:offset(codec, op, selection, index)
  local g = self.pack.groups[op.pgn]
  local elem = floor(g[1] / g[2])
  local f = op.flags
  if hasFlag(f, F_PID) then return op.off + selection.pid * elem end
  if hasFlag(f, F_RATE) then return op.off + selection.rate * elem end
  if hasFlag(f, F_TV) then return op.off + selection.tv * elem end
  if hasFlag(f, F_INDEXED) then
    local stride = codec.indexStride > 0 and codec.indexStride or elem
    return op.off + index * stride
  end
  return op.off
end

-- Build the chain for `msg` and put its first step at the front of the queue.
function Virtual:expand(msg, queue)
  local function fail(reason)
    if msg.errorHandler then msg.errorHandler(reason) end
  end

  local codec, err = decode(self.pack.codecs[msg.command])
  if not codec then return fail(err) end

  -- Parse the request as the firmware would, refuse where it did.
  local data = msg.payload or {}
  local index = requestIndex(codec, data)
  if not index then return fail("refused") end

  local job = { selection = nil, which = {}, bytes = {} }

  local function push(step)
    table.insert(queue.pending, 1, step)
  end

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

  -- Run `steps` (each queues a message and calls its continuation from the
  -- reply) one after another, then `done`.
  local function sequence(steps, done)
    local i = 0
    local function nextStep()
      i = i + 1
      if steps[i] then return steps[i](nextStep) end
      done()
    end
    nextStep()
  end

  -- What decides where ops land before their bytes are read: the board's
  -- profile selection, and each selected element's selector.
  local prepare = {}
  if needsSelection(codec) then
    prepare[#prepare + 1] = function(continue)
      local sel = self.pack.selection
      local lo = math.min(sel.pid, sel.rate, sel.tv)
      local hi = math.max(sel.pid, sel.rate, sel.tv)
      push(readStep(SYSTEM_CONFIG_PGN, lo, hi - lo + 1, function(buf)
        job.selection = { pid = buf[sel.pid - lo + 1], rate = buf[sel.rate - lo + 1], tv = buf[sel.tv - lo + 1] }
        continue()
      end))
    end
  end
  for i = 1, #codec.ops do
    local op = codec.ops[i]
    if op.kind == K_SELECT then
      prepare[#prepare + 1] = function(continue)
        push(readStep(op.selPgn, op.selOff, op.selSize, function(buf)
          job.which[i] = tabUInt(buf, 1, op.selSize)
          continue()
        end))
      end
    end
  end

  -- Offset of every op that touches a group, or nil and the reason.
  local function place()
    local placed = {}
    for i = 1, #codec.ops do
      local op = codec.ops[i]
      if op.pgn then
        local at = self:offset(codec, op, job.selection, index)
        if op.kind == K_SELECT then
          -- out of range, the firmware itself would read past the array
          if job.which[i] >= op.count then return nil, "selector_out_of_range" end
          at = at + job.which[i] * op.stride
        end
        if at + op.size > self.pack.groups[op.pgn][1] then return nil, "codec_out_of_range" end
        placed[i] = at
      end
    end
    return placed
  end

  local function reply(placed)
    -- Only the span of each group the reply needs.
    local spans, order = {}, {}
    for i = 1, #codec.ops do
      local op, at = codec.ops[i], placed[i]
      if at then
        local s = spans[op.pgn]
        if not s then
          spans[op.pgn] = { lo = at, hi = at + op.size }
          order[#order + 1] = op.pgn
        else
          if at < s.lo then s.lo = at end
          if at + op.size > s.hi then s.hi = at + op.size end
        end
      end
    end

    local reads = {}
    for _, pgn in ipairs(order) do
      local s = spans[pgn]
      local at = s.lo
      while at < s.hi do
        local off, len = at, math.min(CHUNK, s.hi - at)
        reads[#reads + 1] = function(continue)
          push(readStep(pgn, off, len, function(buf)
            local g = job.bytes[pgn]
            if not g then g = {}; job.bytes[pgn] = g end
            for k = 1, len do g[off + k] = buf[k] end
            continue()
          end))
        end
        at = at + len
      end
    end

    sequence(reads, function()
      local out = {}
      for i = 1, #codec.ops do
        local op = codec.ops[i]
        local b, at = job.bytes[op.pgn], placed[i]
        local kind = op.kind
        if kind == K_CONST then
          putInt(out, op.value, op.w)
        elseif (kind == K_FIELD or kind == K_SELECT) and op.w ~= op.size then
          local v = tabUInt(b, at + 1, op.size)
          if hasFlag(op.flags, F_SIGNED) then v = toSigned(v, op.size) end
          putInt(out, v, op.w) -- C: sign-extend signed fields, zero-extend unsigned
        elseif kind == K_FIELD or kind == K_SELECT or kind == K_DATA then
          -- the bytes as stored, whatever the width (64-bit fields too)
          for k = 1, op.size do out[#out + 1] = b[at + k] or 0 end
        elseif kind == K_STR_OUT then
          for k = 1, op.size do
            local c = b[at + k] or 0
            if c == 0 then break end
            out[#out + 1] = c
          end
        else
          return fail("op_in_reply")
        end
      end
      if msg.processReply then msg.processReply(msg, out) end
    end)
  end

  local function setter(placed)
    local n = #data
    local pos = 1 + codec.indexW
    local patches, order = {}, {}
    local function patch(pgn, at, bytes)
      local p = patches[pgn]
      if not p then p = {}; patches[pgn] = p; order[#order + 1] = pgn end
      for k = 1, #bytes do p[at + k - 1] = bytes[k] end
    end

    for i = 1, #codec.ops do
      local op = codec.ops[i]
      local w = op.w
      if op.kind == K_STR_IN then
        -- the field cleared, then what the request sent, at most max
        local take = math.min(op.max, n - pos + 1)
        local bytes = {}
        for k = 1, op.size do bytes[k] = 0 end
        for k = 1, take do bytes[k] = data[pos + k - 1] end
        pos = pos + take
        patch(op.pgn, placed[i], bytes)
      elseif pos + w - 1 > n then
        -- the firmware would read past the request; an optional tail is left out
        if not hasFlag(op.flags, F_OPTIONAL) then return fail("refused") end
      elseif op.kind == K_SKIP then
        pos = pos + w
      elseif op.kind ~= K_FIELD and op.kind ~= K_SELECT then
        return fail("op_in_setter")
      elseif w == op.size and not op.min then
        -- the bytes as sent, whatever the width (64-bit fields too)
        local bytes = {}
        for k = 1, w do bytes[k] = data[pos + k - 1] end
        pos = pos + w
        patch(op.pgn, placed[i], bytes)
      else
        local v = tabUInt(data, pos, w)
        if hasFlag(op.flags, F_WIRE_SIGNED) then v = toSigned(v, w) end
        pos = pos + w
        if op.min and (v < op.min or v > op.max) then return fail("refused") end
        local bytes = {}
        putInt(bytes, v, op.size) -- the store truncates to the field
        patch(op.pgn, placed[i], bytes)
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
        local off, bytes = offs[s], {}
        for k = s, e do bytes[#bytes + 1] = p[offs[k]] end
        writes[#writes + 1] = function(continue) push(writeStep(pgn, off, bytes, continue)) end
        s = e + 1
      end
    end

    sequence(writes, function()
      if msg.processReply then msg.processReply(msg, {}) end
    end)
  end

  sequence(prepare, function()
    local placed, reason = place()
    if not placed then return fail(reason) end
    if codec.dir == 0 then reply(placed) else setter(placed) end
  end)
end

-- Should the queue hand `msg` to expand()? The policy: a reply opcode is
-- answered here only once this connection has seen the firmware's own reply
-- to it match what expand() builds, byte for byte. The first request for an
-- opcode goes to the firmware as always -- the page gets the real reply at
-- once -- and the comparison runs behind it. An indexed reply is verified per
-- index, each being its own request. Setters are not taken yet: the firmware
-- still has them, and a wrong setter would write, not just show, the wrong
-- bytes (the configurator gates them the same way).
function Virtual:intercept(msg, queue)
  if not self:handles(msg) then return false end
  local cmd = msg.command
  if self.pack.codecs[cmd]:byte(1) ~= 0 then return false end
  local payload = {}
  for i = 1, #(msg.payload or {}) do payload[i] = msg.payload[i] end
  local key = #payload > 0 and (cmd .. ":" .. table.concat(payload, ",")) or cmd
  self.verified = self.verified or {}
  local state = self.verified[key]
  if state == true then
    self:expand(msg, queue)
    return true
  end
  if state == nil then
    self.verified[key] = "pending"
    local original = msg.processReply
    msg.processReply = function(m, buf)
      -- Copy first: a transport may reuse its receive buffer.
      local real = {}
      for i = 1, #(buf or {}) do real[i] = buf[i] end
      if original then original(m, buf) end
      self:expand({
        command = cmd,
        payload = payload,
        processReply = function(_, mine)
          local same = #mine == #real
          for i = 1, #real do
            if not same then break end
            same = mine[i] == real[i]
          end
          self.verified[key] = same
          if self.onVerified then self.onVerified(cmd, same) end
        end,
        errorHandler = function(reason)
          self.verified[key] = false
          if self.onVerified then self.onVerified(cmd, false, reason) end
        end,
      }, queue)
    end
  end
  return false
end

return Virtual
