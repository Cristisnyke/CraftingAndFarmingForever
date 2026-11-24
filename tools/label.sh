#!/usr/bin/env bash
# Moves issues to a stage label, taking off the other stage labels.
#
# Usage: tools/label.sh <stage> <issue>...   stage: needs-info planned in-game-test next-release declined
set -euo pipefail
stage=${1:?stage}; shift
stages=(needs-info planned in-game-test next-release declined)
printf '%s\n' "${stages[@]}" | grep -qx "$stage" || { echo "Unknown stage: $stage" >&2; exit 2; }
for issue in "$@"; do
	args=(--add-label "$stage")
	for other in "${stages[@]}"; do [ "$other" = "$stage" ] || args+=(--remove-label "$other"); done
	# Removing a label the issue hasn't got is fine for gh, so no need to look first.
	gh issue edit "${issue#\#}" "${args[@]}" >/dev/null 2>&1 \
		|| gh issue edit "${issue#\#}" --add-label "$stage" >/dev/null
	echo "#${issue#\#}: $stage"
done
