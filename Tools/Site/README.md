# Tools/Site — the GitHub Pages site

The project site is built and deployed by
[`.github/workflows/pages.yml`](../../.github/workflows/pages.yml) on every push
to `main`, and on demand (*Actions → Pages → Run workflow*). It is published
as an Actions artifact, never committed: there is no `gh-pages` branch, so the
generated files never enter the history and clones do not grow.

| Path | What | Built by |
|---|---|---|
| `/` | the landing page: the hero clip, links to the three below, and the README's clips from `/media/latest/` | `Tools/Site/index.html` |
| `/docs/` | the DocC reference; `/docs/` itself redirects to `/docs/documentation/tui/` | `Tools/BuildDocs/build-docs.sh --static-hosting --hosting-base-path <base>/docs`, on macOS as CI's `docs` job does |
| `/demo/` | the Example app in WebAssembly, which loads only when the visitor presses *Run* | `Tools/Web/build.sh`, in CI's `swift:6.3.3-noble` + wasm SDK pair |
| `/media/<version>/<name>` | every asset of that version's GitHub release (tag `v<version>`) | `gh release download` |
| `/media/latest/<name>` | the newest version's, or before any version has media, the release tagged `media` | `gh release download` |
| `/404.html` | what Pages answers for any missing path | `Tools/Site/404.html` |

On a project site the base is `https://<owner>.github.io/<repository>/`, so
for this repository today: `https://wadetregaskis.github.io/TUI/`, with the
docs at `…/TUI/docs/documentation/tui/` and the demo at `…/TUI/demo/`.
Nothing in the workflow or the scripts names the repository: the base path
comes from `actions/configure-pages` and the links from `github.repository`,
so a rename (or a custom domain) needs no edit. Links to the old address
are worth checking after a rename: GitHub redirects the repository's own
URLs, and the Pages site is a different host.

## The one setting

**Settings → Pages → Build and deployment → Source: "GitHub Actions".** Until
that is set, the workflow's first job fails with "Get Pages site failed", and
nothing else is wrong. No branch, folder or token needs configuring.

## Media

The README's pictures and recordings are assets of releases rather than files
in the repository, where every clone would carry every version of every one of
them for ever. Each version's clips are attached to its release by
[`Tools/Release/release.sh`](../Release/release.sh) (see
[RELEASING.md](../../RELEASING.md)), and the workflow downloads them into
`media/<version>/`, and the newest version's again into `media/latest/`, so an
asset `mixer.webp` of release `v1.2.0` is served at `<site>/media/1.2.0/mixer.webp`
and, while 1.2.0 is the newest, at `<site>/media/latest/mixer.webp`. The README
links `latest`; a version's own notes can link its own folder, which never
changes.

Before any version has media, the release tagged `media` stands in for
`latest` (`Tools/ScreenClips/regenerate.sh --publish` uploads to it). With no
media at all the site is published without `media/`; any other failure to read
the releases (network, token) fails the run rather than publishing a site whose
pictures have vanished.

Publishing a release runs the workflow. To change a release's media
afterwards: upload to (or delete from) it, then run the workflow by hand
(*Run workflow*), since nothing in the repository changes and no push will.

## The custom domain

The site is served at **https://swift-tui.com/**, its canonical address, set
under *Settings → Pages → Custom domain* (with *Enforce HTTPS*) and pointed at
GitHub Pages by the domain's DNS records. Write the site's address as
`https://swift-tui.com/` wherever it is mentioned.

With a custom domain the site is served at the root of its host, so
`actions/configure-pages` reports an empty base path and the workflow builds
for that: nothing in the workflow names the domain. An Actions-deployed site
needs no `CNAME` file in the artifact; the domain is the Pages setting. If it
ever moves, the setting and the DNS records are all that change; GitHub's
"Managing a custom domain for your GitHub Pages site" is the reference.

## Building it locally

```sh
Tools/Site/assemble.sh --docs build --demo build      # → .build/site
python3 -m http.server -d .build/site 8000            # http://localhost:8000/
```

Each section is skipped unless asked for (`--docs`, `--demo`, `--media`), and
each takes either `build`, a path to something already built, or `skip`.
`--media release` needs `gh` signed in, or `GH_TOKEN`. `--help` has the rest.
The docs take about six minutes and the demo about five, and both need what
their own scripts need (Xcode's toolchain for the docs; swiftly's 6.3.3 and its
WebAssembly SDK for the demo — see `Tools/Web/build.sh`).

`--base-path` is the URL path the site will be served under, empty by default,
which is right for the preview above. DocC compiles it into every page, so a
docs archive built for one base path is a blank page under any other;
`assemble.sh` checks the archive it is given was built for its own.

A plain `http.server` is enough for all of it. The docs are built with
`--static-hosting`, which gives every page an `index.html` of its own, and the
demo needs cross-origin isolation, which it gets from `isolation-sw.js` when
the server does not send the headers (Pages cannot either; see
`Tools/Web/README.md`).

## Size

GitHub Pages refuses a site over 1 GB. On 2026-10-24 this one was 788 MB in
126,525 files (79%): 759 MB of docs — DocC writes a JSON file and an
`index.html` for each of 63,224 pages — and 28 MB of demo. The docs grow with
the API, so `assemble.sh` prints the total and each section's share on every
run, warns past 85% and fails past the limit, rather than leaving Pages to
refuse the deploy.

## What gets downloaded

The demo's module is gzipped by `assemble.sh` and inflated by the page as it
streams, because Pages compresses only what it chooses to. As of 2026-10-24
(Swift 6.3.3, release, no `wasm-opt`) it is 88.3 MB raw and 27.8 MB gzipped,
and that is what *Run* downloads; the page itself, the scripts and the
resources are a few hundred kilobytes more. Brotli would be smaller (not
measured: no `brotli` here; `xz -9`, for scale, makes 15.7 MB of the
name-stripped module that gzip makes 25.5 MB of), but the page would have to
inflate it itself, as it does the gzip, and `DecompressionStream` takes brotli
in too few browsers yet.
