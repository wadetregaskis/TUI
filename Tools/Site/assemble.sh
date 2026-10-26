#!/usr/bin/env bash
#
# 🖥️ TUI — A Terminal UI framework for Swift
# assemble.sh — puts the GitHub Pages site together in one directory.
#
#   Tools/Site/assemble.sh [--output <dir>] [--base-path <path>]
#                          [--docs build|<archive>|skip]
#                          [--demo build|<dir>|skip]
#                          [--media release|<dir>|skip]
#                          [--repository <owner/name>]
#
#   --output      where the site goes (default .build/site); emptied first
#   --base-path   the URL path the site is served under: "/TUI" for
#                 https://<owner>.github.io/TUI/, "" (the default) for a
#                 site at the root of its host, which is what a local preview is
#   --docs        `build` runs Tools/BuildDocs/build-docs.sh for this base path;
#                 a path uses a TUI.doccarchive built with --static-hosting
#                 and --hosting-base-path <base-path>/docs (checked)
#   --demo        `build` runs Tools/Web/build.sh; a path uses a directory it
#                 produced (Tools/Web/site, or a copy of it)
#   --media       `release` downloads, with `gh` (GH_TOKEN in CI), the assets
#                 of every version's release (tags vX.Y.Z) into media/X.Y.Z/,
#                 and the newest version's again into media/latest/; before
#                 any version has media, the assets of the release tagged
#                 `media` go to media/latest/. It carries on without media if
#                 there is none yet. A path copies a folder to media/ as it is
#   --repository  for the landing page's links (default $GITHUB_REPOSITORY,
#                 else the `origin` remote)
#
# Each section defaults to `skip`, so a preview builds only what it asks for.
# The layout, and why it is this one, is in Tools/Site/README.md:
#
#   index.html  404.html   the landing page and the not-found page
#   docs/                  the DocC archive; docs/ itself redirects into it
#   demo/                  the WebAssembly demo, the module gzipped
#   media/X.Y.Z/           each version's release's assets, by file name
#   media/latest/          the newest version's (or the `media` release's)
#
# Preview (the demo's service worker makes any static server enough):
#
#   Tools/Site/assemble.sh --docs build --demo build
#   python3 -m http.server -d .build/site 8000     # http://localhost:8000/

set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

OUTPUT=".build/site"
BASE_PATH=""
DOCS="skip"
DEMO="skip"
MEDIA="skip"
REPOSITORY="${GITHUB_REPOSITORY:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --base-path) BASE_PATH="$2"; shift 2 ;;
        --docs) DOCS="$2"; shift 2 ;;
        --demo) DEMO="$2"; shift 2 ;;
        --media) MEDIA="$2"; shift 2 ;;
        --repository) REPOSITORY="$2"; shift 2 ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# One spelling of the base path from here on: empty, or a leading slash and
# no trailing one ("/TUI"). actions/configure-pages gives exactly that.
BASE_PATH="${BASE_PATH%/}"
[ -z "$BASE_PATH" ] || [ "${BASE_PATH#/}" != "$BASE_PATH" ] || BASE_PATH="/$BASE_PATH"
# DocC takes its base path without the leading slash.
DOCS_BASE="${BASE_PATH#/}/docs"
DOCS_BASE="${DOCS_BASE#/}"

if [ -z "$REPOSITORY" ]; then
    REMOTE="$(git remote get-url origin 2>/dev/null || true)"
    REPOSITORY="$(printf '%s\n' "$REMOTE" | sed -E 's#^(git@[^:]+:|[a-z]+://[^/]+/)##; s#\.git$##')"
fi
[ -n "$REPOSITORY" ] || { echo "error: no repository; pass --repository <owner/name>" >&2; exit 2; }
REPOSITORY_URL="${GITHUB_SERVER_URL:-https://github.com}/$REPOSITORY"
VERSION="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo local)}"
VERSION="${VERSION:0:12}"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Fills a template's placeholders. `|` as the delimiter because the values
# are URLs and paths; neither contains one.
fill() {
    sed -e "s|@REPOSITORY_URL@|$REPOSITORY_URL|g" \
        -e "s|@REPOSITORY@|$REPOSITORY|g" \
        -e "s|@BASE_PATH@|$BASE_PATH|g" "$1" > "$2"
}

echo "==> Landing page (base path '${BASE_PATH:-/}', $REPOSITORY)"
fill Tools/Site/index.html "$OUTPUT/index.html"
fill Tools/Site/404.html "$OUTPUT/404.html"

