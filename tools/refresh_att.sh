#!/usr/bin/env bash
# Regenerates both tables built from AllTheThings' data, Sources.lua (Farm It) and RecipeSources.lua (the Recipes
# list), from the installed AllTheThings, prints what changed and runs the checks. Run it before a release whenever
# AllTheThings has updated:
#   tools/refresh_att.sh ["<AddOns>/AllTheThings/db/Camelot"]
set -euo pipefail
cd "$(dirname "$0")/.."
ATT="${1:-/mnt/WD850SN/Games/World of Warcraft/_forever_/Interface/AddOns/AllTheThings/db/Camelot}"
[ -d "$ATT" ] || { echo "No AllTheThings data at $ATT"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

lua5.1 tools/gen_sources.lua "$ATT" > "$tmp/Sources.lua"
lua5.1 tools/gen_recipes.lua "$ATT" > "$tmp/RecipeSources.lua"

# Recipes added or gone, by ID, so a big drop (AllTheThings changed its format) shows before it ships.
ids() { grep -oE '^\[[0-9]+\]' "$1" | tr -d '[]' | sort -n; }
ids RecipeSources.lua > "$tmp/old-recipes"
ids "$tmp/RecipeSources.lua" > "$tmp/new-recipes"
added=$(comm -13 "$tmp/old-recipes" "$tmp/new-recipes" | wc -l)
removed=$(comm -23 "$tmp/old-recipes" "$tmp/new-recipes" | wc -l)
echo "AllTheThings $(grep -oE 'RECIPE_DATA_VERSION = "[^"]*"' "$tmp/RecipeSources.lua" | cut -d'"' -f2)"
echo "Recipes: $(wc -l < "$tmp/new-recipes") ($added added, $removed gone)"
if [ "$removed" -gt 0 ]; then echo "Gone: $(comm -23 "$tmp/old-recipes" "$tmp/new-recipes" | head -40 | tr '\n' ' ')"; fi
echo "Sources.lua: $(grep -c '^\[' "$tmp/Sources.lua") items, $(cmp -s Sources.lua "$tmp/Sources.lua" && echo unchanged || echo changed)"

cp "$tmp/Sources.lua" Sources.lua
cp "$tmp/RecipeSources.lua" RecipeSources.lua
tools/check.sh
git diff --stat -- Sources.lua RecipeSources.lua
