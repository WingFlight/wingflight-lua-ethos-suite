# System architecture

WFSuite has three independent subsystems registered by
[`main.lua`](../src/wfsuite/main.lua): the system tool, dashboard widgets, and the
background task. Each owns its state through closures. They communicate through
[`lib/bus.lua`](../src/wfsuite/lib/bus.lua), rather than a shared `wfsuite` global.

## Entry points and shared code

| Area | Entry or location | Responsibility |
| --- | --- | --- |
| System tool | `app/tool.lua` | Static menus, navigation and page callbacks |
| Pages | `app/pages/*.lua` | Configuration, settings and diagnostics |
| Page helpers | `app/page_runtime.lua`, `app/field_layout.lua` | Common read/save lifecycle and form fields |
| Background | `tasks/background.lua` | Background service registration |
| Scheduler and session | `tasks/scheduler.lua`, `tasks/session.lua` | Scheduled work and connection/session state |
| MSP transport | `tasks/msp/` | Transport and request queue |
| Command codecs | `lib/msp_*.lua` | Wire schemas, decoding, encoding and message builders |
| Widgets | `widgets/dashboard.lua`, `widgets/activelook.lua` | Dashboard and glasses integration |
| Shared utilities | `lib/` | Bus, module loader and other reusable helpers |

Paths in the table are relative to `src/wfsuite/`.

## Loading and lifetime

Top-level subsystems load eagerly. On-device testing found that lazy callback
proxies increased retained RAM. ActiveLook registers only when
`system.registerGlassesWidget` exists. This capability check is distinct from a
user preference for disabling subsystem registration.

Leaf pages load when opened through `app/menu_container.lua`; they are not cached
as live pages between visits. Shared modules use `lib/require.lua` and
`package.loaded` where appropriate. See [Memory and module lifecycle](memory-and-module-lifecycle.md)
for ownership, subscription cleanup and caching rules.

## Adding a page

Use a similar existing page as the implementation reference. Many pages create a
`page_runtime` instance, build fields and call `loadInitial()`; custom pages manage
their own asynchronous requests and cleanup. Close dialogs, unsubscribe listeners
and release transient references on exit. Keep wakeup and paint paths free of
avoidable allocation and repeated UI updates.

Add its entry directly to `ROOT_ENTRIES` or `MENUS` in `app/tool.lua`, then scaffold
and review its [page documentation](README.md#maintaining-page-documentation).
There is no module manifest or menu generation step.

New MSP codecs must be checked against Wingflight firmware's actual
`src/main/msp/msp.c` serializer and write handler. Retained wire positions may be
zeroed or ignored; Rotorflight field names alone do not establish compatibility.

## Background instruction backoff

On Ethos versions exposing `system.getInstructionsUsage()` (26.1.3+), background
frame drains also stop when the current execution cycle's instruction usage
reaches a conservative threshold: 60% for MSP receive/cleanup and the nested
S.Port reply search, 70% for ELRS custom telemetry. Existing time and frame caps
still apply. Older versions retain their original behaviour without this API.

Checks run before consuming the next frame. Partial MSP replies remain assembled
in memory, unread frames remain in the transport queue, and ELRS requests another
drain on the next background wakeup. Cleanup always resets MSP state even when
its optional stale-frame drain is skipped. No per-check tables, strings or
closures are allocated. Capability references are cached when modules load.

These thresholds reserve headroom for subsequent session updates, alerts and
keepalives; they are initial guardrails, not hardware-measured guarantees. A
single frame decode or native API call cannot be interrupted, instruction usage
does not measure SD-card latency, and sustained overload can still delay replies
or overflow native telemetry queues. Boot loading and task scheduling remain
unchanged. The existing `bin/perf/verify_clock_budgets.lua` harness covers absent
API behaviour, pause/resume, nested S.Port draining and long MSP reply assembly.

### Dashboard object wakeups

The dashboard engine also pauses its object-wakeup loop at 70% instruction
usage when the API is available. It retains the current object cursor and resumes
on the next callback; normal backoff does not count as an object failure or emit
an error. Existing object-count pacing still applies, including on older Ethos
versions without the API. The shared loop also covers initial object preparation
requested by paint; drawing itself is unchanged. Resetting the engine clears the
paused cursor. A single object cannot be interrupted by this check, so the
threshold still needs on-radio validation.
