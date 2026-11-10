#!/usr/bin/env python3
"""Verify the themed icon set covers KOReader's expected names."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "tools" / "koreader-icons.txt"


def read_manifest():
    return sorted(
        line.strip()
        for line in MANIFEST.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    )


def local_icons():
    return sorted(path.stem for path in (ROOT / "assets" / "icons").glob("*.svg"))


def simpleui_references():
    pack = (ROOT / "assets" / "simpleui-icons" / "pack.lua").read_text(encoding="utf-8")
    return sorted(set(re.findall(r'=\s*"([^"]+\.svg)"', pack)))


def main():
    expected = read_manifest()
    actual = local_icons()
    missing = sorted(set(expected) - set(actual))

    if missing:
        print("Missing KOReader icons:", ", ".join(missing), file=sys.stderr)
        return 1

    extra = sorted(set(actual) - set(expected))
    if extra:
        print("Extra KOReader icons:", ", ".join(extra), file=sys.stderr)
        return 1

    simpleui = simpleui_references()
    missing_simpleui = [
        name
        for name in simpleui
        if not (ROOT / "assets" / "simpleui-icons" / name).is_file()
    ]
    if missing_simpleui:
        print("Missing SimpleUI icons:", ", ".join(missing_simpleui), file=sys.stderr)
        return 1

    print(
        f"KOReader icons: {len(actual)} local / {len(expected)} expected; "
        f"SimpleUI references: {len(simpleui)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
