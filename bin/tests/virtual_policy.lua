-- Run from the repository root with Lua 5.3+: lua bin/tests/virtual_policy.lua
-- When tasks/msp/virtual.lua answers a request itself, and how MSP2_WING_BUILD_ID
-- reports a build without a config catalogue. The codecs are stubs: only their
-- kind byte (reply 0, setter 1) and index width matter to the policy, so the
-- answer itself (expand) is recorded instead of built.
local function eq(a, b, what) assert(a == b, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

package.loaded["wfsuite.lib.require"] = function() return {} end
local Virtual = assert(loadfile("src/wfsuite/tasks/msp/virtual.lua"))()
local buildId = assert(loadfile("src/wfsuite/lib/msp_build_id.lua"))()

local REPLY, SETTER = 101, 201
local CODEC_REPLY = string.char(0, 0) .. string.rep("\0", 8)    -- kind 0, no index
local CODEC_SETTER = string.char(1, 0) .. string.rep("\0", 8)   -- kind 1

local function layer(authoritative, writes)
  local v = Virtual.new({ codecs = { [REPLY] = CODEC_REPLY, [SETTER] = CODEC_SETTER } })
  v.authoritative, v.writes = authoritative, writes
  v.expanded = {}
  function v:expand(msg) self.expanded[#self.expanded + 1] = msg.command end
  return v
end

-- Verifying layer (a build with its catalogue): the firmware answers first.
local v = layer(false, false)
local msg = { command = REPLY, processReply = function() end }
eq(v:intercept(msg, {}), false, "first reply request goes to the firmware")
eq(#v.expanded, 0, "nothing answered locally before verification")
eq(v:intercept({ command = SETTER, payload = {1} }, {}), false, "setter without writes goes to the firmware")
eq(v:intercept({ command = 999 }, {}), false, "opcode without a codec goes to the firmware")

-- Authoritative layer (no config catalogue): answered at once, setters too.
v = layer(true, true)
eq(v:intercept({ command = REPLY }, {}), true, "reply answered locally at once")
eq(v:intercept({ command = SETTER, payload = {1} }, {}), true, "setter written through its codec at once")
eq(#v.expanded, 2, "both expanded")
eq(v:intercept({ command = 999 }, {}), false, "opcode without a codec still goes to the firmware")

-- MSP2_WING_BUILD_ID: U8 protocol, 8 id bytes, U16 capabilities, ...
local function reply(caps)
  local b = { 1, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, caps % 256, math.floor(caps / 256), 0, 0, 0, 0 }
  return b
end
local id, noCatalogue = buildId.decode(reply(2))
eq(id, "0123456789abcdef", "valid id"); eq(noCatalogue, false, "catalogue present")
id, noCatalogue = buildId.decode(reply(2 + 4))
eq(id, "0123456789abcdef", "valid id, no catalogue"); eq(noCatalogue, true, "no catalogue")
id, noCatalogue = buildId.decode(reply(4))
eq(id, nil, "placeholder id"); eq(noCatalogue, true, "no catalogue reported without an id too")
eq(buildId.decode({ 1, 2, 3 }), nil, "short reply")

print("virtual policy checks passed")
