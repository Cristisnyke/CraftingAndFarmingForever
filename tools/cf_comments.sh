#!/usr/bin/env bash
# Prints every CurseForge comment thread of the project as one JSON array (replies nested in .replies), from the
# website's own JSON endpoint (no official comments API; plain curl works, the HTML pages are behind Cloudflare).
# Saves a copy in ~/.cache/cff/cf-comments.json. Exits 1 when the fetch fails.
#
# Usage: tools/cf_comments.sh [--cached]   --cached: reuse the saved copy when under 10 minutes old
set -euo pipefail
cf_project=1791788
cache="$HOME/.cache/cff/cf-comments.json"
mkdir -p "$(dirname "$cache")"
if [ "${1:-}" = "--cached" ] && [ -s "$cache" ] && [ -n "$(find "$cache" -mmin -10)" ]; then
	cat "$cache"
	exit 0
fi
threads="[]"
fetched=0
for page in $(seq 0 49); do
	json=$(curl -sf -A "Mozilla/5.0" "https://www.curseforge.com/api/v1/mods/$cf_project/comments?pageIndex=$page&pageSize=20") || exit 1
	fetched=1
	# Pages past the end repeat the last one: stop when a page brings no new thread.
	fresh=$(jq -c --argjson have "$threads" '[.data[] | select(.id as $id | $have | map(.id) | index($id) | not)]' <<<"$json")
	[ "$fresh" = "[]" ] && break
	threads=$(jq -c --argjson have "$threads" '$have + .' <<<"$fresh")
done
[ "$fetched" = 1 ] || exit 1
printf '%s\n' "$threads" > "$cache"
printf '%s\n' "$threads"
