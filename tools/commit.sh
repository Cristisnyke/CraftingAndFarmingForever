#!/usr/bin/env bash
# The usual end of a change: quiet checks, commit everything, deploy to the game, issues to in-game-test.
#
# Usage: tools/commit.sh "<subject>" [issue]...   each issue adds "Fixes #N" (closed by the release push)
set -euo pipefail
cd "$(dirname "$0")/.."
subject=${1:?subject}; shift
log=$(mktemp)
trap 'rm -f "$log"' EXIT
tools/check.sh --quiet >"$log" 2>&1 || { cat "$log"; exit 1; }
grep -v '^check: OK' "$log" | grep -vE '^[0-9]+ checks, 0 failures$' || true
message="$subject"
if [ $# -gt 0 ]; then
	message+=$'\n'
	for issue in "$@"; do message+=$'\n'"Fixes #${issue#\#}"; done
fi
message+=$'\n\n'"Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git add -A
git commit -q -m "$message"
echo "Committed $(git log -1 --format=%h): $subject"
tools/deploy.sh >/dev/null && echo "Deployed (/reload in game; a new file or texture needs a client restart)."
[ $# -eq 0 ] || tools/label.sh in-game-test "$@"
