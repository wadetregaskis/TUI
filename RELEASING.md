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
the release's notes word for word, so write it for someone upgrading.

For the first release, also rewrite the changelog's opening paragraph, which
says there are no tagged releases.

## Cutting one

You need: `gh` signed in (`gh auth login`) with push access; `main` checked
out, clean, and level with `origin/main`; and, to film the clips, the screen
unlocked and the machine left alone for the few minutes the filming takes
(terminal windows open and close; see `Tools/ScreenClips/README.md`).

```bash
Tools/Release/release.sh --dry-run
```

checks everything and writes out the notes without changing anything. Then:

```bash
Tools/Release/release.sh
```

It shows the last release and offers the next major, minor and patch, then:

1. films the clips into a scratch folder (or `--clips <dir>` attaches ones
   already made, `--skip-clips` none);
2. writes `VERSION`, turns `## Unreleased` into `## X.Y.Z — <date>` under a
   new empty `## Unreleased`, commits "Release X.Y.Z" and tags `vX.Y.Z`;
3. **asks**, then pushes `main` and the tag, creates the release as a draft,
   uploads the clips and publishes it.

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
