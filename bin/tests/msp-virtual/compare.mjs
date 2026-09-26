// Lua virtual.lua vs the configurator's VirtualMsp: identical bytes on the same board.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;

const [cfgRoot, virtualLua, packLua, manifestPath] = process.argv.slice(2);
const imp = (p) => import(pathToFileURL(`${cfgRoot}/${p}`).href);
const { Manifest } = await imp("src/js/param/manifest.js");
const { VirtualMsp } = await imp("src/js/param/virtual_msp.js");
const { symmetricPairs } = await imp("src/js/param/verify_msp.js");
const { MSPCodes } = await imp("src/js/msp/MSPCodes.js");

const manifest = new Manifest(JSON.parse(readFileSync(manifestPath, "utf8")));
const codecs = manifest.raw.msp_codecs;
let seed = 7;
const random = () => ((seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff) >>> 16) & 0xff;

function makeBoard() {
    const groups = new Map(manifest.raw.pgs.map((pg) => [pg.pgn, Uint8Array.from({ length: pg.size }, () => random())]));
    const sys = groups.get(18);
    if (sys) { sys[5] = 1; sys[6] = 2; sys[7] = 1; } // non-zero profile selections
    for (const c of Object.values(codecs)) {
        for (const op of c.ops) {
            // selectors in range (out of range, the firmware reads past its array)
            if (op[0] === "x") groups.get(op[6]).fill(0, op[7], op[7] + op[8]).set([Math.min(1, op[10] - 1)], op[7]);
            // strings end in a NUL, as their setter leaves them
            if (op[0] === "z") groups.get(op[2])[op[3] + op[1] - 1] = 0;
        }
    }
    return groups;
}
const jsIo = (groups) => ({
    async readRange(pgn, off, len) { return new DataView(groups.get(pgn).buffer, off, len); },
    async writeRange(pgn, off, bytes) { groups.get(pgn).set(bytes, off); },
});
const le = (v, w) => Array.from({ length: w }, (_, i) => (v >> (8 * i)) & 0xff);
const requests = (c) => (c.index ? Array.from({ length: c.index.max }, (_, i) => le(i, c.index.w)) : [[]]);
const luaTable = (bytes) => `{${[...bytes].join(",")}}`;
const hex = (b) => [...b].map((x) => x.toString(16).padStart(2, "0")).join("");

// --- Lua side --------------------------------------------------------------------
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function runLua(src) {
    if (lauxlib.luaL_dostring(L, to_luastring(src)) !== lua.LUA_OK) {
        throw new Error(lua.lua_tojsstring(L, -1));
    }
    const out = lua.lua_gettop(L) ? lua.lua_tojsstring(L, -1) : "";
    lua.lua_settop(L, 0);
    return out;
}
const esc = (p) => p.replace(/\\/g, "/");
runLua(`
  Virtual = dofile("${esc(virtualLua)}")
  PACK = dofile("${esc(packLua)}")
  function run(board, command, payload)
    local q = { pending = {} }
    local v = Virtual.new(PACK)
    local result
    local msg = { command = command, payload = payload,
      processReply = function(_, buf) result = buf end,
      errorHandler = function(r) result = "ERR " .. tostring(r) end }
    if not v:handles(msg) then return "UNHANDLED" end
    v:expand(msg, q)
    local guard = 0
    while #q.pending > 0 do
      guard = guard + 1; if guard > 10000 then return "LOOP" end
      local m = table.remove(q.pending, 1)
      local p = m.payload
      local pgn, off = p[1] + p[2] * 256, p[3] + p[4] * 256
      local g = board[pgn]
      if m.command == 0x5F22 then
        local len = p[5] + p[6] * 256
        local reply = {}
        for k = 1, len do reply[k] = g[off + k] end
        m.processReply(m, reply)
      else
        for k = 5, #p do g[off + k - 4] = p[k] end
        m.processReply(m, {})
      end
    end
    if type(result) == "string" then return result end
    local parts = {}
    for i = 1, #(result or {}) do parts[i] = string.format("%02x", result[i]) end
    return table.concat(parts)
  end
  function dump(board, pgn)
    local g, parts = board[pgn], {}
    for i = 1, #g do parts[i] = string.format("%02x", g[i]) end
    return table.concat(parts)
  end
`);
const luaBoard = (groups) =>
    "{" + [...groups].map(([pgn, b]) => `[${pgn}]={${[...b].join(",")}}`).join(",") + "}";

// --- compare ---------------------------------------------------------------------
let checks = 0, failures = 0;
const check = (what, ok, detail = "") => { checks++; if (!ok) { failures++; console.error(`FAIL ${what} ${detail}`); } };

