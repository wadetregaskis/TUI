# Documentation build

Builds the DocC reference as **one archive covering the whole package**, with
every public symbol under `/documentation/tuikit/`.

```bash
Tools/BuildDocs/build-docs.sh --preview             # read them: serves on :8080
Tools/BuildDocs/build-docs.sh                       # → .build/docs/TUIkit.doccarchive
Tools/BuildDocs/build-docs.sh --analyze             # every diagnostic, for a docs audit
Tools/BuildDocs/build-docs.sh --strict              # --analyze, and fail on any of them
Tools/BuildDocs/build-docs.sh --static-hosting \
    --output docc-output                            # for publishing
```

**`--strict` is what CI runs, and it is not pedantry.** DocC warnings never fail
a build, and nearly all of them are broken doc *links* — a `` ``Symbol`` `` that
cannot resolve renders as plain text, so the page looks fine and nothing says a
reference was lost. Uncounted they pile up: 659 warnings by 2026-08-04, then 435
again by 2026-09-08 from 82 source lines, in both cases because the docs job
built the archive and never read what DocC said about it. `--strict` counts, and
reports SOURCE LINES as well as warnings, because one bad link in a `View`
extension is repeated onto every conforming type — 93 warnings came from one
line of `View+AlertPresenting.swift`.

## Reading the docs

**`--preview`** is the one to reach for. It runs DocC's own server and prints
the URL; open <http://localhost:8080/documentation/tuikit>.

**Xcode**: `open .build/docs/TUIkit.doccarchive`. This needs the archive to
carry an LMDB navigator index (`index/navigator.index` + `data.mdb`), which is
why the script passes `--emit-lmdb-index`. Without it Xcode opens its
documentation window on the generic landing page with the archive nowhere in
the navigator — indistinguishable from the archive failing to load.

**Not** `python3 -m http.server`. The renderer is a single-page app: it needs
a server that answers unknown deep paths with `index.html`, and the site root
`/` is not a route at all, so a dumb static server lands you on DocC's own
"The page you're looking for can't be found." A real static host needs the
`404.html` fallback (copy `index.html` to `404.html`), which is what the
publish step sets up.

## Why this exists (don't replace it with `generate-documentation`)

The obvious command —

```bash
swift package generate-documentation --target TUIkit     # ← produces a BROKEN site
```

— builds an archive with **no symbol page at all**: not `View`, `Color`,
`Binding`, `Text` or `List`, since the umbrella declares nothing (since module
split step B1), and every catalog link to a symbol dangling.

TUIkit is several library modules — `TUIkitCore`, `TUIkitStyling`,
`TUIkitView`, `TUIkitImage`, `TUIkitFoundation` (which compiles every module
of the planned split not yet carved into a target of its own), the modules
carved out of it so far (`TUIkitStrings`, `TUIkitTerminalHost`, step B2;
`TUIkitApp`, step B3), and the `TUIkit` umbrella that `@_exported import`s the rest and declares nothing.
That split buys layering, per-module test isolation and build time, and it is
*ours*: a reader writing `import TUIkit` sees one API and should never have to
learn which module happens to declare `Color`.

DocC, though, builds from symbol graphs one module at a time, and an
`@_exported` re-export does **not** copy the re-exported symbols into the
importing module's graph. Point it at `TUIkit` and you document only what
`TUIkit` itself declares, which is nothing. Point it at each module and you
get separate module trees — which leaks exactly the structure we want hidden.

So this script emits the symbol graphs, rewrites their module identity to
`TUIkit`, and hands the result to `docc convert` as one module. The three
things that must be rewritten, and what each one costs if you skip it, are
documented at the top of `unify_symbol_graphs.py` — the third (the `A@B`
filename convention) is the non-obvious one, and skipping it silently drops
every `View` modifier from the docs.

Symbol identity is the USR, which already encodes the defining module and is
left untouched, so relationships and cross-references still resolve. Nothing
about the built product changes; this is purely how the docs are assembled.

## Swift Package Index

Swift Package Index (SPI) hosts the docs the project template links to
(`/documentation/tuikit`), and it does not run this script: it runs
`generate-documentation` once per target `.spi.yml` lists, and serves the
archives behind a selector, the first as the landing page. So `.spi.yml` lists
the umbrella first (its archive is the catalog's articles, with no API, and
keeps the template's link) and then every other module in
`unify_symbol_graphs.py`'s `MODULES`, each its own archive. That shows readers
the module structure the unified build hides, and the landing page's links to
symbols dangle; the other way, one reference, needs the archive this script
builds hosted somewhere and `.spi.yml`'s `external_links` pointed at it
(decisions file `SwiftUI-API-completion-decisions-SPB1.md`, B-SPB1-2).

`check_spi_targets.py` fails the build (it runs first, and costs nothing) when
the list lacks a module of `MODULES` or does not start with the umbrella: when
the umbrella stopped declaring anything, at step B1, a list naming only it
would have published an empty reference. A module carved out of
`TUIkitFoundation` joins `MODULES`, and then the list.

## The regression guard

After converting, the script asserts that pages exist for a handful of types
declared in the sibling modules. That is precisely the failure mode this tool
exists to prevent, it costs nothing to check, and it fails loudly the day
someone "simplifies" the build back to a single target.

## Diagnostics

`--analyze` turns on DocC's full diagnostic set. The current residue is
per-symbol doc-comment hygiene — undocumented parameters, links to internal
types that have no page — not structural. Fix them at the source comment; a
link to something internal should be single-backtick code, not a
``doc-link``.

A link to one of several overloads names it by a disambiguator. Prefer the
parameter types (``init(_:content:)-(LocalizedStringKey,_)``) to DocC's hash
(``buttonStyle(_:)-5m1ib``): the hash is taken over the symbol's USR, which
names the module that declares it, so it changes whenever the symbol moves
module: the module split's step B1, which renamed the module of everything
above the lower four, broke all five hash links to those symbols. Only where
the types cannot tell the overloads apart (two generic `S` constrained
differently) is the hash the way.
