# Menu structure

The menu source of truth is [`app/tool.lua`](../src/wfsuite/app/tool.lua).
`ROOT_ENTRIES` defines the root tiles and `MENUS` defines named submenus.
The [page index](pages/README.md) lists all reachable leaf pages and their conditions;
each page document contains its full breadcrumb.

A leaf entry has `title`, `icon` and `script="app/pages/<page>.lua"`.
A submenu entry uses `menuId="<MENUS key>"` instead of `script`.
Edit these Lua tables directly. Link directly to a page when a submenu would
contain only one entry. `bin/menu/` is obsolete tooling for the removed
`app/modules/manifest.lua` architecture and must not be used for this menu.

`app/menu_container.lua` loads pages and applies navigation guards. A running
background task is required; entries marked `offline = true` may be opened without
an FC connection. Servo bus and ESC protocol guards add feature-specific checks.
`visibleWhen` controls visibility, including developer tools. Do not assume every
page is locked while armed: verify each page and its shared runtime separately.

After adding, moving or removing a page, run the documentation scaffold/index tools
and review breadcrumbs in existing documents. Scaffolding preserves authored text;
it does not silently rewrite an existing page after a menu move.
