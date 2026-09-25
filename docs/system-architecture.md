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
