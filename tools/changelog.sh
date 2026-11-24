#!/usr/bin/env bash
# Adds a player-facing bullet under "## Unreleased" in CHANGELOG.md (making the section if needed) and regenerates
# Changelog.lua.
#
# Usage: tools/changelog.sh "Plain-words bullet for players."
set -euo pipefail
cd "$(dirname "$0")/.."
bullet=${1:?bullet text}
python3 - "$bullet" <<'PY'
import sys
path, bullet = "CHANGELOG.md", sys.argv[1].strip()
if not bullet.startswith("- "): bullet = "- " + bullet
text = open(path, encoding="utf-8").read()
if "## Unreleased\n" in text:
    head, rest = text.split("## Unreleased\n", 1)
    body, sep, tail = rest.partition("\n## ")
    body = body.rstrip("\n") + "\n" + bullet + "\n"
    text = head + "## Unreleased\n" + (body if body.startswith("\n") else "\n" + body.lstrip("\n")) + ("\n## " + tail if sep else "")
else:
    i = text.index("\n## ") + 1
    text = text[:i] + "## Unreleased\n\n" + bullet + "\n\n" + text[i:]
open(path, "w", encoding="utf-8").write(text)
PY
lua5.1 tools/gen_changelog.lua CHANGELOG.md > Changelog.lua
echo "Added to Unreleased: $bullet"
