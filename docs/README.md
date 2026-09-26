# WFSuite documentation

Start with the [configuration page index](pages/README.md) to find a radio page.
Each entry is marked **draft** or **reviewed**. Drafts are scaffolds, not complete
operating instructions. Reviewed means checked against the current Lua source;
it does not imply testing on a radio or every firmware version.

## Contributor guides

- [System architecture](system-architecture.md)
- [Menu structure](menu-structure.md)
- [Memory and module lifecycle](memory-and-module-lifecycle.md)
- [Locale workflow](i18n-locales.md)
- [Dashboard themes](dashboard-themes.md)
- [Dashboard objects](dashboard-objects.md)

## Maintaining page documentation

The documentation tools run on a development computer and are not radio code.
They read `src/wfsuite/app/tool.lua` and the runtime English locale directly.
They do not regenerate menus or locale files.

```sh
python3 bin/docs/generate_menu_docs.py --scaffold-all
python3 bin/docs/generate_menu_docs.py --page setup/governor.md
python3 bin/docs/generate_menu_docs.py --update-index
python3 bin/docs/generate_menu_docs.py --check
python3 -m unittest discover -s bin/docs -p 'test_*.py'
```

Windows users can run `bin\docs\generate_menu_docs.cmd` with the same arguments;
Unix users can use `bash bin/docs/generate_menu_docs.sh`.

Scaffolding uses [_template.md](_template.md). Both `--scaffold-all` and `--page`
preserve existing documents. `--force` explicitly replaces their content, including
reviewed prose. The index is generated and should not be hand-edited.

Edit page documents by hand after scaffolding. Explain each control, check displayed
units and scaling, follow save callbacks through shared helpers, and verify profile
scope and access conditions. Replace all TODOs and the draft notice, then set
`documentation_status: reviewed` and refresh the index. Add specific related links
where useful. Preserve the `source` field so the document can be traced to its page.

The parser supports the current static menu layout, not arbitrary Lua. It checks
for unresolved English keys, missing source files, menu cycles, duplicate document
paths and unreachable script entries. Dynamic controls and helper-built forms need
manual review; extracted labels can be incomplete. It deliberately does not infer
save/reboot behaviour, armed locks, displayed ranges or firmware defaults.

`--check` verifies file coverage and explicit review status. It does not certify
correctness or detect all stale prose. `--check --require-reviewed` additionally
fails while drafts remain. CI runs coverage and tooling tests; publishing a website
is a separate step after content review.

The tooling was adapted from [Rotorflight PR #2369](https://github.com/rotorflight/rotorflight-lua-ethos-suite/pull/2369).
