#!/usr/bin/env bash
#
# 🖥️ TUIkit — Terminal UI Kit for Swift
# release.sh — cuts a release from this Mac: the version, the changelog, the
# tag, the GitHub release with its notes and clips, and the site.
#
#   Tools/Release/release.sh [--version X.Y.Z] [--clips <dir>|--skip-clips] [--dry-run]
#
#   --version     the version to release; asked for when not given, with the
#                 next major, minor and patch offered
#   --clips       attach the clips already in <dir> (*.webp, *.mp4) instead of
#                 filming them again
#   --skip-clips  attach none: the site's media/latest/ then stays the last
#                 version's that had some
#   --dry-run     say what it would do, and show the notes, changing nothing
#
# What it does, in order (RELEASING.md has the why):
#
#   1. Checks: `gh` signed in; on `main`, clean, and level with `origin/main`;
#      the version a semantic version above every tag; `## Unreleased` in
#      CHANGELOG.md not empty.
#   2. Films the clips (Tools/ScreenClips/regenerate.sh) into a scratch folder,
#      unless told otherwise. That opens terminal windows: the screen must be
#      unlocked, and the machine left alone until it is done.
#   3. Writes Sources/TUIkitStrings/VERSION, turns `## Unreleased` into
#      `## X.Y.Z — <date>` under a fresh empty `## Unreleased`, commits
#      "Release X.Y.Z", and tags it `vX.Y.Z` (annotated).
#   4. Asks, then pushes `main` and the tag, creates the release as a draft
#      with that section of the changelog as its notes, uploads the clips, and
#      publishes it. Publishing runs the Pages workflow, which serves the clips
#      at media/X.Y.Z/ and media/latest/ (Tools/Site/README.md).
#
# Nothing is pushed or published without a yes at the prompt. Before it, every
# step is local and undone by `git reset --hard origin/main && git tag -d vX.Y.Z`.
#
# Bash 3.2 compatible (macOS's /bin/bash).

set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION_FILE="Sources/TUIkitStrings/VERSION"
CHANGELOG="CHANGELOG.md"
VERSION=""
CLIPS=""
SKIP_CLIPS=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --clips) CLIPS="$2"; shift 2 ;;
        --skip-clips) SKIP_CLIPS=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

fail() { echo "error: $*" >&2; exit 1; }

# ── 1. Checks ─────────────────────────────────────────────────────────────────
command -v gh >/dev/null || fail "gh is not installed (brew install gh)"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in (gh auth login)"
REPOSITORY="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

# A dry run reports these and goes on, so the notes can be read from anywhere.
check() { if [ "$DRY_RUN" = 1 ]; then echo "warning: $*" >&2; else fail "$*"; fi; }
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || check "not on main"
[ -z "$(git status --porcelain)" ] || check "the working tree is not clean"
git fetch --quiet origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || check "HEAD is not level with origin/main (pull or push first)"

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"
LAST_TAG="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -1)"

# The next major, minor and patch after `$1`, for the prompt.
next_versions() {
    local major minor patch
    IFS=. read -r major minor patch <<< "$1"
    echo "$((major + 1)).0.0 $major.$((minor + 1)).0 $major.$minor.$((patch + 1))"
}

if [ -z "$VERSION" ]; then
    BASE="${LAST_TAG#v}"; [ -n "$BASE" ] || BASE="$CURRENT"
    read -r MAJOR MINOR PATCH <<< "$(next_versions "$BASE")"
    echo "Last release: ${LAST_TAG:-none}. VERSION says $CURRENT."
    echo "Breaking changes → $MAJOR · features → $MINOR · fixes only → $PATCH"
    printf 'Version to release: '
    read -r VERSION
