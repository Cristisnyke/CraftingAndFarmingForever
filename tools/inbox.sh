#!/usr/bin/env bash
# Lists GitHub activity since the last inbox (open issues/PRs, every new
# comment by someone other than the owner) and new CurseForge comments. Read-only; run on demand only.
# Usage: tools/inbox.sh [--since ISO8601] [--mark]
#   --mark  remember now as the last inbox time (~/.config/cff/inbox-last)
set -euo pipefail
repo=Cristisnyke/CraftingAndFarmingForever
owner=Cristisnyke
cf_project=1791788
cf_owner=thesnic
state="$HOME/.config/cff/inbox-last"
since=""
mark=0
while [ $# -gt 0 ]; do
	case "$1" in
		--since) since="$2"; shift 2 ;;
		--mark) mark=1; shift ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done
[ -z "$since" ] && [ -f "$state" ] && since=$(cat "$state")
[ -z "$since" ] && since="2026-11-08T00:00:00Z"  # repo went public
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "== Inbox since $since"
echo
echo "== Open issues and pull requests (* = new or updated since then)"
gh api "repos/$repo/issues?state=open&per_page=100" --paginate \
	--jq ".[] | \"\(if .updated_at > \"$since\" then \"*\" else \" \" end) #\(.number) \(if .pull_request then \"PR   \" else \"issue\" end) [\([.labels[].name] | join(\",\"))] \(.title)  (by \(.user.login), \(.created_at[:10]))\""
echo
echo "== New comments from others"
gh api "repos/$repo/issues/comments?since=$since&per_page=100" --paginate \
	--jq ".[] | select(.user.login != \"$owner\") | \"--- #\(.issue_url | split(\"/\") | last) \(.user.login) \(.created_at)\n\(.body)\n\""
gh api "repos/$repo/pulls/comments?since=$since&per_page=100" --paginate \
	--jq ".[] | select(.user.login != \"$owner\") | \"--- PR review #\(.pull_request_url | split(\"/\") | last) \(.user.login) \(.path):\(.line // \"?\")\n\(.body)\n\""
echo
echo "== Closed since then"
gh api "repos/$repo/issues?state=closed&since=$since&per_page=100" --paginate \
	--jq ".[] | select(.closed_at > \"$since\") | \"#\(.number) \(.title) (closed \(.closed_at[:10]))\""

echo
echo "== CurseForge comments since then (! = last word isn't yours: needs a reply)"
# The website's own JSON endpoint (no official comments API); plain curl works,
# the HTML page is behind Cloudflare.
since_ms=$(( $(date -d "$since" +%s) * 1000 ))
seen="[]"
for page in $(seq 0 49); do
	json=$(curl -sf -A "Mozilla/5.0" "https://www.curseforge.com/api/v1/mods/$cf_project/comments?pageIndex=$page&pageSize=20") || { echo "(CurseForge fetch failed)"; break; }
	# Pages past the end repeat the last one: stop when a page brings no new thread.
	fresh=$(jq -c --argjson seen "$seen" '[.data[] | select(.id as $id | $seen | index($id) | not)]' <<<"$json")
	[ "$fresh" = "[]" ] && break
	seen=$(jq -c --argjson seen "$seen" '$seen + [.[].id]' <<<"$fresh")
	jq -r --argjson since "$since_ms" --arg me "$cf_owner" '
		def when: (./1000 | strflocaltime("%Y-%m-%d %H:%M"));
		def post: "  \(.author.displayName) \(.datePosted | when):\n    \(.text | gsub("\\s+"; " "))";
		.[]
		| [recurse(.replies[]?)] as $all
		| select(any($all[]; .datePosted > $since))
		| ($all | max_by(.datePosted)) as $last
		| "\(if ($last.author.username | ascii_downcase) != $me then "!" else " " end) thread \(.id)",
		  ($all | sort_by(.datePosted)[] | select(.datePosted > $since or .parentId == null) | post),
		  ""' <<<"$fresh"
done

if [ "$mark" = 1 ]; then
	mkdir -p "$(dirname "$state")"
	echo "$now" > "$state"
	echo
	echo "Marked: next inbox starts at $now"
fi
