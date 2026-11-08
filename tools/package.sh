#!/usr/bin/env bash
# Builds the zip to upload to CurseForge or Wago: one folder named CraftingAndFarmingForever, holding only what the game
# loads (the toc, the .lua files, LICENSE and Media textures). Built from a committed git ref, so local edits that
# aren't committed never end up in a release.
#   tools/package.sh [git ref, default HEAD]
# Writes dist/CraftingAndFarmingForever-<toc version>.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

REF="${1:-HEAD}"
NAME=CraftingAndFarmingForever
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git archive "$REF" | tar -x -C "$WORK" --one-top-level=src
SRC="$WORK/src"
VERSION=$(tr -d '\r' < "$SRC/$NAME.toc" | sed -n 's/^## Version: *//p')
[ -n "$VERSION" ] || { echo "No ## Version in the toc at $REF"; exit 1; }

# Exactly the files the toc lists, plus the license and textures. A listed file that's missing stops the build.
mkdir -p "$WORK/$NAME/Media"
cp "$SRC/$NAME.toc" "$SRC/LICENSE" "$WORK/$NAME/"
while read -r file; do
	[ -f "$SRC/$file" ] || { echo "The toc lists $file, but it isn't in $REF"; exit 1; }
	cp "$SRC/$file" "$WORK/$NAME/"
done < <(tr -d '\r' < "$SRC/$NAME.toc" | grep -E '\.lua$')
if compgen -G "$SRC/Media/*.tga" >/dev/null; then cp "$SRC"/Media/*.tga "$WORK/$NAME/Media/"; else rmdir "$WORK/$NAME/Media"; fi

mkdir -p dist
OUT="dist/$NAME-$VERSION.zip"
rm -f "$OUT"
(cd "$WORK" && bsdtar -a -cf "$OLDPWD/$OUT" "$NAME")
echo "Built $OUT from $(git rev-parse --short "$REF") (version $VERSION):"
bsdtar -tf "$OUT"
