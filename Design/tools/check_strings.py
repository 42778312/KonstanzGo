#!/usr/bin/env python3
"""
Lists the German keys used in a package target's code that have no English in its string catalog.

    python3 Design/tools/check_strings.py KGFeatures          # list missing keys
    python3 Design/tools/check_strings.py KGFeatures en.json  # add translations from a JSON {key: english}

Keys come from the compiler's .stringsdata files of the last Xcode build (exact, %@ / %lld as Swift writes
them); without a build, from the source text with a guess at the placeholder types.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "Packages/KonstanzKit/Sources"
INT_HINTS = ("count", "minutes", "index", "step", "stops", "number", "days", "hours", "total", "rides", "left")


def compiled_keys(target):
    """Exact keys from the compiler's .stringsdata files of the last Xcode build, when there are any."""
    build = ROOT.parents[2] / "build/DerivedData/Build/Intermediates.noindex/KonstanzKit.build"
    found = set()
    for path in build.glob(f"*/{target}*.build/Objects-normal/*/*.stringsdata"):
        for entry in json.loads(path.read_text()).get("tables", {}).get("Localizable", []):
            found.add(entry["key"])
    return found


def keys(target):
    compiled = compiled_keys(target)
    if compiled:
        return compiled
    found = set()
    pattern = re.compile(r'(?:Text|String)\(\s*(?:localized:\s*)?"((?:[^"\\]|\\.)*)"\s*,\s*bundle:\s*\.(?:module|kgDesign)', re.S)
    for path in (ROOT / target).rglob("*.swift"):
        for raw in pattern.findall(path.read_text()):
            def placeholder(match):
                inner = match.group(1)
                if inner.startswith(INT_HINTS) or "+ 1" in inner or inner.endswith(".count") or "Int(" in inner:
                    return "%lld"
                return "%@"
            found.add(re.sub(r"\\\((.*?)\)(?=[^)]*(?:\\\(|$))", placeholder, raw))
    return found


def main():
    target = sys.argv[1]
    catalog_path = ROOT / target / "Resources/Localizable.xcstrings"
    catalog = json.loads(catalog_path.read_text())
    strings = catalog["strings"]
    if len(sys.argv) > 2:
        for key, english in json.loads(Path(sys.argv[2]).read_text()).items():
            entry = strings.setdefault(key, {})
            if isinstance(english, dict):
                entry["localizations"] = english
            else:
                entry["localizations"] = {"en": {"stringUnit": {"state": "translated", "value": english}}}
        catalog["strings"] = dict(sorted(strings.items()))
        catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2))
    missing = sorted(k for k in keys(target) if "en" not in strings.get(k, {}).get("localizations", {}))
    for key in missing:
        print(key)
    print(f"{len(missing)} missing", file=sys.stderr)


main()
