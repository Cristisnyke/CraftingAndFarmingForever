#!/usr/bin/env bash
# Syntax, top-level local room, calls between files, accidental globals, lint and tests, on Lua 5.1 as the game uses. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

# The toc decides what the game loads, so a file missing from it can't pass here unnoticed.
mapfile -t ADDON_FILES < <(tr -d '\r' < CraftingAndFarmingForever.toc | grep -E '\.lua$')
for f in *.lua; do
	printf '%s\n' "${ADDON_FILES[@]}" | grep -qx "$f" || { echo "$f is not in the toc"; exit 1; }
done

for f in "${ADDON_FILES[@]}" tests/*.lua; do luac5.1 -p "$f"; done

# Lua 5.1 refuses a chunk with more than 200 locals at its top level, and UI.lua has come close. Fail while there's
# still room (LOCALS_SPARE more must fit), so the next feature doesn't find out by breaking the build: group
# constants into a table instead of adding top-level locals. The spares go first, since a file may end in return.
LOCALS_SPARE=15
spare_locals=$(for ((i = 1; i <= LOCALS_SPARE; i++)); do printf 'local spare%d\n' "$i"; done)
for f in "${ADDON_FILES[@]}"; do
	if ! printf '%s\n%s\n' "$spare_locals" "$(cat "$f")" | luac5.1 -p - 2>/dev/null; then
		echo "$f has room for fewer than $LOCALS_SPARE more top-level locals (Lua 5.1 allows 200): group some into a table"
		exit 1
	fi
done

# Calls between files name functions that exist (luacheck can't see fields of ns).
lua5.1 tools/check_calls.lua "${ADDON_FILES[@]}"

# Globals the add-on itself may assign: its saved data and slash command name.
ALLOWED='CraftingAndFarmingForeverDB|SLASH_CFF1|SLASH_CFF2'
leaks=$(for f in "${ADDON_FILES[@]}"; do luac5.1 -l -p "$f" | grep SETGLOBAL || true; done | awk '{print $NF}' | grep -vE "^($ALLOWED)$" || true)
if [ -n "$leaks" ]; then
	echo "Accidental globals:"; echo "$leaks"; exit 1
fi

# The in-game What's new text comes from CHANGELOG.md.
if ! diff -q <(lua5.1 tools/gen_changelog.lua CHANGELOG.md) Changelog.lua >/dev/null; then
	echo "Changelog.lua is out of date: lua5.1 tools/gen_changelog.lua CHANGELOG.md > Changelog.lua"; exit 1
fi

# Linters, where installed (pacman -S luacheck shellcheck). Settings are in .luacheckrc.
if command -v luacheck >/dev/null; then luacheck . --quiet --no-color; else echo "luacheck not installed: lint skipped"; fi
if command -v shellcheck >/dev/null; then shellcheck tools/*.sh; else echo "shellcheck not installed: lint skipped"; fi

lua5.1 tests/planner_test.lua
lua5.1 tests/smoke_test.lua
