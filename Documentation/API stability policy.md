# API stability policy

**Status: decided by the owner on 2026-11-09 (the decisions are at the end), and in force from 1.0.0.** Written as
a draft on 2026-11-08. It is not in the DocC catalog yet: as 1.0 is prepared, the user-facing part becomes a DocC
article ("API stability"), `RELEASING.md` points at it, and the pre-1.0 rule of deleting old spellings outright
(the changelog's preface, `.claude/CLAUDE.md`) changes to the deprecation rule below. Until 1.0.0 is tagged, the
pre-1.0 rule stands.

Still open before 1.0: each experiment (decision 5), the defaults 1.0 freezes (decision 11), and the work that
makes WebAssembly and Windows supported (decision 9).

## What 1.0 promises

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
5. Persisted state, both ways within a major release: an app built with any 1.n reads the settings an app built
   with any 1.m wrote, older or newer (`UserDefaults` on macOS; `settings.json` and `UserDefaults.json` in the app's
   configuration directory elsewhere), at the same paths. Across major releases TUI tries to keep it too, by
   reading an old name as a fallback and writing under both old and new names (decision 8).

**What a minor or patch release may still do,** as is usual for Swift packages and not counted as breaking:

- Add declarations. In rare cases a new name or overload makes an app's unqualified reference ambiguous, or
  shadows one of the app's own names; the fix is to qualify it (`TUI.Foo`, `MyApp.Foo`).
- Add requirements with default implementations to public protocols, and cases to any public enum (decision 3).
  Swift has no non-frozen enums outside library evolution, so an app that switches over a TUI enum writes
  `@unknown default:`. Measured on Swift 6.2.4, 6.3.3 and 6.4.0 against an enum from a source package: with
  `@unknown default:` there is no warning, and when a case is added it still compiles, with a warning naming the
  new case; with `default:`, no warning either way; with neither, it stops compiling.
- Fix a behaviour that contradicts the documentation, or that differs from SwiftUI where the difference is not
  recorded as deliberate in [Deliberate deviations](<SwiftUI parity/Deliberate deviations from SwiftUI.md>). A fix that apps are
  likely to have depended on is called out in the release notes.
- Deprecate API (a warning, never an error), under the deprecation policy below.

## What it does not cover

- **Underscored names.** A declaration whose name, or any enclosing type's name, starts with `_` is not API, even
  when it is `public`: SwiftUI and the Swift standard library follow the same rule, and so does swift-collections.
  There are 292 such declarations under 74 names today, public only because a public protocol or SwiftUI's own
  spelling needs them. The working note `plan/broad/underscored-public.md` (in the maintainers' working notes, not
  the repository) sorts them; the 14 types it found public by accident were made `internal` or `package` on
  2026-11-09 (the owner's LEAKS ruling). The owner ruled the same day that underscored names may change in any
  release, and that every remaining one be checked and made `package`, `internal` or `private` unless it has to be
  public.
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

## Supported platforms

macOS 15 and later, Linux, WebAssembly and Windows, all four fully supported from 1.0 (owner, 2026-11-09; the
draft recommended WebAssembly as best effort and Windows later). As of this writing that is ahead of the code:
WebAssembly builds and runs, but CI builds it without running the test suite there, and on Windows only the four
lower modules build. Both are 1.0 work; Windows is the last large piece of it, done on a Windows VM.

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

**Decided: B** (owner, 2026-11-09): only a major release raises a minimum Swift or macOS, and any release may
lower one. The draft recommended A, a minor release raising one with a release's notice.

## Deprecation after 1.0

Before 1.0, a renamed or superseded spelling is deleted in the same commit. After 1.0 that is a major change each
time, so the rule has to flip. Options:

| Option | What it means | For | Against |
|---|---|---|---|
| **A. Deprecate in a minor, remove in the next major** | The old spelling stays, marked `@available(*, deprecated, renamed: "…")` (a warning with a fix-it), until the next major release removes it | The usual Swift practice; apps get a fix-it and a full major cycle | Old spellings accumulate until the major |
| **B. As A, with a minimum life** | As A, but a deprecated spelling also lives at least N minor releases or M months, even across a major | Protects apps that skip releases | More to carry; a major can't clean up everything |
| **C. Deprecate only at a major** | No deprecations in minors: renames wait for 2.0 | Fewest warnings | Fixing a bad name waits a whole cycle |

**Decided: A** (owner, 2026-11-09): a minor release deprecates, and the next major release removes. Alongside it:

- **SwiftUI's deprecations, case by case.** Today TUI does not implement deprecated SwiftUI API, and offers
  `@available(*, unavailable, message:)` stubs for it instead. When SwiftUI deprecates something TUI already has,
  whether TUI deprecates it too is decided each time, since SwiftUI's replacement may or may not suit a terminal
  (owner, 2026-11-09; the draft recommended always following). A deprecation it does follow works as above.
- **Unavailable stubs are not API.** Removing an `@available(*, unavailable)` stub breaks no program that builds,
  so it may happen in any release. The baseline already leaves them out.

The changelog records each deprecation under its release, saying what replaces it.

## How it is checked

`Tools/Release/api_baseline.py --check` lists every public declaration added and removed since the baseline was
written. Before a release, a removed or changed line means a major release, a deprecation done wrong, or an
underscored or experimental name (which the policy allows); an added one means at least a minor. The baseline is
rewritten in the release commit. It also runs in CI (decision 10), so that each change to the public API is
acknowledged, by rewriting the baseline, in the commit that makes it.

## The decisions

Answered by the owner on 2026-11-09, in chat; the record is in
[The owner's decisions of 2026-11-08](<Historical/SwiftUI parity process/The owner's decisions of 2026-11-08.md>).

| # | Decision | Answer |
|---|---|---|
| 1 | What is public API (declarations, product and module names, traits, documented behaviour, end-user environment variables, persisted state) | As written |
| 2 | Underscored names | Not API, and may change at any time. Every remaining underscored public is checked, and made `package`, `internal` or `private` unless it has to be public (the 14 accidental ones already were) |
| 3 | Which public enums may gain cases | Any, in any release; apps write `@unknown default:` |
| 4 | Which of the 35 library products are promised | All of them |
| 5 | Each experiment: `TUI_ARROW_FOCUS`, `TUI_CURSOR_FOLLOWS_FOCUS`, `TUI_PLAIN_TEXT=transliterate`, `TUI_GRAPHICS_PLAYBACK`, the held-press widening (A-TEXT2-1) | **Open:** the owner tests each and decides before 1.0 |
| 6 | Raising the minimum Swift or macOS | B: only a major release raises one; any release may lower one |
| 7 | Deprecation | A: deprecate in a minor, remove in the next major. SwiftUI's deprecations followed case by case |
| 8 | Read compatibility of persisted settings | Both ways within a major; kept across majors where it can be |
| 9 | Supported platforms at 1.0 | macOS, Linux, WebAssembly and Windows, all fully supported |
| 10 | `api_baseline.py --check` in CI | Yes |
| 11 | The defaults 1.0 freezes that are still open: SCROLL-REGIONS, SCROLLBAR-PLACEMENT, and the terminal probes in [Open owner decisions](<Open owner decisions.md>) | **Open** |
