#!/usr/bin/env bash
# Cut a release: set VERSION.INC, move CHANGELOG.md's Unreleased changes under the
# new version and today's date, update the changelog's compare links, then commit
# and tag. Nothing is pushed: the script prints the command that does.
#
# Usage: scripts/release.sh <version | major | minor | patch>
#
#   scripts/release.sh 0.2.0           an explicit SemVer version
#   scripts/release.sh 0.2.0-beta.1    a pre-release (the GitHub release is marked so)
#   scripts/release.sh minor           the next minor version (0.1.3 -> 0.2.0);
#                                      from a pre-release, its own version (0.2.0-dev.1 -> 0.2.0)
set -euo pipefail

cd "$(dirname "$0")/.."

die() { echo "$*" >&2; exit 1; }

[ $# -eq 1 ] || die "Usage: scripts/release.sh <version | major | minor | patch>"

current=$(scripts/check-version.sh)
semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$'
[[ "$current" =~ $semver ]]
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]} pre=${BASH_REMATCH[4]}

# The bumps follow npm's: a pre-release is released as its own version when the bump allows
case "$1" in
  major) if [[ -n "$pre" && $minor -eq 0 && $patch -eq 0 ]]; then version=$major.0.0
         else version=$((major + 1)).0.0; fi ;;
  minor) if [[ -n "$pre" && $patch -eq 0 ]]; then version=$major.$minor.0
         else version=$major.$((minor + 1)).0; fi ;;
  patch) if [[ -n "$pre" ]]; then version=$major.$minor.$patch
         else version=$major.$minor.$((patch + 1)); fi ;;
  *)     version=${1#v} ;;
esac
tag=v$version

[[ "$version" =~ $semver ]] || die "'$version' is not a SemVer version (X.Y.Z or X.Y.Z-pre.N)"
[ -z "$(git status --porcelain)" ] || die "The working tree has changes: commit or stash them first"
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = main ] || die "Release from main (on '$branch')"
! git rev-parse -q --verify "refs/tags/$tag" > /dev/null || die "Tag $tag already exists"

# The Unreleased section must say what changed
notes=$(awk '/^## \[Unreleased\]/ { on = 1; next } /^## \[/ { on = 0 } on && NF' CHANGELOG.md)
[ -n "$notes" ] || die "CHANGELOG.md: nothing under [Unreleased] to release"

repo=$(git remote get-url origin | sed -E 's#^git@github\.com:#https://github.com/#; s#\.git$##')
previous=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2> /dev/null || true)
if [ -n "$previous" ]; then
  link="[$version]: $repo/compare/$previous...$tag"
else
  link="[$version]: $repo/releases/tag/$tag"
fi
unreleased="[Unreleased]: $repo/compare/$tag...HEAD"
today=$(date +%Y-%m-%d)

# VERSION.INC keeps its CRLF line endings: only the quoted version changes
sed -i "s/\(AppVersion *= *'\)[^']*'/\1$version'/" VERSION.INC

# The new heading goes under Unreleased; the links are kept at the end, newest first
awk -v heading="## [$version] - $today" -v unreleased="$unreleased" -v link="$link" '
  /^## \[Unreleased\]/ { print; print ""; print heading; next }
  /^\[Unreleased\]: / { next }
  /^\[[0-9]+\.[0-9]+\.[0-9]+[^]]*\]: / && !linked { print unreleased; print link; linked = 1 }
  { print }
  END { if (!linked) { print ""; print unreleased; print link } }
' CHANGELOG.md > CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md

scripts/check-version.sh "$tag" > /dev/null

git add VERSION.INC CHANGELOG.md
git commit -q -m "Release $version"
git tag -a "$tag" -m "SynthMinder $version"

echo "Released $current -> $version, committed and tagged $tag."
echo "Check it (git show), then push to build the draft release:"
echo
echo "  git push --atomic origin main $tag"
