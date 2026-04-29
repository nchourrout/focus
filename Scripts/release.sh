#!/usr/bin/env bash
# Cut a new release: bump VERSION, commit, tag, push.
# Usage: Scripts/release.sh 0.4.0
#
# Pushing the tag triggers .github/workflows/release.yml, which builds the
# .app on a clean macos-15 runner and attaches the zip to a GitHub Release.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>   # e.g. 0.4.0" >&2
  exit 2
fi

VERSION="$1"

# Reject anything that isn't a plain semver triplet — keeps tag/version sane.
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must look like X.Y.Z (got: $VERSION)" >&2
  exit 2
fi

TAG="v$VERSION"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree not clean — commit or stash first" >&2
  exit 1
fi

if [[ "$(git symbolic-ref --short HEAD 2>/dev/null)" != "main" ]]; then
  echo "error: must be on main (tags should follow main)" >&2
  exit 1
fi

# Idempotent: if VERSION already matches (e.g. cutting the very first release
# at the in-tree version), skip the bump commit and just tag HEAD.
echo "$VERSION" > VERSION
if ! git diff --quiet VERSION; then
  git add VERSION
  git commit -m "Release $TAG"
fi
git tag -a "$TAG" -m "Release $TAG"

echo
echo "Created commit + tag $TAG. Push with:"
echo "  git push && git push origin $TAG"
echo
echo "The release workflow runs on tag push and uploads Focus-${TAG}.zip."
