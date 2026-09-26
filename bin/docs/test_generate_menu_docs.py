"""Regression checks for documentation coverage and protection of authored text."""
import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import generate_menu_docs as docs


class DocumentationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'src/wfsuite'
        (self.source / 'app/pages').mkdir(parents=True)
        (self.source / 'app/pages/example.lua').write_text('return {}\n')
        (self.source / 'main.lua').write_text('local version = {major = 1, minor = 2, revision = 3}\n')
        self.tool = self.source / 'app/tool.lua'
        self.menu = '''local ROOT_ENTRIES = {
  {title = "Settings", menuId = "settings_menu", offline = true},
}
local MENUS = {
  settings_menu = {
    title = "Settings",
    entries = {
      {title = "Example", script = "app/pages/example.lua", offline = true},
    },
  },
}
-- Comments between the menu and nav are valid.
local nav = nil
'''
        self.tool.write_text(self.menu)
        self.docroot = self.root / 'docs/pages'
        for name, value in {
            'REPO_ROOT': self.root, 'TOOL_PATH': self.tool,
            'MAIN_PATH': self.source / 'main.lua',
            'DOCS_PAGES_DIR': self.docroot, 'INDEX_PATH': self.docroot / 'README.md',
        }.items():
            patcher = patch.object(docs, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)

    def run_cli(self, *args):
        with patch('sys.argv', ['generate_menu_docs.py', *args]):
            return docs.main()

    def test_scaffold_and_single_page_preserve_authored_text(self):
        self.assertEqual(self.run_cli('--scaffold-all'), 0)
        target = self.docroot / 'settings/example.md'
        target.write_text('authored text\n')
        self.run_cli('--scaffold-all')
        self.run_cli('--page', 'settings/example.md')
        self.assertEqual(target.read_text(), 'authored text\n')
        self.run_cli('--page', 'settings/example.md', '--force')
        self.assertIn('documentation_status: draft', target.read_text())

    def test_coverage_and_review_are_distinct(self):
        self.assertEqual(docs.check_docs(), 1)
        docs.scaffold_all()
        self.assertEqual(docs.check_docs(), 0)
        self.assertEqual(docs.check_docs(require_reviewed=True), 1)
        target = self.docroot / 'settings/example.md'
        target.write_text(target.read_text().replace('documentation_status: draft', 'documentation_status: reviewed'))
        self.assertEqual(docs.check_docs(), 1)  # TODOs cannot count as reviewed.

    def test_developer_settings_does_not_imply_developer_gate(self):
        self.tool.write_text(self.menu.replace('title = "Example"', 'title = "Developer settings"'))
        page = docs.parse_lua_menus()[0]
        self.assertTrue(page['conditions']['offline'])
        self.assertFalse(page['conditions'].get('developer', False))
        self.assertNotIn('armed', docs.format_conditions(page['conditions']))

    def test_offline_child_still_requires_connected_parent(self):
        self.tool.write_text(self.menu.replace('menuId = "settings_menu", offline = true', 'menuId = "settings_menu"'))
        self.assertFalse(docs.parse_lua_menus()[0]['conditions']['offline'])

    def test_comments_do_not_create_phantom_pages(self):
        self.tool.write_text(self.menu.replace('local MENUS', '-- {script = "app/pages/removed.lua"}\nlocal MENUS'))
        self.assertEqual(len(docs.parse_lua_menus()), 1)
        self.assertEqual(docs.strip_comments('"--literal" -- comment\n'), '"--literal" \n')
        self.assertEqual(docs.strip_comments('--[[hidden]]\nreturn {}'), '\nreturn {}')

    def test_missing_source_and_unknown_menu_fail(self):
        self.tool.write_text(self.menu.replace('example.lua', 'missing.lua'))
        with self.assertRaisesRegex(ValueError, 'Missing page source'):
            docs.parse_lua_menus()
        self.tool.write_text(self.menu.replace('menuId = "settings_menu"', 'menuId = "unknown"'))
        with self.assertRaisesRegex(ValueError, 'Unknown menu'):
            docs.parse_lua_menus()

    def test_cycle_fails_instead_of_recursing(self):
        self.tool.write_text(self.menu.replace('script = "app/pages/example.lua"', 'menuId = "settings_menu"'))
        with self.assertRaisesRegex(ValueError, 'Menu cycle'):
            docs.parse_lua_menus()

    def test_unreachable_script_is_not_silently_skipped(self):
        extra = '''  orphan = {
    entries = {{title = "Lost", script = "app/pages/lost.lua"}},
  },
'''
        self.tool.write_text(self.menu.replace('local MENUS = {', 'local MENUS = {\n' + extra))
        with self.assertRaisesRegex(ValueError, 'Unreachable or unparsed'):
            docs.parse_lua_menus()

    def test_duplicate_output_is_rejected(self):
        row = '{title = "Example", script = "app/pages/example.lua", offline = true},'
        self.tool.write_text(self.menu.replace(row, row + '\n      ' + row))
        with self.assertRaisesRegex(ValueError, 'Duplicate documentation'):
            docs.parse_lua_menus()

    def test_index_is_deterministic(self):
        docs.scaffold_all()
        before = docs.INDEX_PATH.read_bytes()
        docs.update_index()
        self.assertEqual(before, docs.INDEX_PATH.read_bytes())

    def test_multiple_translation_tokens_preserve_separator(self):
        with patch.object(docs, 'I18N_DATA', {'one': {'english': 'First'}, 'two': 'Second'}):
            self.assertEqual(docs.tr('"@i18n(one)@ / @i18n(two)@"'), 'First / Second')

    def test_unknown_translation_fails(self):
        with self.assertRaisesRegex(ValueError, 'Unresolved English'):
            docs.tr('@i18n(nonexistent.documentation.test)@')


if __name__ == '__main__':
    unittest.main()
