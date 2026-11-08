#!/usr/bin/env bash
# One-time move from the old name, CraftLedger, to CraftingAndFarmingForever in a WoW install.
# Run with the game closed: the game rewrites saved data on logout.
#   tools/migrate-name.sh ["/path/to/World of Warcraft/_forever_"]
# Copies each account's saved data to the new name (the old file stays as it was), deploys the add-on under the new
# folder name and removes the old add-on folder, so the two never load together.
set -euo pipefail
cd "$(dirname "$0")/.."

GAME="${1:-/mnt/WD850SN/Games/World of Warcraft/_forever_}"
[ -d "$GAME/Interface/AddOns" ] || { echo "No AddOns folder under: $GAME"; exit 1; }
if [ $# -eq 0 ] && pgrep -f '_forever_\\Wow.exe' >/dev/null; then
	echo "The game is running. Quit it first, so it can't overwrite the saved data afterwards."
	exit 1
fi

shopt -s nullglob
for old in "$GAME"/WTF/Account/*/SavedVariables/CraftLedger.lua; do
	new="$(dirname "$old")/CraftingAndFarmingForever.lua"
	if [ -e "$new" ]; then
		echo "Already has new saved data, left alone: $new"
		continue
	fi
	sed 's/^CraftLedgerDB = /CraftingAndFarmingForeverDB = /' "$old" > "$new"
	if [ "$(grep -c '^CraftingAndFarmingForeverDB = ' "$new")" != 1 ]; then
		rm -f "$new"
		echo "Unexpected contents in $old, nothing copied."
		exit 1
	fi
	echo "Saved data copied: $new"
done

tools/deploy.sh "$GAME/Interface/AddOns"
if [ -d "$GAME/Interface/AddOns/CraftLedger" ]; then
	rm -rf "$GAME/Interface/AddOns/CraftLedger"
	echo "Removed old add-on folder: $GAME/Interface/AddOns/CraftLedger"
fi
