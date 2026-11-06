// Run a plain Lua 5.3 test file under fengari: node run_lua.mjs <file.lua>
// (from the repository root, as bin/tests/*.lua expect).
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lauxlib.luaL_dostring(L, to_luastring("collectgarbage = collectgarbage or function() return 0 end"));
const status = lauxlib.luaL_dofile(L, to_luastring(process.argv[2]));
if (status !== lua.LUA_OK) {
    console.error(lua.lua_tojsstring(L, -1));
    process.exit(1);
}
console.log(`${process.argv[2]}: ok`);
