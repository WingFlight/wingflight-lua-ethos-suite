// queue.lua + virtual.lua together, with a fake transport: verify-on-first-use.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const [cfgRoot, suiteRoot, packLua, manifestPath] = process.argv.slice(2);
const imp = (p) => import(pathToFileURL(`${cfgRoot}/${p}`).href);
const { Manifest } = await imp("src/js/param/manifest.js");
const { VirtualMsp } = await imp("src/js/param/virtual_msp.js");
const { MSPCodes } = await imp("src/js/msp/MSPCodes.js");

const manifest = new Manifest(JSON.parse(readFileSync(manifestPath, "utf8")));
let seed = 3;
const random = () => ((seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff) >>> 16) & 0xff;
const board = new Map(manifest.raw.pgs.map((pg) => [pg.pgn, Uint8Array.from({ length: pg.size }, () => random())]));
board.get(18).set([1, 2, 1], 5);
const js = new VirtualMsp(manifest, {
    async readRange(pgn, off, len) { return new DataView(board.get(pgn).buffer, off, len); },
    async writeRange() {},
});

// Opcodes to exercise: a reply with profile fields, a plain reply, and a setter.
const REPLY = MSPCodes.MSP_RC_TUNING;
const PLAIN = MSPCodes.MSP_ARMING_CONFIG;
const SETTER = MSPCodes.MSP_SET_ARMING_CONFIG;
const firmware = {
    [REPLY]: [...(await js.read(REPLY))],
    [PLAIN]: [...(await js.read(PLAIN))].map((b, i) => (i === 0 ? (b + 1) & 0xff : b)), // disagrees with the codec
};
// A reply indexed by its request's first byte (MSP_GET_*): the firmware's
// answer per index.
const [INDEXED, indexedCodec] = Object.entries(manifest.raw.msp_codecs).find(
    ([, c]) => c.dir === "out" && c.index?.w === 1 && (c.len ?? 1) === 1,
);
// Stage B: what the firmware's own setter stores for a request (applied by
// the fake transport), and one aimed elsewhere, as a wrong codec would see it.
const SETTER_PAYLOAD = [...(await js.read(MSPCodes.MSP_ARMING_CONFIG))].map((b) => (b + 1) & 0xff);
const setterRuns = await js.plan(SETTER, SETTER_PAYLOAD);
const luaRuns = (runs) => `{${runs.map((r) => `{${r.pgn},${r.offset},{${[...r.bytes].join(",")}}}`).join(",")}}`;
const firmwareIndexed = [];
for (let i = 0; i < 2; i++) firmwareIndexed.push([...(await js.read(Number(INDEXED), [i]))]);

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const lua_ = (src) => {
    if (lauxlib.luaL_dostring(L, to_luastring(src)) !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));
    const r = lua.lua_gettop(L) ? lua.lua_tojsstring(L, -1) : "";
    lua.lua_settop(L, 0);
    return r;
};
const S = suiteRoot.replace(/\\/g, "/");
lua_(`
  system = { getVersion = function() return { simulation = false } end }
  collectgarbage = function() return 0 end -- fengari has no GC control; the radio does
  local noop = function() end
  DEBUG = { msp = noop, print = noop }
  Queue = dofile("${S}/tasks/msp/queue.lua")
  Virtual = dofile("${S}/tasks/msp/virtual.lua")
  PACK = dofile("${packLua.replace(/\\/g, "/")}")
  BOARD = {${[...board].map(([pgn, b]) => `[${pgn}]={${[...b].join(",")}}`).join(",")}}
  FIRMWARE = {${Object.entries(firmware).map(([c, b]) => `[${c}]={${b.join(",")}}`).join(",")}}
  FIRMWARE_INDEXED = { [${INDEXED}] = {${firmwareIndexed.map((b, i) => `[${i}]={${b.join(",")}}`).join(",")}} }
  WIRE = {}      -- every command that went over the wire, in order
  FIRMWARE_WRITES = {}  -- cmd -> { {pgn, off, bytes}, ... } the firmware's setter stores
  FIRMWARE_ERRORS = {}  -- cmd -> true: the firmware answers MSP_RESULT_ERROR
  local pendingReply
  COMMON = {
    mspSendRequest = function(cmd, payload)
      WIRE[#WIRE + 1] = cmd
      local p = payload
      if cmd == 0x5F22 then
        local pgn, off, len = p[1] + p[2] * 256, p[3] + p[4] * 256, p[5] + p[6] * 256
        local r = {}
        for k = 1, len do r[k] = BOARD[pgn][off + k] end
        pendingReply = { cmd, r }
      elseif cmd == 0x5F23 then
        local pgn, off = p[1] + p[2] * 256, p[3] + p[4] * 256
        for k = 5, #p do BOARD[pgn][off + k - 4] = p[k] end
        pendingReply = { cmd, {} }
      elseif FIRMWARE_ERRORS[cmd] then
        pendingReply = { cmd, {}, "error" }
      elseif FIRMWARE_WRITES[cmd] then
        for _, w in ipairs(FIRMWARE_WRITES[cmd]) do
          for k = 1, #w[3] do BOARD[w[1]][w[2] + k] = w[3][k] end
        end
        pendingReply = { cmd, {} }
      else
        local byIndex = FIRMWARE_INDEXED[cmd]
        pendingReply = { cmd, (byIndex and byIndex[p[1]]) or FIRMWARE[cmd] or {} }
      end
      return true
    end,
    mspProcessTxQ = function() end,
    mspPollReply = function()
      if not pendingReply then return nil end
      local r = pendingReply; pendingReply = nil
      local copy = {}
      for i = 1, #r[2] do copy[i] = r[2][i] end
      return r[1], copy, r[3]
    end,
    mspClearBufs = function() pendingReply = nil end,
  }
  function drain(q)
    local guard = 0
    while not q:isProcessed() do
      guard = guard + 1; if guard > 5000 then error("queue never drained") end
      q:processQueue()
    end
  end
  function hex(t)
    local parts = {}
    for i = 1, #t do parts[i] = string.format("%02x", t[i]) end
    return table.concat(parts)
  end
  function request(q, cmd, payload)
    local got
    q:add({ command = cmd, payload = payload,
      processReply = function(_, buf) got = hex(buf or {}) end,
      errorHandler = function(r) got = "ERR " .. tostring(r) end })
    drain(q)
    return got
  end
  function wireCount(cmd)
    local n = 0
    for _, c in ipairs(WIRE) do if c == cmd then n = n + 1 end end
    return n
  end
`);

