#!/usr/bin/env bash
# Copies the add-on into a WoW AddOns folder. Add-on files only (code, toc, license, Media textures): no tests, tools,
# docs or git data.
# Default target can be overridden: tools/deploy.sh "/path/to/Interface/AddOns"
set -euo pipefail
cd "$(dirname "$0")/.."

ADDONS="${1:-/mnt/WD850SN/Games/World of Warcraft/_forever_/Interface/AddOns}"
[ -d "$ADDONS" ] || { echo "No AddOns folder at: $ADDONS"; exit 1; }

mkdir -p "$ADDONS/CraftingAndFarmingForever"
rsync -a --delete \
	--include='*.lua' --include='*.toc' --include='LICENSE' --include='Media/' --include='Media/*.tga' --exclude='*' \
	./ "$ADDONS/CraftingAndFarmingForever/"
echo "Deployed to $ADDONS/CraftingAndFarmingForever"
