#!/usr/bin/env python3
"""Generate and verify configuration page documentation for WFSuite Ethos.

Adapted from rotorflight/rotorflight-lua-ethos-suite PR #2369 (GPLv3).

Parses the menu navigation structure in src/wfsuite/app/tool.lua and
page definitions in src/wfsuite/app/pages/*.lua to generate, update, and
validate documentation skeletons in docs/pages/ conforming to docs/_template.md.

Usage:
    python bin/docs/generate_menu_docs.py --scaffold-all
    python bin/docs/generate_menu_docs.py --check
    python bin/docs/generate_menu_docs.py --update-index
    python bin/docs/generate_menu_docs.py --page flight_tuning/pids.md
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
TOOL_PATH = REPO_ROOT / "src" / "wfsuite" / "app" / "tool.lua"
I18N_PATH = REPO_ROOT / "src" / "wfsuite" / "i18n" / "en.json"
DOCS_PAGES_DIR = REPO_ROOT / "docs" / "pages"
TEMPLATE_PATH = REPO_ROOT / "docs" / "_template.md"
INDEX_PATH = DOCS_PAGES_DIR / "README.md"
MAIN_PATH = REPO_ROOT / "src" / "wfsuite" / "main.lua"


def get_suite_version():
    """Extract suite version string from src/wfsuite/main.lua."""
    if not MAIN_PATH.exists():
        raise ValueError("Cannot determine suite version from main.lua")
    content = MAIN_PATH.read_text(encoding="utf-8")
    m = re.search(
        r"local\s+version\s*=\s*\{\s*major\s*=\s*(\d+),\s*minor\s*=\s*(\d+),\s*revision\s*=\s*(\d+)",
        content,
    )
    if m:
        return f"{m.group(1)}.{m.group(2)}.{m.group(3)}"
    raise ValueError("Cannot determine suite version from main.lua")


def load_i18n():
    """Load base English i18n lookup table."""
    with I18N_PATH.open(encoding="utf-8") as f:
        return json.load(f)


I18N_DATA = load_i18n()


def tr(text):
    """Resolve every @i18n(key)@ token, preserving surrounding literal text."""
    def resolve(match):
        key = match.group(1)
        value = I18N_DATA
        for part in key.split("."):
            if not isinstance(value, dict) or part not in value:
                raise ValueError(f"Unresolved English locale key: {key}")
            value = value[part]
        if isinstance(value, dict):
            value = value.get("english", value.get("translation"))
        if not isinstance(value, str):
            raise ValueError(f"Invalid English locale value: {key}")
        return value
    return re.sub(r"@i18n\(([^)]+)\)@", resolve, text.strip('"\'')) if text else ""


# Stable filenames derived from the script, grouped by the root menu ID.
# No second, manually maintained inventory of Wingflight pages.
def doc_path_for(script, domain=""):
    prefix = domain.removesuffix("_menu")
    return f"{prefix + '/' if prefix else ''}{Path(script).stem}.md"


def strip_comments(content):
    """Remove Lua comments while preserving quoted strings and line boundaries."""
    pattern = r"(\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')|--\[(=*)\[[\s\S]*?\]\2\]|--[^\n]*"
    return re.sub(pattern, lambda m: m.group(1) or "\n" * m.group(0).count("\n"), content)


def parse_lua_menus():
    """Parse tool.lua navigation definitions and extract all reachable pages and breadcrumbs."""
    if not TOOL_PATH.exists():
        raise FileNotFoundError(f"Missing tool.lua at {TOOL_PATH}")
    content = strip_comments(TOOL_PATH.read_text(encoding="utf-8"))

    # Extract ROOT_ENTRIES
    root_match = re.search(r"local ROOT_ENTRIES = \{([^;]+?)\n\}", content, re.DOTALL)
    if not root_match:
        raise ValueError("Could not find ROOT_ENTRIES in tool.lua")
    root_block = root_match.group(1)

    root_entries = []
    for item in re.finditer(r"\{([^}]+)\}", root_block):
        entry_text = item.group(1)
        tm = re.search(r'title\s*=\s*("(?:[^"\\]|\\.)*"|@[^@]+@)', entry_text)
        title = tr(tm.group(1)) if tm else ""
        gm = re.search(r'group\s*=\s*("(?:[^"\\]|\\.)*"|@[^@]+@)', entry_text)
        group = tr(gm.group(1)) if gm else ""
        mm = re.search(r'menuId\s*=\s*"([^"]+)"', entry_text)
        menu_id = mm.group(1) if mm else None
        sm = re.search(r'script\s*=\s*"([^"]+)"', entry_text)
        script = sm.group(1) if sm else None
        offline = "offline = true" in entry_text
        root_entries.append({
            "title": title,
            "group": group,
            "menuId": menu_id,
            "script": script,
            "offline": offline
        })

    # Extract MENUS table block
    menus_match = re.search(r"local MENUS = \{([\s\S]+?)\n\}\s*\nlocal nav", content)
    if not menus_match:
        raise ValueError("Could not find MENUS table in tool.lua")
    menus_block = menus_match.group(1)

    # Split MENUS into individual menu declaration blocks: `  <id> = {`
    menu_blocks = {}
    current_menu = None
    current_lines = []
    for line in menus_block.splitlines():
        m = re.match(r"^\s{2}([a-zA-Z0-9_]+)\s*=\s*\{", line)
        if m:
            if current_menu:
                menu_blocks[current_menu] = "\n".join(current_lines)
            current_menu = m.group(1)
            current_lines = [line]
        elif current_menu:
            current_lines.append(line)
    if current_menu:
        menu_blocks[current_menu] = "\n".join(current_lines)

    menus = {}
    for m_id, m_body in menu_blocks.items():
        tm = re.search(r'title\s*=\s*("(?:[^"\\]|\\.)*"|@[^@]+@)', m_body)
        title = tr(tm.group(1)) if tm else ""

        entries = []
        entries_block_match = re.search(r"entries\s*=\s*\{([\s\S]*)\}", m_body)
        if entries_block_match:
            entries_content = entries_block_match.group(1)
            for e_match in re.finditer(r"\{([^{}]+)\}", entries_content):
                e_body = e_match.group(1)
                et_m = re.search(r'title\s*=\s*("(?:[^"\\]|\\.)*"|@[^@]+@)', e_body)
                if not et_m:
                    continue
                e_title = tr(et_m.group(1))
                es_m = re.search(r'script\s*=\s*"([^"]+)"', e_body)
                e_script = es_m.group(1) if es_m else None
                em_m = re.search(r'menuId\s*=\s*"([^"]+)"', e_body)
                e_menu_id = em_m.group(1) if em_m else None
                offline = "offline = true" in e_body
                requires_bus = "requiresServoBus = true" in e_body
                esc_proto_m = re.search(r"escProtocolId\s*=\s*(\d+)", e_body)
                esc_proto = esc_proto_m.group(1) if esc_proto_m else None
                developer = "visibleWhen" in e_body and "developerModeEnabled" in e_body

                entries.append({
                    "title": e_title,
                    "script": e_script,
                    "menuId": e_menu_id,
                    "offline": offline,
                    "requiresServoBus": requires_bus,
                    "escProtocolId": esc_proto,
                    "developer": developer
                })
        menus[m_id] = {"title": title, "entries": entries}

    pages_list = []

    def walk_menu(menu_id, breadcrumbs, parent_conditions=None, domain=None, ancestors=()):
        if menu_id in ancestors:
            raise ValueError(f"Menu cycle: {ancestors} -> {menu_id}")
        domain = domain or menu_id
        conds = dict(parent_conditions or {})
        menu = menus.get(menu_id)
        if not menu:
            raise ValueError(f"Unknown menu: {menu_id}")
        for order_idx, entry in enumerate(menu["entries"]):
            curr_conds = dict(conds)
            curr_conds["offline"] = conds.get("offline", False) and entry["offline"]
            if entry["requiresServoBus"]:
                curr_conds["requiresServoBus"] = True
            if entry["escProtocolId"]:
                curr_conds["escProtocolId"] = entry["escProtocolId"]
            if entry["developer"]:
                curr_conds["developer"] = True

            tile_title = entry["title"]
            curr_crumb = breadcrumbs + [tile_title]

            if entry["script"]:
                script = entry["script"]
                doc_path = doc_path_for(script, domain)
                pages_list.append({
                    "title": tile_title,
                    "script": script,
                    "doc_path": doc_path,
                    "breadcrumbs": curr_crumb,
                    "conditions": curr_conds,
                    "order": (order_idx + 1) * 10
                })
            elif entry["menuId"]:
                walk_menu(entry["menuId"], curr_crumb, curr_conds, domain, ancestors + (menu_id,))

    for r_entry in root_entries:
        group_name = r_entry["group"]
        root_title = r_entry["title"]
        crumbs = [group_name, root_title] if group_name else [root_title]
        base_conds = {"offline": r_entry["offline"]}
        if r_entry["script"]:
            script = r_entry["script"]
            doc_path = doc_path_for(script)
            pages_list.append({
                "title": root_title,
                "script": script,
                "doc_path": doc_path,
                "breadcrumbs": crumbs,
                "conditions": base_conds,
                "order": 10
            })
        elif r_entry["menuId"]:
            walk_menu(r_entry["menuId"], crumbs, base_conds)

    if not pages_list:
        raise ValueError("No reachable pages parsed")
    declared = set(re.findall(r'script\s*=\s*"([^"]+)"', root_block + menus_block))
    reached = {p["script"] for p in pages_list}
    if declared != reached:
        raise ValueError(f"Unreachable or unparsed pages: {sorted(declared - reached)}")
    paths = [p["doc_path"] for p in pages_list]
    if len(paths) != len(set(paths)):
        raise ValueError("Duplicate documentation paths; review menu aliases")
    for page in pages_list:
        if not (REPO_ROOT / "src/wfsuite" / page["script"]).is_file():
            raise ValueError(f"Missing page source: {page['script']}")
    return pages_list


def parse_page_lua(script_path):
    """Best-effort literal control labels, in source order; never execute Lua."""
    content = strip_comments((REPO_ROOT / "src/wfsuite" / script_path).read_text(encoding="utf-8"))
    quoted = r'("(?:[^"\\]|\\.)*")'
    matches = []
    for pattern in (
        rf'fieldLayout\.buildSingle\s*\([^,]+,\s*{quoted}',
        rf'(?:form\.addLine|addNumberRow|addChoiceRow)\s*\(\s*{quoted}',
    ):
        for match in re.finditer(pattern, content):
            matches.append((match.start(), tr(match.group(1))))
    for group in re.finditer(
        rf'fieldLayout\.buildGroup\s*\([^,]+,\s*{quoted}\s*,\s*\{{([\s\S]*?)\n\s*\}}\)', content
    ):
        for item in re.finditer(rf'title\s*=\s*{quoted}', group.group(2)):
            matches.append((group.start() + item.start(), f"{tr(group.group(1))} ({tr(item.group(1))})"))
    return {"fields": [{"label": label} for _, label in sorted(matches)]}


def format_conditions(conds):
    """Format access preconditions into standardized sentences."""
    sentences = []
    if conds.get("offline"):
        sentences.append("Available without a flight controller connection; the background task must be running.")
    else:
        sentences.append("Requires a running background task and a flight controller connection.")

    if conds.get("lockedWhileArmed", False):
        sentences.append("Read-only while the model is armed.")

    if conds.get("requiresServoBus"):
        sentences.append("Only available when servo bus output is configured.")

    if conds.get("escProtocolId"):
        sentences.append(f"Lit only while the flight controller reports this ESC telemetry protocol (Protocol ID: {conds['escProtocolId']}).")

    if conds.get("developer"):
        sentences.append("Hidden until *System* → *Settings* → *Developer* mode is active.")

    return " ".join(sentences)


def format_settings_table(fields):
    """Extract labels as review prompts, never infer units or firmware defaults."""
    labels = list(dict.fromkeys(f["label"].strip() for f in fields if f["label"].strip()))
    rows = ["| Setting | What it does |", "| --- | --- |"]
    for label in labels:
        label = label.replace("|", "\\|").replace("\n", " ")
        rows.append(f"| {label} | TODO: explain behaviour, displayed units, range and conditions. |")
    if not labels:
        rows.append("| TODO | Inspect the page and its helpers; automatic extraction found no controls. |")
    return "\n".join(rows)


def generate_page_doc(page_info, suite_version):
    """Create a draft from the shared template; edited docs are maintained by hand."""
    parsed = parse_page_lua(page_info["script"])
    source = REPO_ROOT / "src/wfsuite" / page_info["script"]
    target = DOCS_PAGES_DIR / page_info["doc_path"]
    values = {
        "title_yaml": json.dumps(page_info["title"], ensure_ascii=False),
        "title": page_info["title"],
        "order": str(page_info["order"]),
        "source": page_info["script"],
        "source_link": Path(os.path.relpath(source, target.parent)).as_posix(),
        "breadcrumbs": " → ".join(f"*{c}*" for c in page_info["breadcrumbs"]),
        "conditions": format_conditions(page_info["conditions"]),
        "settings": format_settings_table(parsed["fields"]),
        "version": suite_version,
    }
    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    return re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], template)


def document_status(path):
    if not path.is_file():
        return "missing"
    content = path.read_text(encoding="utf-8")
    match = re.search(r"^documentation_status: (draft|reviewed)$", content, re.MULTILINE)
    return match.group(1) if match else "unmarked"


def scaffold_all(force=False):
    """Scaffold documentation skeletons for all reachable pages."""
    pages = parse_lua_menus()
    suite_version = get_suite_version()
    created = 0
    skipped = 0

    for p in pages:
        target_file = DOCS_PAGES_DIR / p["doc_path"]
        if target_file.exists() and not force:
            skipped += 1
            continue

        target_file.parent.mkdir(parents=True, exist_ok=True)
        doc_content = generate_page_doc(p, suite_version)
        target_file.write_text(doc_content, encoding="utf-8")
        created += 1
        print(f"  Created: docs/pages/{p['doc_path']}")

    print(f"\nScaffolding complete: {created} created, {skipped} existing preserved.")
    update_index()


def update_index():
    """Generate or update docs/pages/README.md central index."""
    pages = parse_lua_menus()

    # Group pages by root domain
    sections = {}
    for p in pages:
        group_key = p["breadcrumbs"][0] if p["breadcrumbs"] else "General"
        sub_key = p["breadcrumbs"][1] if len(p["breadcrumbs"]) > 1 else ""
        section_title = f"{group_key} → {sub_key}" if sub_key else group_key
        if section_title not in sections:
            sections[section_title] = []
        sections[section_title].append(p)

    lines = [
        "---",
        "title: Pages",
        "sidebar_label: Pages",
        "---",
        "",
        "# Configuration pages",
        "",
        "Reference documentation for each configuration and settings page reachable",
        "within the WFSuite Ethos system tool.",
        "",
        f"**Coverage:** {len(pages)} reachable pages in navigation hierarchy. Drafts require review.",
        "",
        "The *Conditions* column names what hides, greys out or locks a page; the sentences",
        "and structure follow [_template.md](../_template.md).",
        "",
    ]

    for sec_title, sec_pages in sections.items():
        lines.append(f"## {sec_title}\n")
        lines.append("| Page | File | Conditions | Status |")
        lines.append("| --- | --- | --- | --- |")
        for p in sec_pages:
            doc_rel = p["doc_path"]
            doc_file = DOCS_PAGES_DIR / doc_rel
            is_written = doc_file.exists()
            status = document_status(doc_file)
            file_link = f"[{doc_rel}]({doc_rel})" if is_written else f"`{doc_rel}`"
            conds_desc = format_conditions(p["conditions"])
            lines.append(f"| {p['title']} | {file_link} | {conds_desc} | {status} |")
        lines.append("")

    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    INDEX_PATH.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")
    print(f"Updated index: docs/pages/README.md ({len(pages)} pages)")


def check_docs(require_reviewed=False):
    """Verify that all reachable pages have corresponding markdown documentation."""
    pages = parse_lua_menus()
    missing = []
    drafts = 0
    for p in pages:
        doc_file = DOCS_PAGES_DIR / p["doc_path"]
        status = document_status(doc_file)
        if status == "draft":
            drafts += 1
        if status in ("missing", "unmarked") or (require_reviewed and status != "reviewed"):
            missing.append(p)
        elif status == "reviewed" and "TODO" in doc_file.read_text(encoding="utf-8"):
            missing.append(p)

    if missing:
        print(f"FAILED: {len(missing)} of {len(pages)} pages lack valid documentation/status:")
        for m in missing:
            print(f"  Needs attention: docs/pages/{m['doc_path']} (script: {m['script']})")
        return 1

    print(f"OK: {len(pages)} reachable pages have documentation files ({drafts} drafts). Coverage does not certify content accuracy.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--scaffold-all", action="store_true", help="Generate skeletons for all reachable pages")
    parser.add_argument("--force", action="store_true", help="Overwrite existing documentation files when scaffolding")
    action.add_argument("--update-index", action="store_true", help="Rebuild docs/pages/README.md central index")
    parser.add_argument("--require-reviewed", action="store_true", help="With --check, fail on drafts")
    action.add_argument("--check", action="store_true", help="Verify that all pages have documentation")
    action.add_argument("--page", help="Scaffold documentation for a doc path or page script")

    args = parser.parse_args()
    if args.require_reviewed and not args.check:
        parser.error("--require-reviewed requires --check")
    if args.force and not (args.scaffold_all or args.page):
        parser.error("--force requires --scaffold-all or --page")

    if args.scaffold_all:
        scaffold_all(force=args.force)
        return 0
    elif args.update_index:
        update_index()
        return 0
    elif args.check:
        return check_docs(args.require_reviewed)
    elif args.page:
        pages = parse_lua_menus()
        suite_version = get_suite_version()
        matched = [p for p in pages if p["doc_path"] == args.page or p["script"] == args.page]
        if not matched:
            print(f"No page found matching: {args.page}", file=sys.stderr)
            return 1
        p = matched[0]
        content = generate_page_doc(p, suite_version)
        target = DOCS_PAGES_DIR / p["doc_path"]
        if target.exists() and not args.force:
            print(f"Preserved existing document: {target}. Use --force to replace it.")
            return 0
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        update_index()
        print(f"Generated docs/pages/{p['doc_path']}")
        return 0
    else:
        parser.print_help()
        return 0


if __name__ == "__main__":
    sys.exit(main())
