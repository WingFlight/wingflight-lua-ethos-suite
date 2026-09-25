# Locale workflow

Runtime translations live in `src/wfsuite/i18n/<locale>.json` and supply the
`@i18n(...)@` tokens used by pages and menus. The page documentation tool reads
`src/wfsuite/i18n/en.json` directly without changing any translations.

## Current source drift

`bin/i18n/json/<locale>.json` is the intended generator input, but it is incomplete
relative to the runtime files. Regenerating can remove real help text, including
ACC_TRIM and BATTERY_CONFIG entries. Until those sources are reconciled, treat the
runtime JSON as the practical source of truth, edit it directly, and mirror new
keys into `bin/i18n/json/` as required by [AGENTS.md](../AGENTS.md).

Keep locale key structure consistent with English. Inspect diffs carefully before
accepting generator output. Do not run `build-single-json.py` merely to make a
documentation change. The translation helpers remain available:

```sh
python3 bin/i18n/update-missing-translations.py --only <locale>
python3 bin/i18n/update-max-lengths.py --only <locale>
python3 bin/i18n/build-single-json.py --only <locale>
```

## Adding a locale

Create the locale files with the same keys as English and check the language
matrices in `.github/workflows/`. Packaging uses `bin/package/build_package.py`,
which includes locale generation and token resolution; review the generation step
in light of the source drift above. Coordinate locale availability with the
Wingflight updater and add sound pack data under `bin/sound-generator/` when needed.
