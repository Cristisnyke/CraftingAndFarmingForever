#!/usr/bin/env bash
# Syntax check, accidental-global check and tests. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

ADDON_FILES=(Core.lua Planner.lua Data.lua Queue.lua Sales.lua Shopping.lua UI.lua)

for f in "${ADDON_FILES[@]}" tests/*.lua; do luac -p "$f"; done

# Globals the add-on itself may assign: its saved data and slash command name.
ALLOWED='CraftLedgerDB|SLASH_CRAFTLEDGER1|SLASH_CRAFTLEDGER2'
leaks=$(for f in "${ADDON_FILES[@]}"; do luac -l -p "$f" | grep SETGLOBAL || true; done | awk '{print $NF}' | grep -vE "^($ALLOWED)$" || true)
if [ -n "$leaks" ]; then
	echo "Accidental globals:"; echo "$leaks"; exit 1
fi

lua tests/planner_test.lua
lua tests/smoke_test.lua
