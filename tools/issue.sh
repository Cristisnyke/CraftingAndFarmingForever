#!/usr/bin/env bash
# Opens a GitHub issue from a CurseForge post, quoting it with its author and thread. Prints the issue's URL.
#
# Usage: tools/issue.sh <bug|enhancement|question> <post id> "<title>" [stage label]
#   post id: the [id] tools/inbox.sh prints; stage: planned (default), needs-info, declined, ...
set -euo pipefail
cd "$(dirname "$0")/.."
kind=${1:?kind}; post=${2:?post id}; title=${3:?title}; stage=${4:-planned}
threads=$(tools/cf_comments.sh --cached) || { echo "CurseForge fetch failed" >&2; exit 1; }
found=$(jq -c --argjson id "$post" '.[] | .id as $thread | recurse(.replies[]?) | select(.id == $id)
	| {thread: $thread, who: .author.displayName, text: .text, when: (.datePosted / 1000 | strflocaltime("%Y-%m-%d"))}' \
	<<<"$threads" | head -1)
[ -n "$found" ] || { echo "No CurseForge post $post" >&2; exit 1; }
body=$(jq -r '"From CurseForge comment by \(.who) (thread \(.thread), \(.when)): https://www.curseforge.com/wow/addons/crafting-and-farming-forever/comments\n\n" + (.text | split("\n") | map("> " + .) | join("\n"))' <<<"$found")
gh issue create --label "$kind" --label "$stage" --title "$title" --body "$body"
