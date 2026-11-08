#!/usr/bin/env bash
# Publishes a version: checks, version bump, commit, tag, push to GitHub, zip, upload to CurseForge.
# Run it only after the version has been confirmed working in game.
#
#   tools/release.sh 1.1.0             release
#   tools/release.sh 1.1.0 --beta      beta (or --alpha)
#   tools/release.sh 1.1.0 --dry-run   everything except commit, tag, push and upload; shows what would be sent
#   tools/release.sh 1.1.0 --upload-only   upload the existing tag v1.1.0 again (after a failed upload)
#
# The changelog is the "## 1.1.0" section of CHANGELOG.md, so write it first.
# Needs the CurseForge API token in ~/.config/cff/curseforge-token and "## X-Curse-Project-ID" in the toc.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=CraftingAndFarmingForever
TOC="$NAME.toc"
TOKEN_FILE="$HOME/.config/cff/curseforge-token"
API=https://wow.curseforge.com/api
FOREVER_TYPE_SLUG=wow-forever

VERSION="${1:-}"
shift || true
RELEASE_TYPE=release DRY_RUN=0 UPLOAD_ONLY=0
for arg in "$@"; do
	case "$arg" in
		--beta) RELEASE_TYPE=beta ;;
		--alpha) RELEASE_TYPE=alpha ;;
		--dry-run) DRY_RUN=1 ;;
		--upload-only) UPLOAD_ONLY=1 ;;
		*) echo "Unknown option: $arg"; exit 1 ;;
	esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: tools/release.sh <x.y.z> [--beta|--alpha] [--dry-run|--upload-only]"; exit 1; }
TAG="v$VERSION"

die() { echo "$*"; exit 1; }
toc_field() { tr -d '\r' < "$1" | sed -n "s/^## $2: *//p"; }

# --- Checks before anything changes ---------------------------------------------------------------------------------

[ -r "$TOKEN_FILE" ] || die "No CurseForge token at $TOKEN_FILE."
TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
PROJECT_ID=$(toc_field "$TOC" X-Curse-Project-ID)
[[ "$PROJECT_ID" =~ ^[0-9]+$ ]] || die "Add '## X-Curse-Project-ID: <id>' to $TOC (the number on the CurseForge project page)."

