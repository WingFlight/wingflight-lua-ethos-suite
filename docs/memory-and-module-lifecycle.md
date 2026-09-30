# Memory & Module Lifecycle

Ethos radios are memory- and CPU-constrained embedded devices. This suite loads
Lua modules with `loadfile("path.lua")()` everywhere instead of `require()` —
which means every one of these rules exists because of a real, previously
measured problem, not a hypothetical one. This doc is the reference for why
each rule exists and how to apply it to new code.

## 1. Eager subsystem registration beats lazy proxies

Before assuming "load it lazily" is automatically the RAM-friendly choice,
know that this codebase already tried the opposite and measured it losing.
`main.lua`'s own header comment:

> All three subsystems register direct callbacks eagerly. This costs more
> startup RAM than lazy proxies, but avoids retained-RAM growth observed on
> device with the lazy callback layer.

The three top-level subsystems (`app/tool.lua`'s system tool,
`widgets/dashboard.lua`, `tasks/background.lua`'s background task) are all
`loadfile()`'d and `init()`'d unconditionally at boot, not behind a
deferred/proxy registration layer, specifically because on-device testing
showed the lazy version *grew* retained RAM over a session more than just
paying the eager cost once at startup does. Don't reintroduce a lazy
proxy/deferred-registration layer for these three subsystems without new
on-device evidence — this isn't a style choice, it's a reverted experiment.
This is also directly noted in `AGENTS.md` Section 11 (Wingflight Migration
Notes): the pre-rewrite `lib/features.lua` "Feature Flags" RAM system (a
toggle to skip registering widgets) was deliberately not ported for the
same reason.

This is a different (and larger-grained) concern than §2 below:
this section is about *whether to defer registering a whole subsystem at
all*; §2 is about the mechanics of what happens when the same file is
`loadfile()`'d more than once regardless.

**Scope of the rule:** it covers *registration* -- whether a subsystem's
callbacks are wired up eagerly or behind a proxy. It does not cover *when a
subsystem loads the UI subtree underneath it*. That narrower case is §10,
and deferring it is worth doing.

## 2. `loadfile()` has no `require()`-style caching

`require()` caches by module name: the second call to `require("foo")`
returns the same table the first call built. `loadfile("foo.lua")()` does
not — it re-parses and re-executes the file from scratch on every call,
producing a brand-new, independent set of tables and closures each time.

A page opened via `app/page_runtime.lua`-style navigation calls
`loadfile()` on every one of its dependencies **every time the page is
opened**, not once per app session. For a stateless codec module this is
pure waste; for a module with module-level tables or a bus subscription,
it is actively harmful (see §3 and §4).

## 3. When to self-cache a module

Self-cache via `package.loaded[...]` (mirroring `require()`'s own
behavior) when a module is:

- **Loaded repeatedly from a hot path** — a page/menu that gets opened and
  closed repeatedly during normal use — *and*
- Either **stateless but non-trivial to rebuild** (a codec with field
  tables, metadata, or a simulator fixture), **or** **has any load-time
  side effect** (see §4).

Do **not** bother self-caching a module that's only ever `loadfile()`'d
once by a long-lived subsystem (e.g. something `tasks/session.lua` or
`tasks/background.lua` loads once at task init) — there's nothing
repeated to cache against.

The idiom, verbatim, matching `lib/bus.lua`'s own (the pattern's origin
point in this codebase):

```lua
if package.loaded["wfsuite.lib.my_module"] then
  return package.loaded["wfsuite.lib.my_module"]
end

-- ... module body ...

package.loaded["wfsuite.lib.my_module"] = my_module
return my_module
```

Living examples: `lib/msp_pid_tuning.lua`, `lib/msp_reboot.lua`,
`lib/mspcodec.lua`, `lib/settings_store.lua`, `app/page_runtime.lua`,
`app/field_layout.lua`.

**Known gaps** (loaded repeatedly from many separate page-open call
sites, no self-cache guard — candidates for the same treatment):
`lib/msp_eeprom.lua` and `lib/model_preferences.lua` (the latter has a
real module-level `DEFAULTS` table, making the rebuild cost non-trivial).

## 4. The subscription-leak trap

