# AGENTS.md

This file is for automated coding agents working in this repository.
Follow these rules before making code changes.

## 1) Primary Goal

Keep behavior correct while minimizing runtime memory churn and CPU load on Ethos radios.

## 2) Architecture Quick Map

- Entry point: `src/wfsuite/main.lua` (thin: loads and initialises three
  independent subsystems -- app/tool.lua, widgets/dashboard.lua +
  widgets/activelook.lua, tasks/background.lua -- eagerly, not lazily; see
  its own header comment and Section 11 below before assuming lazy-loading
  or feature gating is available/wanted here)
- App/UI: `src/wfsuite/app/` -- pages live flat in `app/pages/*.lua`, menu
  structure is a static Lua table (`MENUS` in `app/tool.lua`), not a
  generated file. There is no `app/modules/` any more.
- Background scheduler/tasks/MSP transport: `src/wfsuite/tasks/`
  (`tasks/scheduler.lua`, `tasks/session.lua`, `tasks/msp/*` for the
  transport/queue layer)
- MSP command codecs: `src/wfsuite/lib/msp_*.lua` -- one flat
  self-contained file per MSP command (schema + decode/encode +
  message-builders together), not a factory/`api/` pattern. There is no
  `tasks/scheduler/msp/` path any more.
- Dashboard widgets/objects: `src/wfsuite/widgets/`
- Shared utilities: `src/wfsuite/lib/`
- i18n sources and generators: `bin/i18n/` -- see Section 7 for the
  edit-then-generate workflow.
- `bin/menu/` -- wingflight-only tooling with no equivalent in the
  current architecture; see Section 11, do not use it expecting it to do
  anything for the current menu system.

Reference docs:
- `docs/memory-and-module-lifecycle.md` -- loadfile() caching, why eager
  subsystem registration beats lazy proxies, subscription cleanup, and
  why not to reach for collectgarbage(). See also the documentation
  index in `docs/README.md`.

## 3) Non-Negotiables For Agent Changes

- Do not regress memory behavior in wakeup/render paths.
- Do not hand-edit generated artifacts when a generator is the source of truth.
- Keep deltas focused and minimal.
- Prefer explicit cleanup on page/module close.
- Preserve offline/post-connect behavior in menu and task logic.

## 4) GC Churn Guardrails (Critical)

Treat all high-frequency paths (`wakeup`, `paint`, scheduler callbacks) as hot paths.

Avoid:
- Allocating new tables/arrays every wakeup.
- Rebuilding formatted strings every wakeup when input values did not change.
- Recreating closures/handlers repeatedly for static buttons.
- Repeated `lcd.loadMask`/image loads without cache.
- Repeated `field:enable(...)` calls when state is unchanged.
- Replacing a live queue table (`queue = {}`) where clearing in-place is enough.

Prefer:
- Reuse buffers/tables and clear them in-place.
- Cache computed values and update only when quantized display values change.
- Cache color/mask/image resolution outputs when inputs are stable.
- Prebuild tiny animation states (for example loading dots table) instead of `string.rep`.
- Reuse handler functions per menu/module key instead of creating per rebuild.
- Gate UI/state updates behind change detection (`if last ~= current then ... end`).

## 5) Cleanup Rules

When closing a page/module/app:
- Close progress/save dialogs.
- Close file handles.
- Clear page-specific caches.
- Clear image/mask caches when leaving app or page flows that own them.
- Nil large transient references if they are no longer needed.

When clearing collections:
- Prefer wiping keys in-place for reusable tables.
- Only replace the whole table when index-reset semantics are intentional.

## 6) Menu System Rules

No generator: the menu is a static Lua table (`MENUS`) hand-written
directly in `src/wfsuite/app/tool.lua`. Each entry is either
`{title=, icon=, script="app/pages/<page>.lua"}` (leaf page) or
`{title=, icon=, menuId="<other MENUS key>"}` (submenu). There is no
`app/modules/manifest.lua`, no `bin/menu/manifest.source.json`, and no
generate step for this any more -- `bin/menu/` is stale leftover tooling
from the pre-rewrite architecture (see Section 11).