const board = makeBoard();
runLua(`BOARD = ${luaBoard(board)}`);
const js = new VirtualMsp(manifest, jsIo(board));
let replies = 0;
for (const [code, c] of Object.entries(codecs)) {
    if (c.dir !== "out") continue;
    for (const request of requests(c)) {
        const want = hex(await js.read(Number(code), request));
        const got = runLua(`return run(BOARD, ${code}, ${luaTable(request)})`);
        check(`reply ${code}[${request}]`, got === want, `lua ${got.slice(0, 40)} js ${want.slice(0, 40)}`);
        replies++;
    }
}

let setters = 0;
for (const { get: getCode, set: setCode, indexed } of symmetricPairs(codecs, MSPCodes)) {
  for (const request of indexed ? requests({ index: indexed }) : [[]]) {
    const a = makeBoard(), b = makeBoard();
    for (const [pgn, bytes] of a) b.get(pgn).set(bytes);
    const payload = [...request, ...(await new VirtualMsp(manifest, jsIo(a)).read(getCode, request))];
    // scramble both boards identically, then apply the same setter
    const s = makeBoard();
    for (const [pgn, bytes] of s) { a.get(pgn).set(bytes); b.get(pgn).set(bytes); }
    await new VirtualMsp(manifest, jsIo(a)).write(setCode, payload);
    runLua(`B2 = ${luaBoard(b)}`);
    const r = runLua(`return run(B2, ${setCode}, {${[...payload].join(",")}})`);
    check(`setter ${setCode} completes`, r === "", r);
    for (const pgn of a.keys()) {
        const luaHex = runLua(`return dump(B2, ${pgn})`);
        if (luaHex !== hex(a.get(pgn))) { check(`setter ${setCode}[${request}] group ${pgn}`, false); break; }
    }
    setters++;
  }
}

// Every setter, paired or not, with random payloads of the length it takes:
// the same boards afterwards, or the same refusal. Strings run 3 bytes past
// their max, which the firmware drops.
let randomSetters = 0;
for (const [code, c] of Object.entries(codecs)) {
    if (c.dir !== "in") continue;
    const body = c.ops.reduce((n, op) => n + (op[0] === "Z" ? op[1] + 3 : op[0] === "c" || op[0] === "z" ? 0 : op[1]), 0);
    const length = c.len ?? (c.index ? c.index.w : 0) + body;
    const indices = c.index ? [...new Set([0, Math.floor(c.index.max / 2), c.index.max - 1])] : [null];
    for (const i of indices) {
        const payload = Array.from({ length }, () => random());
        if (i !== null) payload.splice(0, c.index.w, ...le(i, c.index.w));
        const a = makeBoard();
        runLua(`B4 = ${luaBoard(a)}`);
        const jsRefused = await new VirtualMsp(manifest, jsIo(a)).write(Number(code), payload).then(() => false, () => true);
        const r = runLua(`return run(B4, ${code}, ${luaTable(payload)})`);
        if (jsRefused || r !== "") {
            check(`random setter ${code}[${i}] refused by both`, jsRefused && r.startsWith("ERR"), `js ${jsRefused} lua ${r}`);
        } else {
            const bad = [...a.keys()].find((pgn) => runLua(`return dump(B4, ${pgn})`) !== hex(a.get(pgn)));
            check(`random setter ${code}[${i}]`, bad === undefined, `group ${bad}`);
        }
        randomSetters++;
    }
}

// refusals must agree too: an out-of-range index
for (const [code, c] of Object.entries(codecs)) {
    if (c.dir === "in" && c.index) {
        const r = runLua(`return run(BOARD, ${code}, {${c.index.max}, 0, 0, 0, 0, 0, 0, 0})`);
        check(`indexed setter ${code} refuses index ${c.index.max}`, r === "ERR refused", r);
    }
    if (c.dir === "out" && c.index) {
        const request = [...le(c.index.max, c.index.w), ...new Array((c.len ?? c.index.w) - c.index.w).fill(0)];
        const r = runLua(`return run(BOARD, ${code}, ${luaTable(request)})`);
        check(`indexed reply ${code} refuses index ${c.index.max}`, r === "ERR refused", r);
    }
}

// ... and an out-of-range selector: both refuse rather than read past the array
for (const [code, c] of Object.entries(codecs)) {
    const x = c.ops.find((op) => op[0] === "x");
    if (!x || c.dir !== "out" || c.index) continue;
    const bad = makeBoard();
    bad.get(x[6]).set(le(x[10], x[8]), x[7]);
    const jsRefused = await new VirtualMsp(manifest, jsIo(bad)).read(Number(code)).then(() => false, () => true);
    runLua(`B3 = ${luaBoard(bad)}`);
    const r = runLua(`return run(B3, ${code}, {})`);
    check(`reply ${code} refuses selector ${x[10]}`, jsRefused && r === "ERR selector_out_of_range", r);
}

console.log(`compared ${replies} replies, ${setters} paired and ${randomSetters} random setters: ${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