let checks = 0, failures = 0;
const check = (what, ok, detail = "") => { checks++; if (!ok) { failures++; console.error(`FAIL ${what} ${detail}`); } };
const hexOf = (a) => a.map((b) => b.toString(16).padStart(2, "0")).join("");

lua_(`Q = Queue.new(COMMON, DEBUG); V = Virtual.new(PACK); Q.virtual = V
      VERIFIED = {}; V.onVerified = function(cmd, same) VERIFIED[cmd] = same end`);

// 1. First request: firmware answers, verification runs behind it.
const first = lua_(`return request(Q, ${REPLY})`);
check("first request gets the firmware's reply", first === hexOf(firmware[REPLY]), first);
check("first request went over the wire", lua_(`return tostring(wireCount(${REPLY}))`) === "1");
check("verification ran and matched", lua_(`return tostring(VERIFIED[${REPLY}])`) === "true");
check("verification used PARAM_READ", Number(lua_(`return tostring(wireCount(0x5F22))`)) >= 1);

// 2. Second request: answered locally, same bytes, no legacy opcode on the wire.
const second = lua_(`return request(Q, ${REPLY})`);
check("second request answered locally, same bytes", second === first, second);
check("second request did not send the legacy opcode", lua_(`return tostring(wireCount(${REPLY}))`) === "1");

// 3. A codec that disagrees with the firmware is never used.
lua_(`request(Q, ${PLAIN})`);
check("a disagreeing reply is marked so", lua_(`return tostring(VERIFIED[${PLAIN}])`) === "false");
const plainAgain = lua_(`return request(Q, ${PLAIN})`);
check("and keeps coming from the firmware", plainAgain === hexOf(firmware[PLAIN]) && lua_(`return tostring(wireCount(${PLAIN}))`) === "2");

// 4. Setters and requests with arguments pass through.
lua_(`request(Q, ${SETTER}, {1, 2, 3, 4, 5})`);
check("a setter goes to the firmware", lua_(`return tostring(wireCount(${SETTER}))`) === "1");
lua_(`request(Q, ${REPLY}, {7})`);
check("a request with arguments goes to the firmware", lua_(`return tostring(wireCount(${REPLY}))`) === "2");

// 5. An indexed reply is verified per index: each index's first request goes
//    to the firmware, later ones are answered locally.
const indexed = (i) => lua_(`return request(Q, ${INDEXED}, {${i}})`);
check("indexed reply, first request of index 0, from the firmware",
    indexed(0) === hexOf(firmwareIndexed[0]) && lua_(`return tostring(wireCount(${INDEXED}))`) === "1");
check("indexed reply, index 0 again, answered locally",
    indexed(0) === hexOf(firmwareIndexed[0]) && lua_(`return tostring(wireCount(${INDEXED}))`) === "1");
