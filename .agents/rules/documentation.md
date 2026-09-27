# Documentation Maintenance Rule

## Mandatory Workflow Requirement
Whenever changes are made to the codebase that a pilot can observe (a new configuration page, a new or removed setting, changed behaviour, a new widget or dashboard theme option, a new audio announcement, or a removed feature) and a Pull Request is prepared:
1. **Always maintain and update the documentation under `docs/`**:
   - Update the file of the page that changed: `docs/pages/<section>/<page>.md`, the file whose `source:` frontmatter names the changed page under `src/wfsuite/app/pages/`. A surface that is not a page (the dashboard widget and its themes, ActiveLook, an announcement) has its file directly under `docs/` (for example `docs/dashboard-themes.md`, `docs/dashboard-objects.md`).
   - When a page is added, removed or moved in the menu, scaffold or remove its file and regenerate the index with `python bin/docs/generate_menu_docs.py --update-index` in the same PR. Do not hand-edit `docs/pages/README.md`.
   - Follow `docs/_template.md`: what the page does, where to find it (the menu path, and the conditions under which it is hidden, greyed out or read-only), one line per setting, and the release the page was checked against.
   - Record the hiding and locking conditions exactly as the `MENUS` table in `src/wfsuite/app/tool.lua` declares them (for example `visibleWhen`, `requiresServoBus`), plus any connection/armed checks the page itself makes.
   - When a page document is checked against the source, replace the draft notice and TODOs and set `documentation_status: reviewed`.
   - Reference the affected page path and the issue / PR number where applicable.
2. **Include the documentation change in the PR**:
   - The updated documentation must be committed as part of the PR so `docs/` stays in sync with master at all times.
   - If a change genuinely needs no documentation update, say so explicitly in the PR body and give the reason, on a line of its own beginning with `Documentation:` (a bullet and bold markers are allowed, for example `- **Documentation.** No page: ...`). The `Documentation rule` job in `.github/workflows/pr.yml` reads that line; it does not judge the reason, it only makes sure the rule cannot be skipped in silence.