# ── docs/ ─────────────────────────────────────────────────────────────────────
case "$DOCS" in
    skip) echo "==> Docs: skipped" ;;
    *)
        if [ "$DOCS" = build ]; then
            Tools/BuildDocs/build-docs.sh --output "$WORK/docs" --static-hosting \
                --hosting-base-path "$DOCS_BASE"
            ARCHIVE="$WORK/docs/TUI.doccarchive"
        else
            ARCHIVE="$DOCS"
        fi
        [ -f "$ARCHIVE/documentation/tui/index.html" ] || {
            echo "error: $ARCHIVE has no documentation/tui/index.html — it is not" >&2
            echo "       a TUI archive built with --static-hosting" >&2
            exit 1
        }
        # DocC compiles the base path into every page, and an archive built
        # for another one renders a blank page wherever it is served, saying
        # nothing. So check it says ours: `baseUrl = "/TUI/docs/"`.
        if ! grep -q "baseUrl *= *\"/$DOCS_BASE/\"" "$ARCHIVE/documentation/tui/index.html"; then
            echo "error: $ARCHIVE was not built for the base path /$DOCS_BASE/" >&2
            echo "       (build it with --hosting-base-path $DOCS_BASE)" >&2
            exit 1
        fi
        echo "==> Docs: $ARCHIVE"
        mkdir -p "$OUTPUT/docs"
        cp -R "$ARCHIVE"/. "$OUTPUT/docs/"
        # The LMDB navigator is Xcode's (build-docs.sh says why it is built);
        # the web renderer reads index/index.json, beside it.
        rm -f "$OUTPUT/docs/index/navigator.index" "$OUTPUT/docs/index/data.mdb"
        # The archive's root is not a page of its own (the renderer shows "The
        # page you're looking for can't be found" there), and every page has
        # its own copy of the app, so the root can simply point at the module.
        cat > "$OUTPUT/docs/index.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>TUI documentation</title>
<meta http-equiv="refresh" content="0; url=documentation/tui/">
<link rel="canonical" href="documentation/tui/">
<p><a href="documentation/tui/">TUI documentation</a></p>
HTML
        ;;
esac

# ── demo/ ─────────────────────────────────────────────────────────────────────
case "$DEMO" in
    skip) echo "==> Demo: skipped" ;;
    *)
        if [ "$DEMO" = build ]; then
            Tools/Web/build.sh
            BUILT="Tools/Web/site"
        else
            BUILT="$DEMO"
        fi
        for file in Example.wasm manifest.json index.html worker.js wasi.js isolation-sw.js; do
            [ -f "$BUILT/$file" ] || { echo "error: no $file in $BUILT — run Tools/Web/build.sh" >&2; exit 1; }
        done
        echo "==> Demo: $BUILT"
        mkdir -p "$OUTPUT/demo"
        # By name, not the whole directory: glyph-probe.html and probe-data/
        # are a measuring tool that posts its results to serve.py.
        cp "$BUILT/index.html" "$BUILT/worker.js" "$BUILT/wasi.js" "$BUILT/isolation-sw.js" "$OUTPUT/demo/"
        [ ! -d "$BUILT/resources" ] || cp -R "$BUILT/resources" "$OUTPUT/demo/"
        # Gzipped here rather than left to the host: GitHub Pages compresses
        # what it chooses to and cannot be asked, and an uncompressed module is
        # several times the download. worker.js inflates a `.gz` module as it
        # streams. -n leaves the name and time out, so a rebuild of the same
        # module is byte-identical.
        gzip -9 -n -c "$BUILT/Example.wasm" > "$OUTPUT/demo/Example.wasm.gz"
        # The manifest names the gzipped module, says how big the download is
        # (the Run button quotes it), and puts the build in every URL, so a
        # browser holding the previous deploy in its cache (Pages allows ten
        # minutes) does not pair a new page with an old module.
        python3 - "$BUILT/manifest.json" "$OUTPUT/demo" "$VERSION" <<'PYTHON'
import json, os, sys

source, demo, version = sys.argv[1:]
with open(source) as handle:
    manifest = json.load(handle)
module = os.path.join(demo, "Example.wasm.gz")
manifest["wasm"] = f"./Example.wasm.gz?v={version}"
manifest["downloadBytes"] = os.path.getsize(module)
for entry in manifest["files"]:
    entry["url"] = f"{entry['url']}?v={version}"
with open(os.path.join(demo, "manifest.json"), "w") as handle:
    json.dump(manifest, handle, indent=2)
