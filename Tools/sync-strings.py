#!/usr/bin/env python3
"""Merge compiler-extracted strings into App/Eagar/Localizable.xcstrings.

Command-line builds extract strings (SWIFT_EMIT_LOC_STRINGS) into .stringsdata files but do
not update the catalog; Xcode's IDE does. This script does the same merge so the catalog can
be kept complete from the terminal and CI.

For every key it ensures a `ga` entry. Missing ones get a pseudo-localisation (accented,
bracketed, ~40% longer, format specifiers preserved) marked `needs_review`, so layout and
Irish-locale plumbing can be tested now (NFR-L10N-02) and a translator replaces them later.

Usage: Tools/sync-strings.py <DerivedData dir> [--check]
  --check  exit 1 if the catalog is missing keys or ga entries, without writing.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Build-target name -> its String Catalog.
CATALOGS = {
    "Eagar": ROOT / "App/Eagar/Localizable.xcstrings",
    "EagarWidgets": ROOT / "App/EagarWidgets/Localizable.xcstrings",
    "EagarShare": ROOT / "App/EagarShare/Localizable.xcstrings",
}
ACCENTS = str.maketrans(
    "aeiouAEIOUcnCNyY",
    "áéíóúÁÉÍÓÚçñÇÑýÝ",
)
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f|%)")


def pseudo(text: str) -> str:
    parts = SPECIFIER.split(text)
    specifiers = SPECIFIER.findall(text)
    out = []
    for i, part in enumerate(parts):
        out.append(part.translate(ACCENTS))
        if i < len(specifiers):
            out.append(specifiers[i])
    body = "".join(out)
    padding = "·" * max(2, round(len(text) * 0.4))
    return f"[{body} {padding}]"


def extracted_keys(derived: pathlib.Path, target: str) -> set[str]:
    keys = set()
    for path in derived.rglob("*.stringsdata"):
        if f"/{target}.build/" not in str(path) or "AppShortcuts" in path.name:
            continue
        data = json.loads(path.read_text())
        for entry in data.get("tables", {}).get("Localizable", []):
            keys.add(entry["key"])
    return keys


def sync(catalog_path: pathlib.Path, keys: set[str], check: bool) -> int:
    catalog = json.loads(catalog_path.read_text())
    strings = catalog.setdefault("strings", {})
    problems = []
    for key in sorted(keys):
        entry = strings.setdefault(key, {})
        if not entry.get("localizations", {}).get("ga"):
            problems.append(key)
            entry.setdefault("localizations", {})["ga"] = {
                "stringUnit": {"state": "needs_review", "value": pseudo(key)}
            }
    stale = sorted(set(strings) - keys)
    for key in stale:
        strings[key]["extractionState"] = "stale"
    name = catalog_path.relative_to(ROOT)
    if check:
        if problems:
            print(f"sync-strings: {name}: {len(problems)} strings missing or without ga", file=sys.stderr)
            for key in problems[:20]:
                print(f"  {key}", file=sys.stderr)
            return 1
        print(f"sync-strings: {name}: complete ({len(keys)} strings)")
        return 0
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print(f"sync-strings: {name}: {len(keys)} strings, {len(problems)} added or scaffolded, {len(stale)} stale")
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    derived = pathlib.Path(sys.argv[1])
    check = "--check" in sys.argv
    status = 0
    found_any = False
    for target, catalog_path in CATALOGS.items():
        keys = extracted_keys(derived, target)
        if not keys:
            continue
        found_any = True
        status |= sync(catalog_path, keys, check)
    if not found_any:
        print("sync-strings: no extracted strings found; build the Eagar scheme first", file=sys.stderr)
        return 2
    return status


if __name__ == "__main__":
    sys.exit(main())