This is the sharpest reason to self-cache, and the easiest to miss: a
module that calls `bus.subscribe(...)` at load time (not inside a
function) registers a new handler *every single time it's loaded*. Without
caching, every page visit adds one more orphaned subscriber that is never
cleaned up, since nothing ever unsubscribes a handler it doesn't know
exists. Ten visits to the same page silently leaves ten copies of that
handler firing on every future bus event, forever.

Example: `lib/elrslink_task.lua` self-caches specifically because it
subscribes to `"session.update"` at load time. `lib/debug_log.lua`'s own
comment: "Self-cached so callers share one bus subscription and one small
settings snapshot."

If a module subscribes to the bus at load time, it **must** self-cache.
There is no other correct option short of never subscribing at load time
in the first place.

## 5. Subscribe/unsubscribe pairing on page close

Separately from §4 (which is about a module leaking a subscription every
time it's *loaded*), any page or widget that subscribes to the bus from
inside its own `open()`/`create()` must unsubscribe on its own
`close()`/`dispose()` — regardless of whether the module itself is
cached. The idiom used throughout:

```lua
local sessionHandler

-- on open/create:
sessionHandler = function(session) ... end
bus.subscribe("session.update", sessionHandler)

-- on close/dispose:
if sessionHandler then
  bus.unsubscribe("session.update", sessionHandler)
  sessionHandler = nil
end
```

Examples: `widgets/dashboard.lua`'s `close()`, `app/page_runtime.lua`'s
dispose path, and most `app/pages/*.lua` files that read live session
data (`diagnostics_elrs_link.lua`, `ports.lua`, `power_alerts.lua`,
`settings_dashboard_theme.lua`, `stats.lua`).

## 6. Explicit `package.loaded[key] = nil` teardown

Self-caching (§3) trades a rebuild cost for a table that now lives for
the rest of the app session. That's fine for small, cheap-to-hold
modules, but for anything sized enough to matter, pair it with explicit
un-caching on app/page close so it doesn't outlive the thing that needed
it:

```lua
for _, key in ipairs(unloadPackageKeys) do
  package.loaded[key] = nil
end
collectgarbage("collect")
```

Examples: `app/tool.lua`'s `close(state)` (app-wide teardown, whole
session package keys), `app/page_runtime.lua`'s per-page
`self.unloadPackageKeys` (see `app/pages/telemetry.lua` for a page that
sets this).

## 7. Clear caches in place, don't replace the table

When clearing a reusable cache/queue table, prefer wiping keys in place
over reassigning `t = {}`:

```lua
local function clearTable(t)
  for key in pairs(t) do t[key] = nil end
end
```

Reassigning creates a new table and allocates again on the next hot-path
tick; it also silently breaks anything holding a reference to the *old*
table (a real bug class, not just a style preference). `widgets/dashboard/context.lua`'s
`clearCaches(options)` uses exactly this `clearTable()` helper for its
image/theme/render caches, gated behind flags (`{renders=, theme=,
images=, liveSources=}`) so a theme switch only clears what actually
needs to change.