PYTHON
        RAW=$(wc -c < "$BUILT/Example.wasm" | tr -d ' ')
        GZ=$(wc -c < "$OUTPUT/demo/Example.wasm.gz" | tr -d ' ')
        echo "    Example.wasm $((RAW / 1000000)) MB, $((GZ / 1000000)) MB gzipped"
        ;;
esac

# ── media/ ────────────────────────────────────────────────────────────────────
case "$MEDIA" in
    skip) echo "==> Media: skipped" ;;
    release)
        # The README's pictures and recordings live as assets of releases
        # rather than in the history, where every clone would carry every
        # version of them for ever: each version's clips are attached to its
        # release (Tools/Release/release.sh), and the site serves them under
        # media/<version>/, the newest also under media/latest/, which is what
        # the README links. Before the first version with clips, the release
        # tagged `media` stands in for latest. No media at all is not an
        # error: the site goes up without until some exist. Anything else (no
        # network, no token) is, since publishing a site whose README pictures
        # have silently vanished is worse than not publishing.
        if ! RELEASES="$(gh release list --repo "$REPOSITORY" --limit 1000 --json tagName,isDraft \
                --jq '.[] | select(.isDraft | not) | .tagName' 2>&1)"; then
            echo "error: could not list $REPOSITORY's releases: $RELEASES" >&2
            exit 1
        fi
        VERSIONS="$(printf '%s\n' "$RELEASES" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V || true)"
        NEWEST=""
        for TAG in $VERSIONS; do
            COUNT="$(gh release view "$TAG" --repo "$REPOSITORY" --json assets --jq '.assets | length')"
            [ "$COUNT" = 0 ] && continue
            echo "==> Media: $COUNT asset(s) from $TAG"
            gh release download "$TAG" --repo "$REPOSITORY" --dir "$OUTPUT/media/${TAG#v}"
            NEWEST="$TAG"
        done
        if [ -n "$NEWEST" ]; then
            echo "==> Media: latest is $NEWEST"
            mkdir -p "$OUTPUT/media/latest"
            cp -R "$OUTPUT/media/${NEWEST#v}"/. "$OUTPUT/media/latest/"
        elif printf '%s\n' "$RELEASES" | grep -qx media; then
            COUNT="$(gh release view media --repo "$REPOSITORY" --json assets --jq '.assets | length')"
            if [ "$COUNT" = 0 ]; then
                echo "==> Media: no version has media and the 'media' release has no assets; none published"
            else
                echo "==> Media: no version has media yet; latest is the 'media' release's $COUNT asset(s)"
                gh release download media --repo "$REPOSITORY" --dir "$OUTPUT/media/latest"
            fi
        else
            echo "==> Media: $REPOSITORY has no release with media yet; none published"
        fi
        ;;
    *)
        echo "==> Media: $MEDIA"
        mkdir -p "$OUTPUT/media"
        cp -R "$MEDIA"/. "$OUTPUT/media/"
        ;;
esac

# GitHub Pages refuses a site over 1 GB, and this one is mostly the docs: on
# 2026-10-24, 788 MB in 126,525 files, 642 MB of it DocC's page JSON (63,224
# pages, each with a 1.6 kB index.html of its own) and 28 MB the demo. The
# docs grow with the API, so say so before Pages does, and in numbers. Sizes
# are the files' own, not `du`'s, which counts whole disk blocks (1.0 GB here).
python3 - "$OUTPUT" <<'PYTHON'
import os, sys

root = sys.argv[1]
LIMIT = 1_000_000_000
totals = {}
for base, _, names in os.walk(root):
    section = os.path.relpath(base, root).split(os.sep)[0]
    section = "(root)" if section == "." else section
    for name in names:
        count, size = totals.get(section, (0, 0))
        totals[section] = (count + 1, size + os.path.getsize(os.path.join(base, name)))
total = sum(size for _, size in totals.values())
print(f"==> {root}: {total / 1e6:.1f} MB in {sum(c for c, _ in totals.values())} files"
      f" ({100 * total / LIMIT:.0f}% of Pages' 1 GB)")
for section, (count, size) in sorted(totals.items(), key=lambda item: -item[1][1]):
    print(f"    {section:8} {size / 1e6:8.1f} MB  {count:7} files")
if total > LIMIT:
    sys.exit("error: over GitHub Pages' 1 GB limit; Pages would refuse this deploy")
if total > 0.85 * LIMIT:
    print("warning: within 15% of GitHub Pages' 1 GB limit", file=sys.stderr)
PYTHON
