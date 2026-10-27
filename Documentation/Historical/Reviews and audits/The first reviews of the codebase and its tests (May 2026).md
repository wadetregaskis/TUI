# The first reviews of the codebase and its tests (May 2026)

*Two early reviews, kept for what they found and what they chose not to change:
a broad code review (2026-05-29: "the library is in good shape", no code
changes applied) and a review of the test suite's gaps and redundancy
(2026-05-31, 1,560 tests then). Later review batches are in
[Reviews](<../../Reviews/>).*



## Broad code review findings (2026-05-29)

A broad pass over the library source (Sources/TUI,
TUICore, TUIStyling, TUIView, TUIImage; the example
app was out of scope) looking for correctness bugs,
inefficiencies, and refactoring/readability opportunities.

**Headline: the library is in good shape.** There is no backlog
of safe, high-value fixes waiting to be applied. I deliberately
applied *no* code changes from this pass — every concrete
candidate I dug into was either already handled, not actually a
problem, or too delicate to change autonomously without better
test coverage first (detail below). I'd rather report that
honestly than make a token edit.

Findings are verified against the code, not assumed. Where a
plausible-sounding issue turned out to be a non-issue, it's
listed under "Checked and rejected" so it isn't re-chased later.

### The one real refactor candidate

#### Consolidate ANSI-sequence scanning in `String+TerminalWidth.swift`