check("indexed reply, index 1, verified on its own",
    indexed(1) === hexOf(firmwareIndexed[1]) && lua_(`return tostring(wireCount(${INDEXED}))`) === "2");
check("indexed reply, index 1 again, answered locally",
    indexed(1) === hexOf(firmwareIndexed[1]) && lua_(`return tostring(wireCount(${INDEXED}))`) === "2");
check("indexed reply with extra arguments goes to the firmware",
    lua_(`request(Q, ${INDEXED}, {0, 0}); return tostring(wireCount(${INDEXED}))`) === "3");

// 6. Setters (stage B), with writes enabled: the first request goes to the
//    firmware and is verified behind it by a dry run; later ones are written
//    through PARAM_WRITE. Nothing extra is written while verifying.
lua_(`WIRE = {}; V.writes = true; FIRMWARE_WRITES[${SETTER}] = ${luaRuns(setterRuns)}`);
const payloadLua = `{${SETTER_PAYLOAD.join(",")}}`;
const firstSet = lua_(`return request(Q, ${SETTER}, ${payloadLua})`);
check("setter, first request, goes to the firmware", firstSet === "" && lua_(`return tostring(wireCount(${SETTER}))`) === "1", firstSet);
check("and is verified without writing", lua_(`return tostring(VERIFIED[${SETTER}])`) === "true" && lua_(`return tostring(wireCount(0x5F23))`) === "0");
const bumped = SETTER_PAYLOAD.map((b) => (b + 1) & 0xff);
const bumpedRuns = await js.plan(SETTER, bumped);
lua_(`request(Q, ${SETTER}, {${bumped.join(",")}})`);
check("a verified setter is written through PARAM_WRITE, not sent",
    lua_(`return tostring(wireCount(${SETTER}))`) === "1" && Number(lua_(`return tostring(wireCount(0x5F23))`)) >= 1);
check("and stores what the firmware's setter would",
    bumpedRuns.every((r) => lua_(`local t = {} for k = 1, ${r.bytes.length} do t[k] = BOARD[${r.pgn}][${r.offset} + k] end return table.concat(t, ",")`) === [...r.bytes].join(",")));

// A codec that stores elsewhere than the firmware: not verified, stays on it.
lua_(`WIRE = {}; V2 = Virtual.new(PACK); V2.writes = true; Q3 = Queue.new(COMMON, DEBUG); Q3.virtual = V2
      V2.onVerified = function(cmd, same) VERIFIED2 = same end
      FIRMWARE_WRITES[${SETTER}] = ${luaRuns(setterRuns.map((r) => ({ ...r, offset: r.offset + 1 })))}`);
lua_(`request(Q3, ${SETTER}, ${payloadLua}); request(Q3, ${SETTER}, ${payloadLua})`);
check("a setter the firmware stores elsewhere is kept on the firmware",
    lua_(`return tostring(VERIFIED2)`) === "false" && lua_(`return tostring(wireCount(${SETTER}))`) === "2");

// A request the firmware refuses verifies nothing; the next one is watched.
lua_(`WIRE = {}; V4 = Virtual.new(PACK); V4.writes = true; Q4 = Queue.new(COMMON, DEBUG); Q4.virtual = V4
      FIRMWARE_ERRORS[${SETTER}] = true; FIRMWARE_WRITES[${SETTER}] = ${luaRuns(setterRuns)}`);
const refused = lua_(`return request(Q4, ${SETTER}, ${payloadLua})`);
lua_(`FIRMWARE_ERRORS[${SETTER}] = nil`);
lua_(`request(Q4, ${SETTER}, ${payloadLua})`);
check("a refused first request reaches the caller's errorHandler and verifies nothing",
    refused.startsWith("ERR") && lua_(`return tostring(V4.verifiedSetters[${SETTER}])`) === "true", refused);

// 7. With no virtual layer (setting off) nothing is intercepted.
lua_(`Q2 = Queue.new(COMMON, DEBUG); WIRE = {}`);
lua_(`request(Q2, ${REPLY}); request(Q2, ${REPLY})`);
check("without the setting both requests hit the firmware", lua_(`return tostring(wireCount(${REPLY}))`) === "2");

// 8. build id decoding
lua_(`BID = dofile("${S}/lib/msp_build_id.lua")`);
check("build id decodes when valid",
    lua_(`return tostring(BID.decode({1, 0x77,0x9b,0xbd,0x3c,0xc4,0x38,0x14,0xe0, 2,0, 0,0,0,0}))`) === "779bbd3cc43814e0");
check("build id is nil when the firmware has none",
    lua_(`return tostring(BID.decode({1, 0,0,0,0,0,0,0,0, 0,0, 0,0,0,0}))`) === "nil");

console.log(`${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