Rules:
- Edit `app/tool.lua`'s `MENUS` table directly.
- Don't leave a single-entry submenu: link straight to the page instead.
- To sort a crowded screen, give its entries a `group` label rather than
  adding submenus (see `setup_menu` and `flight_tuning_menu`). The first
  group's label becomes the screen header.
- `docs/menu-structure.md` describes the current static menu;
  `docs/pages/README.md` is the generated page documentation index.

## 7) i18n Rules

i18n source of truth:
- `bin/i18n/json/<locale>.json`

Generated runtime locale files:
- `src/wfsuite/i18n/<locale>.json`

Commands:
- `python bin/i18n/update-missing-translations.py [--only <locale...>]`
- `python bin/i18n/update-max-lengths.py [--only <locale...>]`
- `python bin/i18n/build-single-json.py [--only <locale...>]`

Workflow: edit `bin/i18n/json/en.json` (new or changed English), then run
the three commands above in order. They copy new keys to every locale
(English text, `needs_translation: true`), reset a translation whose
English changed, refresh `max_length`, and regenerate `src/wfsuite/i18n/`.
Running them again changes nothing. `bin/i18n/auto-translate.py` fills
`needs_translation` entries in `bin/i18n/json/` (needs `ANTHROPIC_API_KEY`);
run `build-single-json.py` afterwards so the translations reach `src/`.

Rules:
- Do not hand-edit generated files in `src/wfsuite/i18n/`: edit `bin/i18n/json/`
  and regenerate, or the next regeneration silently discards the edit.
- Keep translation key structure consistent with `en.json`.
- Every `@i18n(key)@` tag must resolve: a missing key is not a build error,
  the pilot just sees the raw tag text on the radio. Check with
  `python bin/i18n/check-tags.py [--lang <locale>]` (exit 1 and file:line
  for each missing key).
- The deploy i18n step records the last deploy's missing keys in
  `.vscode/logs/i18n-unresolved.json` (git-ignored; deleted when a deploy
  resolves everything). If that file exists, tell the user which keys are
  missing and where, even if the current task did not touch them.

## 8) MSP/API/Scheduler Notes

- Prefer the codec pattern already used in `lib/msp_*.lua` (schema +
  decode/encode + buildReadMessage/buildWriteMessage together in one
  file, self-caching via `package.loaded`) -- not the old
  `tasks/scheduler/msp/api/` factory pattern, which no longer exists.
