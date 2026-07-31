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
- i18n sources and generators: `bin/i18n/` -- see Section 11's warning
  before running `build-single-json.py`.
- `bin/menu/` -- wingflight-only tooling with no equivalent in the
  current architecture; see Section 11, do not use it expecting it to do
  anything for the current menu system.

Reference docs:
- `docs/memory-and-module-lifecycle.md` -- loadfile() caching, why eager
  subsystem registration beats lazy proxies, subscription cleanup, and
  why not to reach for collectgarbage(). Current and accurate (unlike the
  docs listed as stale in Section 11).

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
- Don't leave a single-entry submenu: link straight to the page instead
  (see `advanced_menu`'s "Rates Advanced" entry for the pattern).
- `docs/menu-structure.md` is stale (describes the old generator); do not
  treat it as authoritative.

## 7) i18n Rules

i18n source of truth:
- `bin/i18n/json/<locale>.json`

Generated runtime locale files:
- `src/wfsuite/i18n/<locale>.json`

Commands:
- `python bin/i18n/update-missing-translations.py [--only <locale...>]`
- `python bin/i18n/update-max-lengths.py [--only <locale...>]`
- `python bin/i18n/build-single-json.py [--only <locale...>]`

Rules:
- Do not hand-edit generated files in `src/wfsuite/i18n/` if a source JSON change is intended.
- Keep translation key structure consistent with `en.json`.

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
  fields) while adding others (master_gain, autohover, cross_axis_relax,
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
- Check for hot-path allocations introduced by the change.
- Confirm close/cleanup path exists for new dialogs, handles, or caches.
- Run targeted sanity checks for affected module flows.

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
- **Known trap -- do not run `bin/i18n/build-single-json.py` without
  checking its diff first.** `bin/i18n/json/` (this file's nominal
  i18n source of truth, Section 7) is itself stale/incomplete relative
  to `src/wfsuite/i18n/`, inherited from the upstream rewrite -- running
  the regeneration deletes real content (confirmed: it strips help text
  like `api.ACC_TRIM.pitch/roll` and several `api.BATTERY_CONFIG.*`
  entries that exist in `src/wfsuite/i18n/` but not in `bin/i18n/json/`).
  Until someone reconciles the two, treat `src/wfsuite/i18n/*.json` as
  the practical source of truth and hand-edit it directly when needed
  (matching what every locale-file edit in this migration has done),
  and separately mirror any *new keys* into `bin/i18n/json/` too so
  they're not lost if/when the drift does eventually get fixed.
- **`bin/menu/` is stale**, not just unused: it still generates a
  manifest for the old `app/modules/manifest.lua` structure, which this
  architecture doesn't have (see Section 6). Running it does not error,
  but its output is dead weight.
- **`docs/system-architecture.md`, `docs/menu-structure.md`,
  `docs/i18n-locales.md` are all stale**, describing the pre-rewrite
  architecture (`wfsuite.*` global table, `app/modules/`,
  `tasks/scheduler/`). Not yet rewritten for the new architecture.
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

