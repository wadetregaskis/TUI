# Completing the SwiftUI API: decisions from lane C9B

*Lane C9B shipped item C9b, 2026-10-11, after the owner's decision ("C9b: do it. As I understand it, we can have
the umbrella target, as well as the individuals, all with their own products, but if a user happens to overlap the
two it won't cause any harm."): a library product for every module the umbrella re-exports and for
TUIFoundation, beside `TUI`; ColorPicker's gradient, tone-curve and channel-curve editors in a module of their
own, TUIColorEditors (SIZE3's Q7, change (1)); the user guide (`Sources/TUI/TUI.docc/Articles/ChoosingProducts.md`,
with C9a's notes on where the module still shows); a "which module provides it" index generated with the docs; and a
CI fixture that builds and runs one app per product. The research is
[`Per-module products (2026-10-11)`](<../../../Historical/Per-module products (2026-10-11).md>). This file holds the
judgement calls the lane reached that the brief did not settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-C9B-n — needs your decision.** Nothing has shipped for these.
- **B-C9B-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-C9B-n — declined.** With the reason.

There is no A or C entry.

## B-C9B-1 — The module index is generated with the docs, so it reaches only a reader of the archive `build-docs.sh` builds

**Shipped.** `Tools/BuildDocs/which_module.py` writes the index (1,904 names from 27 modules, each with its module
and product) into a staged copy of the catalog when `build-docs.sh` builds the reference, so it is never staler than
the reference and no commit that changes the API has to regenerate anything. The catalog's own `ModuleIndex.md`, which
any other build shows, says where else to look.

**What that leaves out.** Nothing hosts the archive `build-docs.sh` builds: CI's docs job builds it (with
`--static-hosting`) and publishes nothing, and the documentation users are pointed at, the Swift Package Index's
(project-template/README.md), is built by SPI one module at a time without this script. There each symbol's page sits
under its module's archive, which answers "which module" one symbol at a time, but the index page shows its
ungenerated note. So today a reader sees the index only by running `build-docs.sh --preview`. The README and the guide
describe the index as part of the documentation; neither links to a hosted copy.

**Fuller versions, and their price.**
- *Host the archive* (GitHub Pages from the docs job, which already builds the static-hosting form): every page,
  index included, at a stable URL the README can link. Price: a Pages deployment and its settings, a second
  documentation site beside SPI's, and a choice of which one the template and README link.
- *Also commit the table* (for example as `Documentation/Module index.md`) with a freshness check in the docs job.
  Price: every commit that adds or moves public API must dump the symbol graphs (a build) and rewrite one shared
  file, and parallel lanes would conflict on it at every cherry-pick; CI fails a commit that forgets.

## B-C9B-2 — The per-product fixture runs on one lane

**Shipped.** `Tools/ProductSmoke/verify-products.sh` runs on the macOS 26 swift.org 6.4 lane only: its default build
system, Swift Build, fails (or warns, which the script fails on) on a module that imports a sibling it does not
declare, measured. It cost 47.9 s locally (swift.org 6.4.0, clean, 2026-10-11).

**Fuller version.** Run it on the Linux 6.4 lane as well, where SwiftPM's default build system has not been checked.
Price: one more debug build of every module per run there; it would catch a Linux-only import (a module that names a
sibling only inside an `#if os(Linux)` arm), which the macOS lane cannot see.

## B-C9B-3 — TUIView and TUIImage re-export the lower modules their API names

**Shipped 2026-10-19, (a)** (the split plan's own rule, §4 Q4, and the owner's 10-07 concern about long import
lists, settled it). `TUIView`'s API names `TUICore`'s `FrameBuffer` (`Renderable`) and `TUIStyling`'s
`Color` (a `View` there), and `TUIImage`'s names `Color` (`ASCIIPalette`), so a client of either product alone
had to import those modules beside it: with only `import TUIView`, a primitive view failed with "cannot find type
'FrameBuffer' in scope". Each now has an `Exports.swift`, as every carved module has: `TUIView` re-exports
`TUICore` and `TUIStyling`, and `TUIImage` re-exports `TUIStyling`. One import covers either product;
the product fixture's two apps write only that import. `TUICore` and `TUIStyling` still re-export nothing,
and need not: neither's API names another module's types. TUI's own modules imported both already, so no name
resolves differently. Until then (from the C9B review round) the docs said what to import beside the two.
