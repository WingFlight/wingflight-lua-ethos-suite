# Menu Manifest Generator

Source of truth:
- `bin/menu/manifest.source.json`

Generated runtime files:
- `src/wfsuite/app/modules/manifest.lua`
- `src/wfsuite/app/modules/manifest_root.lua`
- `src/wfsuite/app/modules/manifest_shortcuts.lua`
- `src/wfsuite/app/modules/manifest_menus/*.lua`

Generator behavior:
- Adds deterministic `shortcutId` fields to menu pages in generated `manifest.lua`.
- Keeps app startup lightweight with a root-only manifest and a compact shortcut registry.
- Emits each submenu separately so only the active menu specification needs to be loaded.
- Supports source text + i18n reference pairs:
  - page: `name` + `translation`
  - menu/group/section: `title` + `translation`
  In generated Lua, `translation` is emitted as runtime `name`/`title`.
- This keeps shortcut selections stable when menu order changes.

Generate:

```bash
python bin/menu/generate.py
```

Windows wrapper:

```bat
bin\menu\generate.cmd
```

Verify generated file is up to date:

```bash
python bin/menu/generate.py --check
```

Menu editor (Tk):

```bash
python bin/menu/editor/src/menu_editor.py
```

Windows wrapper:

```bat
bin\menu\editor\menu_editor.cmd
```

Do not edit generated files under `src/wfsuite/app/modules/manifest*.lua` directly.