- **Wire schemas must be verified against wingflight-firmware's actual
  `src/main/msp/msp.c` serializer, not assumed from a rotorflight-based
  guess or a field's old name.** wingflight-firmware has hardcoded,
  zeroed, or entirely removed a substantial number of heli-only fields
  and commands (MSP_GOVERNOR_CONFIG/PROFILE and MSP_RESCUE_PROFILE are
  gone outright; MSP_PID_PROFILE/MSP_PID_TUNING/MSP_RC_TUNING/
  MSP_MIXER_CONFIG keep their wire position but zero/ignore several
  fields) while adding others (master_gain, cross_axis_relax,
  gain_curve on MSP_PID_PROFILE) that a rotorflight-only cross-check
  would never surface. See `lib/msp_pid_profile.lua`'s and
  `lib/msp_rc_tuning.lua`'s own header comments for the full pattern and
  worked examples. Removing/adding a field from the *middle* of a fixed
  wire struct without confirming the firmware did the same shifts every
  field after it -- this already happened once in this migration (the
  rewrite's own `offset_limit_0/1` guess) and would have silently
  corrupted PID data on save.
- Be careful with queue behavior and duplicate suppression semantics.
- Avoid adding logging/diagnostics in hot paths unless guarded by explicit debug preferences.

## 9) Change Validation Checklist

Before finishing:
- Verify no generated file drift (`menu`/`i18n`) if source files were touched.
- `.github/workflows/pr.yml` is generated: to add a Lua harness, add a `LuaStep`
  to `bin/ci/pr_jobs.py` and run `python bin/ci/verify_pr_workflow.py --write`.
  Do not edit `pr.yml` by hand; the `pr-workflow-drift` job fails when they differ.
- If you added or changed any `@i18n(...)@` tag, run `python bin/i18n/check-tags.py`
  and fix what it reports.
- Check for hot-path allocations introduced by the change.
- Confirm close/cleanup path exists for new dialogs, handles, or caches.
- Run targeted sanity checks for affected module flows.
- For UI changes, open the affected page in the simulator when the tooling is available
  (Section 12), and include screenshots with the pull request.
- If the change is one a pilot can observe, update that page's file under `docs/pages/` in
  the same pull request, or state on a line of its own why it needs none. The rule is
  [.agents/rules/documentation.md](.agents/rules/documentation.md); the `Documentation rule`
  job in `.github/workflows/pr.yml` fails when neither is there.

## 10) Scope Control

If the repository is already dirty:
- Do not modify unrelated files.
- Touch only files needed for the requested task.

## 11) Wingflight Migration Notes

`src/wfsuite/` was rebuilt wholesale from `rotorflight-lua-ethos-suite`'s
`rfsuite-full-rewrite` branch (a from-scratch architectural rewrite of
that project), then rebranded and re-aligned for wingflight (fixed-wing
firmware) rather than rotorflight (helicopter firmware). Status:

- **Done**: base replacement + full rebrand; heli-only pages/gfx/MSP
  files removed (governor, rescue, swashplate mixer, main/tail rotor
  PID, rates_type/cyclic/collective-axis UI); `lib/msp_pid_profile.lua`/
  `lib/msp_rc_tuning.lua`/`lib/rate_curve_scale.lua` rebuilt against
  wingflight-firmware's actual wire format (see Section 8).
- **Not ported: the pre-rewrite `lib/features.lua` "Feature Flags" RAM
  system** (a user-preference toggle to skip registering the dashboard/
  toolbox/ActiveLook widgets, added to save RAM on constrained radios).
  Deliberately not carried forward: `main.lua`'s own header comment
  documents that this rewrite already tried lazy/conditional widget
  loading more broadly and reverted to eager loading for all three
  subsystems after on-device testing showed lazy loading caused *worse*
  retained-RAM growth, not better -- porting a feature built on the
  premise that conditional loading helps RAM would fight the rewrite's
  own measured design decision. The `toolbox` widget this system used to
  gate no longer exists in this architecture at all. ActiveLook already
  has an arguably better gate: `main.lua` only loads it when
  `system.registerGlassesWidget` exists (an automatic hardware/firmware
  capability check), not a manual preference.
- **i18n sources reconciled**: `bin/i18n/json/` had drifted from
  `src/wfsuite/i18n/` during the migration (src had newer keys and
  English; bin had translations src never received), so for a while src
  was hand-edited directly. The two were merged and `bin/i18n/json/` is
  the source of truth again: follow Section 7's workflow and don't
  hand-edit `src/wfsuite/i18n/`.
- **`bin/menu/` is stale**, not just unused: it still generates a
  manifest for the old `app/modules/manifest.lua` structure, which this
  architecture doesn't have (see Section 6). Running it does not error,
  but its output is dead weight.
- **Documentation refreshed**: `docs/system-architecture.md`,
  `docs/menu-structure.md`, and `docs/i18n-locales.md` describe the current
  architecture and the locale workflow. `docs/pages/README.md` indexes
  page references with explicit draft/reviewed status; maintain them with
  `bin/docs/generate_menu_docs.py` (see `docs/README.md`).
- **Ported since this section was first written**: Mixer Config
  (`app/pages/mixer_config.lua`), Cross Axis Relax/Master Gain/FW TPA
  (`app/pages/pid_controller.lua`), Arm Ready Wiggle codec
  (`lib/msp_arming_config.lua`, built but not yet wired to a page --
  see HANDOVER.md), Auto Trim/Att Hold/Auto Hover
  (`app/pages/autolevel.lua`), and default rate-curve tuning
  (`app/pages/rates.lua`/`lib/rate_curve_scale.lua`'s `DEFAULT_RAW`).
  See `HANDOVER.md`'s "Done" list for what each actually covers.
- **Still to port**: Throttle Range Governor
  (`MSP2_WING_GOVERNOR_CONFIG`) -- see HANDOVER.md for current priority
  order. (`lib/msp_mixer_override.lua`, inherited from the rewrite base,
  is wire-verified correct against `MSP_SET_MIXER_OVERRIDE` but still
  wired to no page -- not confirmed relevant to wingflight's own
  manual/passthrough concept, or worth building a page for, until
  someone actually needs it.)
- **Phase 3 MSP audit: complete.** Every `lib/msp_*.lua` file has now
  been checked field-by-field against wingflight-firmware's `msp.c` --
  zero wire-format bugs found (see HANDOVER.md's "Done" list, item 11,
  for the two harmless pre-existing quirks noted and the ESC-vendor
  passthrough files' out-of-scope caveat). Treat any *new* `msp_*.lua`
  file added after this point as unverified until checked the same way
  (see Section 8).

## 12) Testing in the Ethos Simulator

Agents can check UI changes in the Ethos WASM simulator. They can boot the radio, see its screen and operate it with touch, keys and the rotary encoder. Use this to confirm that a page, dialog or widget looks and behaves right before calling a pilot-visible change done.

Tooling:
- **Claude Code:** this repository's `.claude/settings.json` lists the `ethos-tools` marketplace and
  enables its `ethos-simulator` plugin, so Claude Code offers to install it when you trust the folder.
  To install it by hand: `/plugin marketplace add FrSkyRC/ethos-tools` and then
  `/plugin install ethos-simulator@ethos-tools`.
  Its `ethos-navigate` skill covers starting the simulator, the screenshot loop and the radio buttons.
  If `ethos-navigate` is not in the session's skill list (the plugin was installed mid-session, or the
  install was declined), restart the session, or read `simulation/skills/ethos-navigate/SKILL.md` from a
  clone of [FrSkyRC/ethos-tools](https://github.com/FrSkyRC/ethos-tools) and follow it by hand.
- **Other agents:** run `simulation/run_wasm.js --serve` from a clone of
  [FrSkyRC/ethos-tools](https://github.com/FrSkyRC/ethos-tools) directly. Its README lists the commands.

This repository:
- **Simulator build:** board and protocol come from `ethos.board` / `ethos.protocol` in `.vscode/settings.json`.
  The Ethos VS Code extension caches the `<BOARD>_<PROTOCOL>.js` + `.wasm` pair in its global storage
  (`<VS Code user dir>/globalStorage/bsongis.ethos/cache`).
- **Deploy first:** `python .vscode/scripts/deploy.py --lang en --step i18n --step soundpack --step sensors`
  (the same command as the "Deploy & Launch [SIM]" VS Code task).
  This writes `src/wfsuite` to `simulators/<BOARD>_<PROTOCOL>@<release>/scripts/wfsuite`.
- **Mount that folder** (`simulators/<BOARD>_<PROTOCOL>@<release>/`) as the radio's root directory.
  It is git-ignored, so mounting it directly is fine. Don't run a second simulator on the same folder at the same time, for example the VS Code extension's.
- **Boot dialogs:** booting shows a *Select Battery* dialog, then *Battery Profile*, then *Checklist warning*.
  Dismiss each one before any other input. Menu keys are ignored while a dialog is open.
- **Opening the app:** `SYS`, then `PAGE` to System page 2, then the **Wingflight** tile. The app's own pages are tile grids with a **BACK** button at the top right.
- **Another board, or a fresh radio folder:** a model saved by a newer Ethos build
  will not load on an older one ("Need firmware update"), so for a second board
  (e.g. `X18S_EU`, the smallest screen at 480x320) mount a new folder under the
  scratchpad holding only `scripts/wfsuite` copied from the deployed one. It boots
  through *Select language*, *Storage error, default settings restored* and the
  *Create model* wizard; finish the wizard, then set the model up, or every app tile
  shows *Background task not running*:
  1. Model menu, page 3, **Lua**: turn **Wingflight [Background]** on.
  2. Model menu, page 1, **RF system**, **Internal module**: turn **State** on.
  3. Model menu, page 2, **Telemetry**: discover sensors if the list is empty.
- **Cached modules:** `app/header.lua` and other shared modules cache themselves in
  `package.loaded`, so a redeploy is not picked up until the simulator restarts
  (`quit`, then start it again).
- **No flight controller needed:** the suite's built-in simulated sensors and MSP responses (`src/wfsuite/sim/sensors/` and the `simulatorResponse` tables in `src/wfsuite/lib/msp_*.lua`) populate pages such as PIDs.
- **Lua errors** appear in the output of the `log` command, not on screen.