CHANGELOG=$(python3 -c '
import sys
lines, found, out = open("CHANGELOG.md", encoding="utf-8").read().splitlines(), False, []
for line in lines:
    if line.startswith("## "):
        if found: break
        found = line[3:].strip() == sys.argv[1]
        continue
    if found: out.append(line)
print("\n".join(out).strip())' "$VERSION")
[ -n "$CHANGELOG" ] || die "CHANGELOG.md has no '## $VERSION' section, or it's empty."

if [ "$UPLOAD_ONLY" = 1 ]; then
	git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "No tag $TAG to upload."
	REF="$TAG"
else
	[ -z "$(git status --porcelain)" ] || die "Commit or stash your changes first; a release is built from committed code."
	[ "$(git branch --show-current)" = main ] || die "Release from the main branch."
	! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "Tag $TAG already exists. Use --upload-only to upload it again."
	CURRENT=$(toc_field "$TOC" Version)
	[ "$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -V | tail -1)" = "$VERSION" ] && [ "$CURRENT" != "$VERSION" ] \
		|| die "$VERSION isn't newer than the toc's $CURRENT."
	tools/check.sh >/dev/null || die "tools/check.sh failed; run it to see why."
	echo "Checks passed."
	REF=HEAD
fi

# The CurseForge game version that matches the toc's ## Interface, within WoW Forever.
INTERFACE=$(git show "$REF:$TOC" | tr -d '\r' | sed -n 's/^## Interface: *//p')
GAME_VERSION_ID=$(curl -sSf -H "X-Api-Token: $TOKEN" "$API/game/version-types" | python3 -c '
import json, sys
types = [t["id"] for t in json.load(sys.stdin) if t["slug"] == sys.argv[1]]
print(types[0] if types else "")' "$FOREVER_TYPE_SLUG")
[ -n "$GAME_VERSION_ID" ] || die "CurseForge has no '$FOREVER_TYPE_SLUG' game version type."
GAME_VERSION=$(curl -sSf -H "X-Api-Token: $TOKEN" "$API/game/versions" | python3 -c '
import json, sys
matches = [v for v in json.load(sys.stdin) if v["gameVersionTypeID"] == int(sys.argv[1]) and v.get("apiVersion") == sys.argv[2]]
matches.sort(key=lambda v: v["id"])
print(matches[-1]["id"], matches[-1]["name"]) if matches else print("")' "$GAME_VERSION_ID" "$INTERFACE")
[ -n "$GAME_VERSION" ] || die "CurseForge has no WoW Forever version for Interface $INTERFACE yet."
echo "CurseForge game version: ${GAME_VERSION#* } (id ${GAME_VERSION%% *}) for Interface $INTERFACE."

# --- Version bump, commit, tag, push ---------------------------------------------------------------------------------

if [ "$UPLOAD_ONLY" = 0 ] && [ "$DRY_RUN" = 0 ]; then
	sed -i "s/^## Version: .*/## Version: $VERSION/" "$TOC"
	git add "$TOC"
	git commit -q -m "Release $VERSION"$'\n\n'"Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
	git tag -a "$TAG" -m "Crafting and Farming Forever $VERSION"
	git push -q origin main "$TAG"
	echo "Committed, tagged $TAG and pushed to GitHub."
	REF="$TAG"
fi

# --- Zip and upload --------------------------------------------------------------------------------------------------

tools/package.sh "$REF" >/dev/null
ZIP=$(ls -t dist/"$NAME"-*.zip | head -1)
if [ "$DRY_RUN" = 1 ] && [ "$UPLOAD_ONLY" = 0 ]; then
	# The dry run's zip comes from HEAD, so it still carries the current version; the real one gets $VERSION.
	ZIP_NAME="$ZIP (built from HEAD; the release zip will say $VERSION)"
else
	ZIP="dist/$NAME-$VERSION.zip"
	[ -f "$ZIP" ] || die "Expected $ZIP from tools/package.sh."
	ZIP_NAME="$ZIP"
fi

METADATA=$(python3 -c '
import json, sys
print(json.dumps({
	"changelog": sys.argv[1], "changelogType": "markdown",
	"displayName": "Crafting and Farming Forever " + sys.argv[2],
	"gameVersions": [int(sys.argv[3])], "releaseType": sys.argv[4],
}))' "$CHANGELOG" "$VERSION" "${GAME_VERSION%% *}" "$RELEASE_TYPE")

if [ "$DRY_RUN" = 1 ]; then
	echo "Dry run. Would upload $ZIP_NAME to project $PROJECT_ID as $RELEASE_TYPE with:"
	python3 -m json.tool <<< "$METADATA"
	exit 0
fi

echo "Uploading $ZIP to CurseForge project $PROJECT_ID as $RELEASE_TYPE..."
# --form-string, not -F: -F reads ';' in a value as the start of options like ;type=, which cut the metadata short
# (1.1.0's changelog has "headings; hover") and CurseForge called it invalid JSON.
RESPONSE=$(curl -sS -w '\n%{http_code}' -H "X-Api-Token: $TOKEN" \
	--form-string "metadata=$METADATA" -F "file=@$ZIP" "$API/projects/$PROJECT_ID/upload-file")
STATUS=${RESPONSE##*$'\n'}
BODY=${RESPONSE%$'\n'*}
if [ "$STATUS" != 200 ]; then
	echo "CurseForge refused the upload (HTTP $STATUS): $BODY"
	echo "Fix the cause, then: tools/release.sh $VERSION --upload-only"
	exit 1
fi
echo "Uploaded: file id $(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("id"))' "$BODY"). CurseForge reviews it before it goes live."
