#!/usr/bin/env python3
"""Validate repository-relative Markdown links without network access."""
from __future__ import annotations
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"(?<!!)\[[^]]*]\(([^)]+)\)")
failures: list[str] = []
documents = [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md")), *sorted((ROOT / "release").rglob("*.md"))]
for document in documents:
    for line_number, line in enumerate(document.read_text(encoding="utf-8").splitlines(), 1):
        for match in LINK.finditer(line):
            target = match.group(1).strip().split(" ", 1)[0].strip("<>")
            if not target or target.startswith(("#", "http://", "https://", "mailto:")):
                continue
            resolved = (document.parent / unquote(target.split("#", 1)[0])).resolve()
            if ROOT not in resolved.parents and resolved != ROOT:
                failures.append(f"{document.relative_to(ROOT)}:{line_number}: link escapes repository: {target}")
            elif not resolved.exists():
                failures.append(f"{document.relative_to(ROOT)}:{line_number}: missing target: {target}")
if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
print("Documentation links: OK")
