#!/usr/bin/env python3
"""Fail if a relative Markdown link points to a missing file. Used by CI."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")

bad = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in (".git", "__pycache__")]
    for name in filenames:
        if not name.endswith(".md"):
            continue
        path = os.path.join(dirpath, name)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        for match in LINK.finditer(text):
            target = match.group(1).split("#")[0].strip()
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            resolved = os.path.normpath(os.path.join(dirpath, target))
            if not os.path.exists(resolved):
                bad.append((os.path.relpath(path, ROOT), target))

if bad:
    print(f"{len(bad)} broken relative link(s):")
    for path, target in bad:
        print(f"  {path}: {target}")
    sys.exit(1)

print("all relative links resolve")
