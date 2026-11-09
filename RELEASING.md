# Releasing

A release is cut from the maintainer's Mac by one script,
[`Tools/Release/release.sh`](Tools/Release/release.sh). It asks for the
version, dates the changelog, tags, publishes the GitHub release with its notes
and the README's clips, and the site follows.

## Versions

Semantic versioning, from 1.0:

| Bump | When |
|---|---|
| **Major** (2.0.0) | Anything that breaks a program that built against the last release: a public name removed or renamed, a signature changed, a behaviour an app could rely on changed on purpose |
| **Minor** (1.3.0) | A notable feature, with nothing broken |
| **Patch** (1.2.4) | Fixes only |

Before 1.0 the project made no such promise, and the 0.x tags predate it.
**1.0 comes after the rename to TUI and when the SwiftUI compatibility work is
nearly done**, not before: the rename changes every product and module name,
which is a major change by the table above.

The version lives in one file, `Sources/TUIStrings/VERSION`, which the
framework bundles (`tuiVersion`). Nothing else in the repository carries it.

## As you go

Every change a user would notice goes under `## Unreleased` in
[CHANGELOG.md](CHANGELOG.md) in the commit that makes it. That section becomes
the release's notes word for word, so write it for someone upgrading. GitHub
takes at most 125,000 characters of notes for a release, and the script stops
before tagging when the section is longer.

When it is longer, hand-write the release's highlights instead and pass the
file: `Tools/Release/release.sh --highlights <file>`. The release body is then
that file and a link to `CHANGELOG.md` at the tag; the changelog and the tag's
message keep the whole section, and the length check applies to the body. The
1.0 draft is `Documentation/Release highlights 1.0 (draft).md`.

For the first release, also rewrite the changelog preface's last paragraph,
which says TUI has not been released and makes no compatibility promise.

## The public API record

[`Tools/Release/api-baseline/`](Tools/Release/api-baseline) lists every public
declaration, one per line and one file per module, as
[`Tools/Release/api_baseline.py`](Tools/Release/api_baseline.py) extracts it
from the symbol graphs. `api_baseline.py --check` lists what was added and
removed since the record was written; rerunning it without `--check` rewrites
the record. A removed or changed line is a candidate breaking change by the
table above. It is not run by CI.

## Cutting one

You need: `gh` signed in (`gh auth login`) with push access; `main` checked
out, clean, and level with `origin/main`; and, to film the clips, the screen
unlocked and the machine left alone for the few minutes the filming takes
(terminal windows open and close; see `Tools/ScreenClips/README.md`).

```bash
Tools/Release/release.sh --dry-run
```

checks everything and writes out the notes without changing anything; it
warns where a real run would stop, and needs no `gh` sign-in. Then:

```bash
Tools/Release/release.sh
```

It shows the last release and offers the next major, minor and patch, then:

1. films the clips into a scratch folder (or `--clips <dir>` attaches ones
   already made, `--skip-clips` none);
2. writes `VERSION`, turns `## Unreleased` into `## X.Y.Z — <date>` under a
   new empty `## Unreleased`, commits "Release X.Y.Z" and tags `vX.Y.Z`;
3. **asks**, then pushes the release commit to `staging` and the tag, creates
   the release as a draft, uploads the clips and publishes it. `main` moves to
   the release commit when CI passes it, as it does for every push
   ([CONTRIBUTING.md](CONTRIBUTING.md#staging-and-main)). The release does not
   wait for that: it is cut from a `main` that already passed, and adds only
   the version and the changelog's heading.

Nothing leaves the machine before the question. Up to it,
`git reset --hard origin/main && git tag -d vX.Y.Z` undoes everything.

## After

Publishing the release runs the Pages workflow, which serves the clips at
`https://swift-tui.com/media/X.Y.Z/` and, as the newest, at
`https://swift-tui.com/media/latest/`, where the README links them
([`Tools/Site/README.md`](Tools/Site/README.md)). Check that the run went
green and that the README's pictures load.

A release's clips can be replaced later: upload to it with `--clobber`, then
run the Pages workflow by hand, since no push follows.