- **File:** `Sources/TUICore/Extensions/String+TerminalWidth.swift`
  (672 lines — over the project's ~500-line guideline).
- **What:** The "scan past an ANSI escape sequence
  (`ESC [ … final-byte`)" logic is open-coded in roughly a dozen
  methods (`strippedLength`, `stripped`, `ansiAwarePrefix`,
  `ansiAwarePrefixForTerminalApp`, `ansiAwareSuffix`,
  `ansiSGRContextAndCleanSuffix`, `leadingANSISequences`,
  `containsTerminalAppCursorAdvanceQuirk`,
  `withTerminalAppCursorCompensation`, …). ~54 sites touch ESC/
  ANSI handling.
- **Why it's worth doing:** a single source of truth for "where
  does this escape sequence end" would cut duplication, shrink
  the file, and mean a parser fix lands in one place. Aligns
  with the repo's "reuse before adding" rule.
- **Why I did NOT do it now (RISK: MODERATE→HIGH):** these
  methods have genuinely *different* needs at the boundary
  (strip vs clip vs Terminal.app cursor compensation vs
  SGR-context preservation), so a shared scanner has to be
  carefully parameterised, not naively extracted. The
  Terminal.app emoji/cursor-advance behaviour is subtle (see
  `Emoji rendering bugs in macOS Sequoia's Terminal.app.md`),
  and the end-to-end test net here is shallow — a subtle
  regression could ship unnoticed.
- **Recommended approach:** *first* add characterisation tests
  that pin the current output of each public method across a
  matrix of inputs (plain / ANSI-heavy / emoji clusters /
  Fitzpatrick / CJK / boundary widths) — this doubles as closing
  a coverage gap — *then* extract a private
  `scanANSISequence(from:in:)` helper and route the methods
  through it, re-running the characterisation tests to prove
  byte-for-byte equivalence. The new `text/*` benchmarks can
  confirm no perf regression. Pinned for Wade because it's a
  judgement call on a delicate, central file.

### Minor / optional (low value, low risk)

- **`TextFieldContentRenderer.swift` (~line 157):** a boundary
  check uses a nested ternary inside a comparison
  (`visibleIndex < width - (textIndex >= clampedPosition ? 0 : 1)`).
  Correct, but hard to parse; extracting a named
  `reservedForCursor` local would read better. Cosmetic.
- **`Color+Downsampling.swift`:** the 6-entry cube-level array
  and 16-entry ANSI table use linear scans. This is *correct and
  fine* — at n=6/n=16 a linear scan beats binary search / LUT
  machinery (branch-predictable, cache-friendly). Noting it
  explicitly so the "optimise with binary search" idea isn't
  raised again: don't. A short comment naming why 6 levels exist
  would be the only worthwhile touch.
- **File-size guideline:** `String+TerminalWidth.swift` (672) is
  the main offender; `RenderLoop.swift` and a couple of others
  are worth a glance against the ~500-line guideline, but none
  are urgent.

### Checked and rejected (verified non-issues)

So these aren't re-investigated later:

- **`StateStorage.endRenderPass` "double filter":** the two
  filter loops operate on *two different dictionaries*
  (`values` and `trackedValues`); they can't be merged and the
  intermediate `staleKeys` array is needed to avoid
  mutate-while-iterate. Correct as written.
- **`TrackRenderer` `result += …` "should use a builder":** in
  Swift, `String` append is amortised O(1) on an owned buffer;
  switching to an `[String]` + `joined()` would add an array
  allocation and is not clearly faster. Not worth changing.
- **`ramp.last!` in `TrackRenderer`:** force-unwrap on a
  hardcoded non-empty `[Character]`; safe, and not in a position
  to crash.

### Positives confirmed during the pass

- No `try!` / `as!` / reachable `fatalError` found in hot paths;
  crash-safety discipline is strong.
- Darwin-only APIs are guarded with
  `#if canImport(Glibc) || canImport(Musl)`; cross-platform
  parity is maintained.
- `@unchecked Sendable` usage is minimal and justified.
- Equatable/Hashable conformances are consistent.
- The render diff / cache-invalidation path reads as correct.

## Test coverage gaps and redundancy (2026-05-31)

A review of the unit-test suite (114 test files, 1560 tests
across 210 suites, all Swift Testing — `@Suite`/`@Test`/
`#expect`) against the source. Findings are grouped into
**coverage gaps** (untested or thinly-tested code, prioritised
by risk) and **redundancy / structure** (over-testing,
duplication, missed parameterisation). Every claim below was
verified by grepping the test tree, not inferred.

### Coverage gaps (prioritised)

#### Critical — zero dedicated tests, high runtime risk

These have **no test file referencing them at all** and sit on
core paths:

- **`AppStorage` / `StorageBackend` / `JSONFileStorage` /
  `UserDefaultsStorage`** (`Sources/TUI/State/`). Persistence
  logic — Codable round-trips, the XDG/`~/.config` path
  resolution, the Linux-vs-Apple backend split, debounced
  writes — is entirely untested. This is the highest-value gap:
  it's pure, mockable (inject a `StorageBackend`), and a
  silent bug here loses user data.
- **`StdinArrivalStream` / `StdinArrivalNotifier`**
  (`Sources/TUI/App/`). The input-arrival race that replaced
  the bare `Task.sleep`. Async + `DispatchSource`; testable with
  a pipe FD. Untested.
- **`ViewRenderer`** (`Sources/TUI/Rendering/`). The core
  view→buffer entry point. Exercised incidentally but has no
  dedicated suite.

#### High — no dedicated tests, but more contained / harder

- **`InputHandler`** (`Sources/TUI/App/`). Only *indirect*
  coverage (2 integration files reference it); no suite drives
  the five-layer dispatch chain directly. Worth a dedicated
  suite: synthesise `KeyEvent`s and assert which layer consumes
  each (text-input vs status-bar vs view-handler vs focus vs
  default), including the modal-Escape special case. Mockable
  via the existing `MockTerminal` + synthetic events.
- **`OnMouseEventModifier`** and **`DragGestureModifier`**
  (`Sources/TUI/Modifiers/`). The public mouse-event and
  drag-gesture entry points — zero references. Mouse plumbing
  underneath is tested, but these surfaces aren't.
- **`SignalManager`** (`Sources/TUI/App/`). Installs real
  SIGINT/SIGWINCH handlers — genuinely awkward to unit-test
  without side effects. Recommendation: either a narrow test of
  the non-installing logic, or a **documented rationale** that
  it's covered by manual/E2E testing (this is one of the "App/
  coverage" items in the project-analysis plan).

#### Medium — thin coverage

- **`KeyPressModifier`** — referenced by only one test file;
  verify the modifier-registration + dispatch path is actually
  asserted, not just compiled.
- **`LocalizedString` / localization** — no references;
  low runtime risk but easy to cover (lookup, fallback,
  interpolation).
- **View extensions** (`Sources/TUI/Extensions/`, ~10 files)
  — no dedicated tests; behaviour is partly exercised through
  View tests. The project-analysis plan calls for targeted
  coverage here.

#### Not a gap (verified, despite first appearances)

- **`RenderContext`** is referenced by ~60 test files — it's the
  standard fixture for nearly every render test, so it's
  exercised exhaustively even without a file named after it.
- **`ASCIIConverter` / `RGBAImage`** are well covered by
  `ImageTests.swift` (contra older notes that listed them as
  gaps; the project-analysis plan has been updated accordingly).

### Redundancy / structure

#### The multi-file splits are mostly legitimate — don't merge reflexively

Earlier notes flagged "5 preference test files", "5 status-bar
test files", "5 colour test files" as redundant. On inspection
they're separation **by concern**, consistent with the project's
"one concern per file" rule, not duplication:

- Preference: `PreferenceKeyTests`, `PreferenceStorageTests`,
  `PreferenceValuesTests` — three different types.
- Status bar: `StatusBarItemTests`, `StatusBarStateTests`,
  `StatusBarViewTests`, `StatusBarSystemItemsModifierTests` —
  four distinct units.
- Colour: `ColorTests`, `ColorDownsamplingTests`,
  `ColorDepth*`, `PaletteDefaultTests`, `PaletteRegistryTests`,
  `PredefinedPaletteTests` — distinct types/behaviours.

Merging these would *hurt* navigability. No action recommended.

#### The real opportunity: parameterisation

Several suites were shaped as N near-identical `@Test` functions
that differ only in an input value — exactly what Swift Testing's
parameterised tests are for. Benefit: fewer, denser tests; adding a
case is one row, not a new function; failures report the offending
argument.

**Done:**

- `ColorDownsamplingTests` — now `@Test(arguments:)` tables:
  RGB→palette256 index, colour→ANSI16, `downsample(colour, depth)`,
  fore/background codes per colour+depth, bright-passthrough per
  depth.
- `MouseEventSGRParsingTests` — now tables: SGR/legacy sequences →
  (button, phase, x, y), plus rejected-sequence tables (the
  shift-modifier case stays standalone, asserting a different field).

**Assessed, not worth it:** the cursor / list **style** suites
(`TextCursorStyleTests`, `ListStyleTests`) are a mix of
shape→character, default-value, custom-init and `Equatable` checks
rather than one repeated mapping; they're already small and tidy, so
parameterising only the handful of mapping rows would be churn for
little gain.

#### Helper duplication

Context-creation and ANSI/render-assertion helpers are
copy-pasted across many files; there is one good shared mock
(`Tests/TUITests/Mocks/MockTerminal.swift`). A
`Tests/TUITests/TestHelpers/` area for the common
`makeContext()` / render-verifier helpers would cut duplication —
but it's a broad, churny migration touching many files, so it's
pinned for a decision rather than done unilaterally (see
`questions-for-wade.md`).

#### Possibly over-tested (low priority)

`OptionalViewTests`, `TupleViewEquatableTests`, `EdgeInsetsTests`
lean toward testing trivial conformances. Not worth removing
(cheap, and they document intent), but not worth expanding
either.

### Suggested order of attack

1. ~~`AppStorage` + backends~~ — **done** (`AppStorageTests`, `MockStorageBackend`).
2. ~~`InputHandler` five-layer dispatch suite~~ — **done**
   (`InputHandlerTests`): layer-precedence (status bar > view handlers >
   focus), the layer-4 defaults (`q`/`t`/`a`), and the modal-Escape
   special case. Layer 0 (text input) stays with the TextField tests
   since `hasTextInputFocus` keys off a real `TextFieldHandler`.
3. ~~`StdinArrivalStream`~~ — **done** (`StdinArrivalNotifierTests`).
4. ~~`OnMouseEventModifier` / `DragGestureModifier`~~ — **done**, and the
   sibling gesture modifiers too: `onTapGesture`, `onScrollGesture`.
5. ~~Parameterise `ColorDownsampling` + SGR-parsing~~ — **done**. (The
   style suites were assessed as not worth parameterising — see above.)
6. View-extension targeted tests — **largely done** (gesture modifiers,
   `String.withPersistentBackground`; `truncatedToWidth` was already
   well covered via `TextTests`). `SignalManager` covered via the
   extracted `SignalFlags` + tests.

Also closed along the way: **`ViewRenderer`** now has a dedicated suite
(`ViewRendererTests`) — writing it uncovered and fixed a real crash in
`renderOnce(_:)` (it rendered with an empty environment).

Every prioritised gap above is now closed. The ANSI-scanner
consolidation that was parked here turned out to be a real (not latent)
bug — four scanners swallowed an Extend scalar that followed an SGR
terminator; it's now fixed via the scalar-level `ansiSegments()` helper,
with `AnsiAwareScannerTests` covering all six functions. What remains is
only the low-priority "possibly over-tested" note below (no action).