**A gated flag with no caller is an unmanaged cache, not a no-op.**
`clearCaches()` is a pure option-dispatch table, so an option nobody
requests fails silently: nothing errors, nothing is logged, and the whole
cache class simply stays resident. That is exactly what happened to the
`images` flag (ported from rotorflight/rotorflight-lua-ethos-suite#2414) --
the branch existed, and `widgets/dashboard.lua`'s `clearThemeCache()` only
ever passed `{theme = true}`, so every decoded dashboard bitmap survived
every theme switch, model change and widget close for the rest of the
session. When adding a flag here, the call site is part of the change; a
flag nothing requests is indistinguishable from a flag that does not work.

Four caches hold decoded bitmaps (or records pointing at them), and all
have a release path that `clearCaches({images = true})` drives:

| Cache | Held by | Released by |
| --- | --- | --- |
| `imageBitmapCache` (context.lua) | the context module, as `{bitmap, used}` records | `clearCaches({images = true})`, plus an LRU ceiling of `IMAGE_BITMAP_CACHE_MAX` (32) entries |
| `imageCache` (context.lua) | `drawImageInRect()`'s per-draw memo, `[fallback][path]` | its values are **weak** references to the records above, so an LRU eviction releases them too; also cleared by `images` |
| `_imgCache` (`objects/image/model.lua`) | the object module, keyed by craft name | a clearer registered via `utils.registerImageCacheClearer()`, run by the same `images` branch |
| `session.dialImageCache` (`objects/dial/image.lua`) | the session table, keyed by dial panel | `clearCaches({images = true})` |

In addition, `imagePathCache` (context.lua) caches resolved string paths and
negative probe results (`path or false`) so missing images are not repeatedly
probed against the filesystem; it is cleared by the same `images` branch.

The LRU ceiling exists because the bitmap cache's key space is open-ended --
every distinct model photo, dial panel and per-box `image` parameter mints a
new key -- so clearing on lifecycle events alone still lets path churn within
one session accumulate. An evicted bitmap is not freed on the spot; the
handle simply becomes garbage once nothing references it, and the next
`loadImage()` re-decodes it.

`drawImageInRect()` keeps its own memo because it runs on paint. Upstream
dropped that memo and called `loadImage()` per draw, which re-normalises the
path (several `gsub` passes) every frame; here the memo stays, holds the LRU
record weakly so it cannot pin a bitmap, and re-stamps the record on a hit so
an image drawn every frame is never the one evicted. It is keyed in two
levels rather than by a `"path|fallback"` string because that concatenation
exceeds Lua's 40-byte short-string limit and so allocated a fresh string on
every draw.

`objects/image/model.lua` needs a registry rather than a lookup because the
engine `loadfile()`s object modules on demand and holds them in its own
`objectsByType` map, so a clearer has to be a closure the module registers
over its own local cache. The engine never evicts that map, so a given
object module registers exactly one clearer per session.

`bin/dashboard/verify_image_caches.lua` pins all of this against the
collector (weak references to stub bitmaps), including an end-to-end theme
reload over the real `settings.update` bus event.

**Not yet measured on hardware.** What is established here is the retention
path: the bitmaps were reachable from a live reference, and they no longer
are. How many kilobytes that is worth on a real radio is not established --
quantifying it needs a `live` vs `churn` split around
`collectgarbage("count")` (a `live` figure after a full collect measures
true retention, `churn` measures the sawtooth).

## 8. Closures survive `form.clear()` — pool them

Live testing showed Ethos retains some `form` callback/widget allocations
after `form.clear()`. Reusing the same callback objects across a rebuild
cannot fix retained widget objects, but does avoid *adding* fresh
retained closures on every repeat visit. `app/field_layout.lua` pools
field getter/setter closures by page+field shape for exactly this reason
— see its own header comment for the full reasoning.

### 8a. But do not shrink the pool on the way out

Ported from rotorflight/rotorflight-lua-ethos-suite#2416.

The natural next step after "the pool is a permanent table" is to drop each
entry when its page is released, on the reasoning that a slot whose
`dataRef` and `controlRef` are both nil is dead weight. **That is a
regression, not a saving**, and it is worth writing down because the
argument for it is very plausible.

The retained widget is what holds the closure alive. Evicting the pool
entry does not free the closure -- it only guarantees the *next* visit to
that page builds a fresh set, while the old widget keeps the old one. So
eviction converts a bounded, one-time pool into closure sets that grow
linearly with the number of page visits, which is the exact thing §8's
pooling exists to prevent.

Upstream measured this by replaying every page's real field inventory
(rotorflight's page set, not wingflight's) through `app/field_layout.lua`
on Lua 5.4, opening each page, building every field and releasing the
runtime:

| Full tours of the page set | Pooled (current) | Evict-on-release |
|---|---|---|
| 1 | 195 entries built | 195 built |
| 2 | 195 | 390 |
| 5 | 195 | 975 |
| 20 | 195 | 3900 |

The shape carries over even though wingflight's numbers differ: the pool is
*bounded by construction*, not merely slow to grow. It is keyed by field
shape, and every field shape in the app is a literal in some page's source,
so it saturates on the first tour and never grows again.

The real lever on this pool is therefore its **per-entry cost**, not its
size. Every entry is a slot table plus its key string plus two closures
(it was three -- the plain setter is now one shared function per field
kind). `field_layout.poolStats()` returns `(count, live)` so the pool's size
and its detached tail can be checked on a radio instead of estimated;
`bin/field_layout/verify_field_layout.lua` pins the pooling, the detach on
`releaseRuntime()`, and the two-closure shape.

## 9. A dead end: don't reach for `collectgarbage()` without new evidence

A prior version of the menu-rebuild path forced `collectgarbage("collect")`
on every menu-screen (re)build to fight observed RAM growth. A live A/B
log across the same 6-page navigation stretch showed **statistically
indistinguishable** growth with vs. without the forced collect
(+44.0/+39.2/... KB vs +55.6/+41.5/... KB). A full, forced
`collectgarbage("collect")` is a *complete* GC cycle — if it cannot
reclaim memory, that memory is genuinely still reachable from a live
reference, not garbage merely waiting to be swept.

Three files were checked and ruled out as the source: `lib/bus.lua`,
`tasks/msp/queue.lua`, `tasks/msp/common.lua`. The leading remaining
hypothesis — plausible given growth scales with field/button count — is
that Ethos's own `form` widget system itself pins something outside
Lua's GC reachability graph entirely, i.e. a platform trait, not
something fixable from script code. See `app/menu_container.lua`'s own
"DISPROVEN, DO NOT RE-ADD without new evidence" comment for the full
write-up.

**Before proposing `collectgarbage()` as a fix for RAM growth tied to
page/menu navigation, check whether it's this same already-ruled-out
case.** A targeted fix (self-caching, subscription cleanup, in-place
clearing) that actually reduces *live references* is the only kind of
fix that can work here.

## 10. Deferring a subsystem's UI subtree is not §1

`app/tool.lua` still registers eagerly at boot (§1), but everything the tool
only needs once it is open -- `app/navigation.lua`, `app/menu_container.lua`
(and through it `app/close_key.lua`, `app/header.lua`, `app/tile_grid.lua`),
`app/esc_protocol_guard.lua`, `app/servo_bus_guard.lua` (and their
`lib/msp_esc_sensor_config.lua`/`lib/msp_serial_config.lua` codecs), and
`lib/memstats.lua` -- is loaded through `ensureX()` helpers from `create()`,
not at module scope. Only `lib/bus.lua` stays eager, because the tool's
`bus.subscribe()` calls have to be live from boot.

Two rules keep that deferral intact:

- **Nothing on the boot path may call an `ensureX()`.** `close()` nil-checks
  `memstats` and `nav` instead of ensuring them: if they are absent the tool
  was never opened, and ensuring them there would load the very modules the
  deferral exists to keep out.
- **A module the subtree loads must not be required at module scope by
  something that loads at boot.** `menu_container.lua` requires `memstats` at
  its call site for the same reason.

The same change in rotorflight-lua-ethos-suite (#2421) measured **−60.4 kB**
of resting Lua heap on an X18RS, connected with the tool closed. The saving
is in the **resting** state, not the peak: with the tool open the modules
are loaded either way, so a pilot who keeps the tool open gets nothing back.
Wingflight had already deferred most of this subtree before that port; the
port added the `close()` nil-checks and the `menu_container.lua` change.

Two harnesses pin it, both run in the PR workflow:

- `bin/tool_ui/verify_tool_ui_lazy.lua` -- none of the modules above are in
  `package.loaded` before `create()` (including after a `close()` with no
  `create()`), all are after, and neither `close()` nor a second `create()`
  loads anything more.
- `bin/tool_ui/verify_no_extra_msp.lua` -- counts `msp.request` at
  `bus.publish` over three tool cycles through both guarded menus, with 100
  wakeups inside one. It answers every request as a live FC would; without
  that, a guard's `pending` flag hides a broken `attempted` latch and the
  harness cannot go red.

**A measurement trap from that work:** an A/B between two builds captured
under different radio state gives a spectacularly wrong number (−523.5 kB
upstream, of which 463.1 kB was Lua deleted off the card between runs). If
the numbers do not decompose, add a third measurement, and compare
`bmpRamAvail` between runs -- if it differs, the screen state differs and the
comparison is void.

## 11. The C stack is a second budget, and it has exactly one unbounded term

Ported from rotorflight/rotorflight-lua-ethos-suite#2426.

The heap is the budget everyone watches. It is not the only one. Ethos runs
FreeRTOS, and a Lua script runs inside one of those tasks. In the reference Lua
VM every Lua-to-Lua call consumes one C stack level, so a call chain that
grows without bound does not raise a catchable Lua error -- it walks the stack
pointer down past the end of the task's stack array and into whatever the
linker placed below it. On the radio that is `ioMutex`, and the result is a
hardfault caught by the watchdog, not an exception.

That is why the two failure modes have to be kept apart. A heap exhaustion
says *"Lua has used too much RAM, it has been Killed"*. A stack overflow says
nothing at all until the radio resets. Any change that trades one for the other
-- or claims to fix an EM by reducing heap -- has to say which one it measured.

### 11.0 Where the two budgets physically live

From the Ethos linker script and the firmware author, on the X18RS:

| Region | Origin | Size | Holds |
|---|---|---|---|
| ITCMRAM | `0x00000000` | 64 K | **unused** |
| **DTCMRAM** | `0x20000000` | 128 K | **all variables and all stacks** |
| RAM_D1 | `0x24000000` | 512 K | the model allocator (used by the mixer) |
| RAM_D2 | `0x30000000` | 288 K | **the model backup, loaded in case of an EM** |
| RAM_D3 | `0x38000000` | 64 K | peripherals that need BDMA |
| **SDRAM** | `0xD0000000` | 8 MB | **everything else: the Lua heap and the bitmap arena** |

Two consequences that are easy to get wrong:

- **The stack and the Lua heap are in different memories.** The Main task's
  stack is a static array in DTCMRAM; the Lua heap is in SDRAM. Exhausting one
  cannot corrupt the other, and a heap reduction cannot buy stack headroom.
  `system.getMemoryUsage()`'s `mainStackAvailable` is derived as
  `4 * STACK_AVAILABLE_WORDS(mainStack, MAIN_STACK_SIZE)` -- a macro over that
  DTCMRAM array, not a heap figure and not a FreeRTOS call.
- **The Lua heap and the bitmap arena share one 8 MB region.** `luaRamAvailable`
  and `luaBitmapsRamAvailable` are two compile-time maxima carved out of the
  same SDRAM, not two separately reserved pools. They compete: a script that
  grows the Lua heap eats bitmap headroom, and the failure surfaces as a
  *bitmap* error. Treat them as one budget with two views.

An EM is a **designed, survivable recovery**, not a dead radio: the model lives
in RAM_D1 and its backup in RAM_D2, and the backup is loaded on EM. That is also
why a Main-stack overflow is survivable at all -- the corruption hits a mutex in
DTCMRAM, while the model and its backup sit in entirely different regions.

The layout inside DTCMRAM is what makes the failure sharp, though:

```
0x20000000  …  unknown .bss  …  0x20005c14
0x20005c14  audioStack   4 096 B
0x20006c14  audioTaskId       4 B
0x20006c18  ioMutex           4 B   <- first casualty of a downward overflow
0x20006c1c  mainStack    20 480 B   <- grows down, into the three above
0x2000BC1C  …  82 916 B of DTCMRAM above the stack  …
```

A FreeRTOS stack pointer starts at the top of its array and grows downward, so
an exhausted Main task reaches `ioMutex` first. **There is no guard region
between them -- that adjacency is link order, not design** -- and 27 676 B of
DTCMRAM lies below `mainStack`, all of it shared with the program's variables.
A full 20 KB overflow does not corrupt one mutex; it walks into everything the
firmware keeps in that 128 K.

### 11.1 The bound

`lib/bus.lua` is the only channel the system tool, the dashboard widget and the
background task use to talk to each other, and `publish()` invokes its
handlers **synchronously**, inside its own loop. A handler is allowed to
publish again -- two or three levels of that is ordinary. A handler that
publishes to a topic whose handler publishes back to the first one is not
ordinary, and nothing in the bus stopped it.

`MAX_PUBLISH_DEPTH` in `lib/bus.lua` stops it. The limit is deliberately far
above legitimate nesting and far below anything that could threaten a stack:
its job is to make the worst case **finite**, not to be the last level before an
overflow. The real budget is not known -- what
`system.getMemoryUsage().mainStackAvailable` counts is an open question, raised
with the Ethos firmware author in
[rotorflight/rotorflight-lua-ethos-suite#2420](https://github.com/rotorflight/rotorflight-lua-ethos-suite/issues/2420).

The guard **raises**, on purpose. The error unwinds exactly one level, into the
`pcall()` of the publish that invoked the offending handler, so the cycle is
cut, the existing handler-error branch above it reports it, and every
`publish()` still decrements on the way out. A silently dropped publish would
be indistinguishable from a bus that works.

`bus.maxPublishDepth()` publishes the deepest chain actually observed, so the
constant can be set from a measurement later instead of from a judgement.

### 11.2 The extremes, and why not an instantaneous reading

`lib/stack_probe.lua` keeps the **smallest** and **largest** value of
`system.getMemoryUsage().mainStackAvailable` seen since the task started. The
question the radio is being asked is how close it has *ever* come to the edge,
and an instantaneous reading cannot answer that -- it is one moment, and the
interesting moment is the worst one. The maximum sits beside it because a
single fixed call site has a fixed depth: a minimum of 0 next to a maximum of
9 000 says the Main task reached the edge; a maximum that also reads 0 says the
call site itself sits deep.

That still cannot say how deep the call site is, so there is a second channel:
`widgets/dashboard.lua` samples the same field at the top of `paint()`, at most
once a second, and `notePaint()` records it separately. Both channels appear on
the background task's `[bgtask mem]` line (`stackMin=… stackMax=… pubMax=…
paintNow=… paintMin=… paintMax=…`), which prints only with the developer
**memory logs** setting on. The paint sample is gated on the same setting, so
with it off `system.getMemoryUsage()` is never called from `paint()` and
`lib/stack_probe.lua` is never loaded.

It lives in its own small module rather than in `lib/memstats.lua` because
that module is loaded lazily, inside the tool's own lifecycle (see section 10),
and the callers here are the background task and the dashboard, which run from
boot. Routing it through `memstats` would mean loading `memstats` at boot --
permanently retained code for a module that does nothing in most sessions,
which is exactly the cost section 10 removed.

`note()` deliberately ignores a missing or non-numeric field instead of
coercing it. The print lines use `or 0`, and feeding that fallback into a
minimum would pin the reported figure at 0 for the rest of the session -- a
confident-looking number that means only "this firmware did not report the
field". `formatStackFields()` renders that case as `-` instead, and prints the
raw bytes rather than `%.1fKB`, because 0 B and 51 B both round to `0.0KB`.

`bin/stack/verify_stack_bounds.lua` drives the real bus through a handler
cycle and asserts it stops at the guard, not at the VM's own "stack
overflow", and pins the exact rendered fields.

### 11.3 What this does not tell you

Measuring the deepest *publish* nesting is not measuring C stack depth. It
bounds the one recursive term in this suite; it says nothing about the depth of
the dashboard's paint path, which is a plain nested call chain with no cycle
in it. Until the meaning of `mainStackAvailable` is answered, no number from
the Lua side can be converted into bytes of headroom.

## Quick reference

| Symptom | Likely cause | Fix |
|---|---|---|
| Considering deferring/proxying a top-level subsystem's registration to save startup RAM | Already tried and reverted -- measured worse retained-RAM growth | Don't, without new on-device evidence (§1) |
| A rarely opened page or tool pulls a big UI subtree in at boot | Modules required at module scope, retained for the session by the `requireModule` cache | Load at the point of use via `ensureX()`; nil-check, don't ensure, in `close()` (§10) |
| Radio resets or EMs with no "Lua has used too much RAM" message | C stack exhaustion, not heap -- e.g. a bus handler cycle | Check `stackMin`/`paintMin`/`pubMax` on the memory log line; `bus.publish` stops cycles at `MAX_PUBLISH_DEPTH` (§11) |
| An A/B between two builds gives an implausibly large delta | The runs had different radio state | Add a third measurement; compare `bmpRamAvail` first (§10) |
| RAM climbs on every visit to the same page | Module reloaded fresh via `loadfile()`, rebuilding module-level tables | Self-cache (§3) |
| RAM climbs *and* stale/duplicate event behavior appears over time | Module subscribes to the bus at load time, never cached | Self-cache (§3/§4) — non-negotiable |
| A page's own live-data callback keeps firing after leaving the page | Page subscribed in open(), never unsubscribed in close() | Pair subscribe/unsubscribe (§5) |
| A long-lived cache table keeps growing across the whole session | Cache never cleared, or cleared by reassignment while something else still holds the old table | Clear in place (§7) |
| A cache class grows across the whole session although a `clearCaches`-style option exists for it | The option is gated and no call site ever requests it -- a silent failure by construction | Request the option at the lifecycle call site, and bound the cache if its key space is open-ended (§7) |
| RAM grows on menu/page rebuild despite everything above being clean | Likely Ethos's own `form` widget retention (§9) | Don't force `collectgarbage()` — it won't help; this needs a different kind of fix (or may be a platform limit) |
