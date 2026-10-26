# Completing the SwiftUI API: decisions from lane SPB1

*Lane SPB1 took step B1 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-08: the target that compiles every planned module became
`TUIFoundation`, and `TUI` became an umbrella that only re-exports. It
changed no public API: `import TUI` gives an app what it gave before. This
file holds the judgement calls the step reached that the plan did not already
settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPB1-n — needs your decision.** Nothing has shipped for these.
- **B-SPB1-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB1-n — declined.** With the reason.

## B. Shipped

### B-SPB1-1. TUIFoundation re-exports the four lower modules

*Module structure — no API*

The single TUI module's `Exports.swift` `@_exported import`ed TUICore,
TUIStyling, TUIView and TUIImage. Within a module, those re-exports
put the lower modules' names in scope in every file of it, and the framework's
files lean on that: 482 of the 900 files B1 moves into TUIFoundation import
none of the lower modules, and most of them name `FrameBuffer`,
`RenderContext` or `Color` (counted 2026-10-08 with a grep for an
`import TUICore|View|Styling|Image` line; how many of the 482 use a lower
name was not counted).

**Shipped: `Sources/TUIFoundation/Exports.swift` re-exports the same four,**
so every file of TUIFoundation sees what it saw before, and the umbrella's
`Exports.swift` re-exports TUIFoundation and the four again (it must go on
giving them after TUIImage leaves TUIFoundation at step B5c). This is
the plan's own assumption (§4: "each module `@_exported`-imports its direct
dependencies", plan question Q4), applied to TUIFoundation now rather than
at the per-module products step, because B1 cannot compile without it or the
imports below.

**The other version:** no re-export, and an explicit import in each file that
uses a lower module, as MemberImportVisibility asks of members already.
**Price:** an import line or two in up to 482 files now, and the same kind of
edit at each carve that moves a file to a module whose dependencies differ;
and `import TUIFoundation` alone would no longer give an importer the
lower modules, which no app can do today anyway (TUIFoundation is not a
product). Nothing user-visible changes either way, so it can be revisited at
step C9b, with the per-module products.

### B-SPB1-2. Swift Package Index documents each library module on its own

*Documentation hosting — no API*

Swift Package Index (SPI) hosts the documentation the project template links
to (`swiftpackageindex.com/wadetregaskis/TUIkit/main/documentation/tui`,
in `project-template/tuikit` and `project-template/README.md`). It does not
run `Tools/BuildDocs/build-docs.sh`: it runs `generate-documentation` for each
target `.spi.yml`'s `documentation_targets` names, one archive per target,
behind a selector whose first entry is the landing page (SPIManifest's
"Common use cases" page, read 2026-10-08). The list named only `TUI`. That
archive already lacked the lower modules' types (`View`, `Color`, `Binding`);
since B1 the umbrella declares nothing, so it would hold the catalog's
articles and no API at all.

**Shipped: `.spi.yml` lists `TUI` first, then `TUIFoundation`,
`TUIView`, `TUIStyling`, `TUICore` and `TUIImage`,** every module
of `unify_symbol_graphs.py`'s `MODULES`. The landing page and the template's
link stay the umbrella's (its articles; its links to symbols render as plain
text, as the links to the lower modules' types already did), and every public
symbol is documented, under the module that declares it. A new
`Tools/BuildDocs/check_spi_targets.py`, run first by `build-docs.sh` (so by
CI's docs job), fails when the list lacks a module of `MODULES` or does not
start with the umbrella. Unmeasured: SPI's build of the new list (it runs only
on SPI, after a push); the selector and the per-target archives are SPI's
documented behaviour.

**Price:** the reader sees the module structure the unified build hides
(`Tools/BuildDocs/README.md`: "leaks exactly the structure we want hidden"),
and must know which module declares a type to find its page there; each carve
adds a module to the list and to the selector.

**The other version:** one reference, as `build-docs.sh` builds it. SPI
cannot build that archive, but `.spi.yml` can point at one hosted elsewhere
(`external_links: documentation: <url>`, in place of the builder's
`documentation_targets`): the CI docs job already builds it with
`--static-hosting`, and would gain a publish step (GitHub Pages, say).
**Price:** a publish step to write and the hosting to switch on, which is the
owner's to do; the template's link would change to that host (or SPI's page
would link through to it).
