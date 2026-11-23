#!/usr/bin/env bash
# Lists everything you haven't been shown and marked yet: open issues/PRs
# (new or updated), GitHub comments by others, closed issues and every
# CurseForge post. Read-only apart from its own state; run on demand only.
#
# Nothing is hidden by time. Each run writes the IDs it showed to
# ~/.config/cff/inbox-shown; --mark moves exactly those into
# ~/.config/cff/inbox-seen. A post that arrives after the run (even before
# --mark) was never shown, so it is listed next time.
#
# Usage: tools/inbox.sh [--mark]
#   --mark  only marks what the previous run showed (prints nothing else)
set -euo pipefail
repo=Cristisnyke/CraftingAndFarmingForever
owner=Cristisnyke
cf_project=1791788
cf_owner=thesnic
dir="$HOME/.config/cff"
seen_file="$dir/inbox-seen"
shown_file="$dir/inbox-shown"
mkdir -p "$dir"
touch "$seen_file"

if [ "${1:-}" = "--mark" ]; then
	[ -s "$shown_file" ] || { echo "Nothing to mark: run tools/inbox.sh first."; exit 0; }
	sort -u "$seen_file" "$shown_file" -o "$seen_file"
	echo "Marked $(wc -l < "$shown_file") item(s) shown by the run at $(stat -c %y "$shown_file" | cut -d. -f1)."
	rm -f "$shown_file"
	exit 0
fi
[ $# -eq 0 ] || { echo "unknown argument: $1" >&2; exit 2; }

seen=$(jq -R . < "$seen_file" | jq -sc .)
shown=$(mktemp)
trap 'rm -f "$shown"' EXIT
# GitHub's own lists are bounded by this; unseen items older than it are
# still caught because open issues are always listed in full.
window=$(date -u -d '60 days ago' +%Y-%m-%dT%H:%M:%SZ)
gh_fail=0

echo "== Open issues and pull requests (* = new or updated, not marked yet)"
gh api "repos/$repo/issues?state=open&per_page=100" --paginate --jq '.[]' \
	| jq -r --argjson seen "$seen" '
		("gh-issue:\(.number):\(.updated_at)") as $key
		| (if ($seen | index($key)) then " " else "*" end) as $new
		| "\($new) #\(.number) \(if .pull_request then "PR   " else "issue" end) [\([.labels[].name] | join(","))] \(.title)  (by \(.user.login), \(.created_at[:10]))\t\($key)"' \
	> "$shown.issues" || gh_fail=1
cut -f1 "$shown.issues"
cut -f2 "$shown.issues" >> "$shown"
rm -f "$shown.issues"

echo
echo "== GitHub comments from others, not marked yet"
{
	gh api "repos/$repo/issues/comments?since=$window&per_page=100" --paginate --jq '.[] | {k: "gh-comment:\(.id)", u: .user.login, w: .created_at, t: "--- #\(.issue_url | split("/") | last)", b: .body}' || gh_fail=1
	gh api "repos/$repo/pulls/comments?since=$window&per_page=100" --paginate --jq '.[] | {k: "gh-review:\(.id)", u: .user.login, w: .created_at, t: "--- PR review #\(.pull_request_url | split("/") | last) \(.path):\(.line // "?")", b: .body}' || gh_fail=1
} | jq -rc --argjson seen "$seen" --arg owner "$owner" '
	select(.u != $owner) | select(($seen | index(.k)) | not) | [.k, "\(.t) \(.u) \(.w)\n\(.b)\n"] | @json' \
	| while read -r row; do
		jq -r '.[1]' <<<"$row"
		jq -r '.[0]' <<<"$row" >> "$shown"
	done

echo
echo "== Closed, not marked yet"
gh api "repos/$repo/issues?state=closed&since=$window&per_page=100" --paginate --jq '.[]' \
	| jq -r --argjson seen "$seen" '
		("gh-closed:\(.number):\(.closed_at)") as $key
		| select(($seen | index($key)) | not)
		| "#\(.number) \(.title) (closed \(.closed_at[:10]))\t\($key)"' \
	| while IFS=$'\t' read -r line key; do echo "$line"; echo "$key" >> "$shown"; done || gh_fail=1

echo
echo "== CurseForge: threads with posts not marked yet (! = last word isn't yours: needs a reply)"
# The website's own JSON endpoint (no official comments API); plain curl works,
# the HTML page is behind Cloudflare.
threads="[]"
cf_fail=1
for page in $(seq 0 49); do
	json=$(curl -sf -A "Mozilla/5.0" "https://www.curseforge.com/api/v1/mods/$cf_project/comments?pageIndex=$page&pageSize=20") || { cf_fail=2; break; }
	cf_fail=0
	# Pages past the end repeat the last one: stop when a page brings no new thread.
	fresh=$(jq -c --argjson have "$threads" '[.data[] | select(.id as $id | $have | map(.id) | index($id) | not)]' <<<"$json")
	[ "$fresh" = "[]" ] && break
	threads=$(jq -c --argjson have "$threads" '$have + .' <<<"$fresh")
done
if [ "$cf_fail" != 0 ]; then
	echo "!!! CurseForge FETCH FAILED: comments NOT checked. Run again."
else
	jq -r --argjson seen "$seen" --arg me "$cf_owner" '
		def when: (./1000 | strflocaltime("%Y-%m-%d %H:%M"));
		def unseen: ("cf:\(.id)") as $k | ($seen | index($k)) == null;
		def post: "  \(if unseen then "*" else " " end) \(.author.displayName) \(.datePosted | when):\n      \(.text | gsub("\\s+"; " "))";
		.[]
		| [recurse(.replies[]?)] as $all
		| select(any($all[]; unseen))
		| ($all | max_by(.datePosted)) as $last
		| "\(if ($last.author.username | ascii_downcase) != $me then "!" else " " end) thread \(.id)",
		  ($all | sort_by(.datePosted)[] | post),
		  ""' <<<"$threads"
	jq -r '.[] | recurse(.replies[]?) | "cf:\(.id)"' <<<"$threads" >> "$shown"
	echo "(checked $(jq length <<<"$threads") threads, $(jq '[.[] | recurse(.replies[]?)] | length' <<<"$threads") posts)"
fi
[ "$gh_fail" = 0 ] || echo "!!! A GitHub request FAILED: GitHub NOT fully checked. Run again."

sort -u "$shown" > "$shown_file"
echo
echo "(* = not marked yet. tools/inbox.sh --mark marks exactly what this run showed.)"