fi
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "'$VERSION' is not X.Y.Z"
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && fail "v$VERSION is already a tag"
if [ -n "$LAST_TAG" ] && [ "$(printf '%s\n%s\n' "${LAST_TAG#v}" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]; then
    fail "$VERSION is not above the last release, $LAST_TAG"
fi

# The `## Unreleased` section's body, without its heading: the release notes.
NOTES="$(awk '/^## Unreleased[[:space:]]*$/ {inside = 1; next} inside && /^## / {exit} inside {print}' "$CHANGELOG")"
[ -n "$(printf '%s' "$NOTES" | tr -d '[:space:]')" ] || fail "CHANGELOG.md's '## Unreleased' is empty or missing"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/release-$VERSION.XXXXXX")"
printf '%s\n' "$NOTES" > "$SCRATCH/notes.md"
DATE="$(date +%Y-%m-%d)"

echo "==> $REPOSITORY $VERSION ($DATE), after ${LAST_TAG:-no release}; notes: $(wc -l < "$SCRATCH/notes.md" | tr -d ' ') lines"
if [ "$DRY_RUN" = 1 ]; then
    echo "==> Dry run: the notes are in $SCRATCH/notes.md. Nothing changed."
    [ "$SKIP_CLIPS" = 1 ] || echo "    Would film the clips${CLIPS:+ (no: would attach $CLIPS)}."
    echo "    Would write $VERSION_FILE, date the changelog, commit, tag v$VERSION, push, release, publish."
    exit 0
fi

# ── 2. Clips ──────────────────────────────────────────────────────────────────
ASSETS=()
if [ "$SKIP_CLIPS" = 0 ]; then
    if [ -z "$CLIPS" ]; then
        [ -x Tools/ScreenClips/regenerate.sh ] || fail "no Tools/ScreenClips/regenerate.sh: pass --clips <dir> or --skip-clips"
        CLIPS="$SCRATCH/clips"
        echo "==> Filming the clips into $CLIPS (terminal windows will open; leave the machine alone)"
        Tools/ScreenClips/regenerate.sh --out "$CLIPS"
    fi
    for FILE in "$CLIPS"/*.webp "$CLIPS"/*.mp4; do
        [ -e "$FILE" ] && ASSETS+=("$FILE")
    done
    [ "${#ASSETS[@]}" -gt 0 ] || fail "no .webp or .mp4 in $CLIPS"
    echo "==> ${#ASSETS[@]} clip(s) to attach"
fi

# ── 3. Version, changelog, commit, tag ────────────────────────────────────────
printf '%s\n' "$VERSION" > "$VERSION_FILE"
awk -v heading="## $VERSION — $DATE" '
    !done && /^## Unreleased[[:space:]]*$/ { print; print ""; print heading; done = 1; next }
    { print }' "$CHANGELOG" > "$SCRATCH/CHANGELOG.md"
mv "$SCRATCH/CHANGELOG.md" "$CHANGELOG"
git add -- "$VERSION_FILE" "$CHANGELOG"
git commit --quiet -m "Release $VERSION"
git tag --annotate "v$VERSION" --file "$SCRATCH/notes.md" --cleanup=verbatim
echo "==> Committed and tagged v$VERSION locally"

# ── 4. Push, release, publish ─────────────────────────────────────────────────
printf 'Push main and v%s to origin and publish the release on %s? [y/N] ' "$VERSION" "$REPOSITORY"
read -r ANSWER
case "$ANSWER" in
    y|Y|yes) ;;
    *) echo "Stopped. Undo with: git reset --hard origin/main && git tag -d v$VERSION"; exit 1 ;;
esac
git push origin main "v$VERSION"
# A draft first, so the release is published — and the site rebuilt — only
# once its clips are attached.
gh release create "v$VERSION" --repo "$REPOSITORY" --draft --title "$VERSION" --notes-file "$SCRATCH/notes.md" --verify-tag
if [ "${#ASSETS[@]}" -gt 0 ]; then
    gh release upload "v$VERSION" --repo "$REPOSITORY" "${ASSETS[@]}"
fi
gh release edit "v$VERSION" --repo "$REPOSITORY" --draft=false --latest
echo "==> Released: https://github.com/$REPOSITORY/releases/tag/v$VERSION"
echo "    The Pages workflow is running for it: https://github.com/$REPOSITORY/actions/workflows/pages.yml"
rm -rf "$SCRATCH"
