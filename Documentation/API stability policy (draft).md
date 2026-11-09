# API stability policy (draft)

**Status: a draft for the owner to approve, written 2026-11-08. Nothing here is promised yet.** It is deliberately
not in the DocC catalog, so it does not appear on swift-tui.com. Once approved, the user-facing part becomes a DocC
article ("API stability"), `RELEASING.md` points at it, and the pre-1.0 rule of deleting old spellings outright
(the changelog's preface, `.claude/CLAUDE.md`) changes to the deprecation policy chosen below.

The decisions it waits on are listed at the end. Each section says which of them it depends on.

## What 1.0 would promise

TUI follows [Semantic Versioning 2.0.0](https://semver.org/) from 1.0.0, with the bump table already in
[`RELEASING.md`](../RELEASING.md): removing or renaming public API, changing a signature, or deliberately changing
behaviour an app could rely on is a major release; a notable feature with nothing broken is a minor one; fixes only
are a patch.

**Source compatibility within 1.x.** A program that builds against TUI 1.m builds against every later 1.n, on a
toolchain and platform that 1.n still supports, without changes to its source. Binary compatibility is not
promised: TUI is a source package built with the app, without library evolution, so there is no ABI to keep.

**What counts as the public API:**

1. Every `public` and `open` declaration reachable by importing a library product, with no leading underscore in
   its name or in the name of any type it is nested in. `Tools/Release/api_baseline.py` records them, one per line,
   in [`Tools/Release/api-baseline/`](../Tools/Release/api-baseline) (9,617 declarations in 38 modules on
   2026-11-08, underscored ones included). A declaration in a module that is not a product (`TUIStrings`,
   `TUITerminalHost`, `TUIWidthCorpus`) is covered when a product re-exports it, which is how clients reach it.
2. The names of the library products, and of the modules they make importable.
3. The package traits (`DeadStripUnusedAPI`, `UnexportTUISymbols`): their names, and that both are on by default.
4. Documented behaviour: what the DocC catalog says a view, modifier or key does, the default key bindings, and
   the end-user environment variables that are not marked experimental (the end-user table in
   `Sources/TUIEnvironmentDocs`).
5. Persisted state: an app built with 1.n reads the settings an app built with 1.m wrote (`UserDefaults` on macOS;
   `settings.json` and `UserDefaults.json` in the app's configuration directory elsewhere), at the same paths.

**What a minor or patch release may still do,** as is usual for Swift packages and not counted as breaking:

- Add declarations. In rare cases a new name or overload makes an app's unqualified reference ambiguous, or
  shadows one of the app's own names; the fix is to qualify it (`TUI.Foo`, `MyApp.Foo`).
- Add requirements with default implementations to public protocols, and cases to enums that are documented as
  growing. (Swift has no non-frozen enums outside library evolution, so which public enums may grow has to be said
  per enum: see decision 3.)
- Fix a behaviour that contradicts the documentation, or that differs from SwiftUI where the difference is not
  recorded as deliberate in [Deliberate deviations](<SwiftUI parity/Deliberate deviations from SwiftUI.md>). A fix that apps are
  likely to have depended on is called out in the release notes.
- Deprecate API (a warning, never an error), under the deprecation policy below.

## What it would not cover

- **Underscored names.** A declaration whose name, or any enclosing type's name, starts with `_` is not API, even
  when it is `public`: SwiftUI and the Swift standard library follow the same rule, and so does swift-collections.
  There are 292 such declarations under 74 names today, public only because a public protocol or SwiftUI's own
  spelling needs them. The working note `plan/broad/underscored-public.md` (in the maintainers' working notes, not
  the repository) sorts them; the 14 types it found public by accident were made `internal` or `package` on
  2026-11-09 (the owner's LEAKS ruling).
- **`package` declarations,** which clients cannot see, and `@_spi` (there is none).
- **Experimental environment variables:** those the end-user table describes as "an experiment, for trying out"
  (`TUI_CURSOR_FOLLOWS_FOCUS`, `TUI_ARROW_FOCUS`), those off pending a measurement (`TUI_GRAPHICS_PLAYBACK`), and
  every developer and internal variable (`TUI_PLAIN_TEXT=transliterate` is one). An experiment can change or go in
  any release; one that is promoted joins the promise from the release that says so.
- **The bytes TUI writes to the terminal:** the escape sequences it chooses, which cells it repaints and when, its
  glyph and colour choices for a given terminal, and frame timing. These change as terminals are measured and
  output is optimised. What is promised is the documented look and behaviour, not how it is drawn. The golden
  snapshots are TUI's own regression tests, not a contract.
- **Exact layout to the cell where it is not documented,** including changes that bring layout closer to SwiftUI's
  and, when it comes, right-to-left text.
- **Performance, memory, binary size and compile time,** which are measured and kept from regressing, but not
  promised.
- **The `Example` app, the tools under `Tools/`, the benchmarks and the test support targets.**
- **Platforms not listed as supported** (decision 9).

## Minimum Swift and macOS

Today: `swift-tools-version: 6.2` and macOS 15, with Linux supported and the lower four modules building on
Windows. Raising either minimum stops some apps building, so the policy has to say which release may do it.
The two notes in `Documentation/Swift language` (raising the floor to macOS 26, raising the minimum Swift to 6.4)
are the evidence for the next such raise.

| Option | What it means | For | Against |
|---|---|---|---|
| **A. A minor release may raise a minimum, announced one minor release ahead** | e.g. 1.4 says "1.5 needs Swift 6.4"; 1.5 does it | Common practice for Swift server packages (from general knowledge, not verified here); TUI can adopt `Span` and new SwiftUI API without waiting for 2.0 | An app on the older toolchain is held at 1.4 |
| **B. Only a major release raises a minimum** | Swift and macOS floors fixed for all of 1.x | Strongest promise | Ties TUI to Swift 6.2 and macOS 15 for as long as 1.x lasts, or forces majors for toolchain reasons alone |
| **C. A trailing window** | e.g. "the three most recent Swift releases"; raising is a minor | Predictable and automatic | Drops a toolchain on Swift's schedule rather than TUI's needs |

**Recommended: A**, with the raise listed at the top of the release notes. It depends on decision 6.

## Deprecation after 1.0

Before 1.0, a renamed or superseded spelling is deleted in the same commit. After 1.0 that is a major change each
time, so the rule has to flip. Options:

| Option | What it means | For | Against |
|---|---|---|---|
| **A. Deprecate in a minor, remove in the next major** | The old spelling stays, marked `@available(*, deprecated, renamed: "…")` (a warning with a fix-it), until the next major release removes it | The usual Swift practice; apps get a fix-it and a full major cycle | Old spellings accumulate until the major |
| **B. As A, with a minimum life** | As A, but a deprecated spelling also lives at least N minor releases or M months, even across a major | Protects apps that skip releases | More to carry; a major can't clean up everything |
| **C. Deprecate only at a major** | No deprecations in minors: renames wait for 2.0 | Fewest warnings | Fixing a bad name waits a whole cycle |

**Recommended: A.** Alongside it, two rules the owner has not had to decide before:

- **Following SwiftUI's deprecations.** Today TUI does not implement deprecated SwiftUI API, and offers
  `@available(*, unavailable, message:)` stubs for it instead. When SwiftUI deprecates something TUI already has,
  TUI would mark it deprecated in its next minor release, with the same message and replacement, and remove it (or
  turn it into an unavailable stub) at its next major.
- **Unavailable stubs are not API.** Removing an `@available(*, unavailable)` stub breaks no program that builds,
  so it may happen in any release. The baseline already leaves them out.

The changelog would record each deprecation under its release, saying what replaces it. It depends on decision 7.

## How it would be checked

`Tools/Release/api_baseline.py --check` lists every public declaration added and removed since the baseline was
written. Before a release, a removed or changed line means a major release, a deprecation done wrong, or an
underscored or experimental name (which the policy allows); an added one means at least a minor. The baseline is
rewritten in the release commit. Whether the check also runs in CI, so that each change to the public API is
acknowledged in the commit that makes it, is decision 10.

## Open owner decisions this depends on

| # | Decision | Recommended | Until decided |
|---|---|---|---|
| 1 | The scope above: what is public API (declarations, product and module names, traits, documented behaviour, end-user environment variables, persisted state) | As written | Nothing is promised |
| 2 | The underscore rule, and before 1.0 whether to make the 14 leaked types `package` or `internal`, and whether the underscored requirements on `View`, `ViewModifier`, `BufferModifier` and `Layout` stay on those public protocols | The rule; re-scope the 14; leave the requirements | Underscored names stay public and unpromised |
| 3 | Which public enums may gain cases in a minor release | A short list, stated in each enum's documentation | None may grow without a major |
| 4 | Which of the 35 library products are promised. Low-confidence ones: `TUIDocuments`, `TUIScenes`, `TUICurveEditors`, `TUITabImages`, `TUIFilePanelImages`, `TUIEnvironmentDocs`, `TUIAppKit`, `TUIFilePanelsAppKit`, `TUITesting`, `TUIMacros` (a product a client imports directly?) | Decide each before 1.0: every product kept is permanent for 1.x | All are products |
| 5 | Each experiment: promote, keep as documented-experimental, or delete before 1.0: `TUI_ARROW_FOCUS`, `TUI_CURSOR_FOLLOWS_FOCUS`, `TUI_PLAIN_TEXT=transliterate`, `TUI_GRAPHICS_PLAYBACK`, the held-press widening (A-TEXT2-1) | Keep the ones still being tried as experimental; delete any not wanted | Experimental, unpromised |
| 6 | Raising the minimum Swift or macOS | Option A | Not raised |
| 7 | Deprecation | Option A, plus following SwiftUI's deprecations | The pre-1.0 rule (delete) stands |
| 8 | Read compatibility of persisted settings across 1.x | Promise it | Unpromised |
| 9 | Supported platforms at 1.0: macOS 15 and Linux; WebAssembly (it builds and runs) and the Windows port (four modules) | macOS and Linux supported; WebAssembly best effort; Windows not yet | As recommended |
| 10 | Whether `api_baseline.py --check` runs in CI | Yes, after 1.0, failing on a removal that no release note explains | Run by hand before a release |
| 11 | The defaults 1.0 would freeze that are still open: SCROLL-REGIONS, SCROLLBAR-PLACEMENT, and the terminal probes in [Open owner decisions](<Open owner decisions.md>) | Settle them before 1.0 | They freeze as they stand |
