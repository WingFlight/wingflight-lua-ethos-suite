# Locale workflow

Runtime translations live in `src/wfsuite/i18n/<locale>.json` and supply the
`@i18n(...)@` tokens used by pages and menus. The page documentation tool reads
`src/wfsuite/i18n/en.json` directly without changing any translations.

## Sources and generation

`bin/i18n/json/<locale>.json` is the source; `src/wfsuite/i18n/<locale>.json` is
generated from it and should not be edited by hand. To add or change text, edit
`bin/i18n/json/en.json`, then run:

```sh
python3 bin/i18n/update-missing-translations.py   # copy new keys to every locale
python3 bin/i18n/update-max-lengths.py            # refresh max_length
python3 bin/i18n/build-single-json.py             # regenerate src/wfsuite/i18n/
```

New keys reach other locales with the English text and `needs_translation: true`.
When English text changes, existing translations of it are reset to the new English
and flagged the same way, so a pilot never sees a translation of the old meaning.
`python3 bin/i18n/auto-translate.py` translates flagged entries in
`bin/i18n/json/` (it calls the Claude API and needs `ANTHROPIC_API_KEY`); run
`build-single-json.py` afterwards. Running the three commands again on unchanged
input changes nothing.

Check that every `@i18n(...)@` tag in `src/` has a key with
`python3 bin/i18n/check-tags.py [--lang <locale>]`.

## Adding a locale

Create the locale files with the same keys as English and check the language
matrices in `.github/workflows/`. Packaging uses `bin/package/build_package.py`,
which includes locale generation and token resolution. Coordinate locale availability with the
Wingflight updater and add sound pack data under `bin/sound-generator/` when needed.

Check a locale's manifest against the suite's audio tree before you generate or ship it, offline and without speech credentials:
  From `bin/sound-generator/`: `python generate-googleapi.py --json json/<locale>.json --base-dir <locale> --variant <variant> --check`
  It exits 1 for a declared file without a WAV, a WAV without a manifest entry (except `adjfunctions/`, which the suite generates), or a key
  that `en.json` declares and the locale lacks. Entries without a translation are listed but do not fail the check.
