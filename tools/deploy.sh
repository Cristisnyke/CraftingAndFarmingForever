#!/usr/bin/env bash
# Copies the add-on into a WoW AddOns folder. Add-on files only: no tests, tools or git data.
# Default target can be overridden: tools/deploy.sh "/path/to/Interface/AddOns"
set -euo pipefail
cd "$(dirname "$0")/.."

ADDONS="${1:-/mnt/WD850SN/Games/World of Warcraft/_forever_/Interface/AddOns}"
[ -d "$ADDONS" ] || { echo "No AddOns folder at: $ADDONS"; exit 1; }

mkdir -p "$ADDONS/CraftLedger"
rsync -a --delete \
	--include='*.lua' --include='*.toc' --include='LICENSE' --exclude='*' \
	./ "$ADDONS/CraftLedger/"
echo "Deployed to $ADDONS/CraftLedger"
