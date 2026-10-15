# Future options

Ideas that were measured or designed and then deliberately not taken, each
with what it would buy, why it was not taken now, and what would make it worth
revisiting. It is a live list:

- an option that is taken leaves this page, and its reasoning goes into the
  commit message that takes it;
- an option dropped for good moves to `Historical/`;
- a decisions entry that defers something links here, and the entry here
  links back.

Numbers are labelled as the decisions files label them: **measured** (with
where), **estimate** (with the arithmetic or its source), or **unmeasured**.
"Session notes" are the working notes beside the repository; a folder named
there holds the probe or the run.

Contents:

- [Build and binary size](#build-and-binary-size)
- [Run time](#run-time)
- [Tests and type checking](#tests-and-type-checking)
- [Features](#features)

---

## Build and binary size

### Single-module LLVM emission

**What it is.** `-enable-single-module-llvm-emission` on TUIkit's own modules,
behind a package trait as the other TUIkit-scoped compile flags are. Each
module is then emitted as one LLVM module, which lets LLVM merge and drop more
than per-file emission does.

**What it buys (measured,** Xcode's Swift 6.2.4, the flag on every module,
2026-10-11, session notes `perf/results/sme`):

| | without | with | change |
|---|--:|--:|--:|
| stripped `Stress` | 11,271,448 B | 10,705,416 B | −5.0% |
| unstripped `Stress` | 24,420,968 B | 23,040,968 B | −1.38 MB |
| clean release build, `-j 4` | 74 s | 107 s | +45% |
| frame time, warm, median over the scenarios | | | about +0.4% (dashboard +2.5%) |
| frame time, cold, median over the scenarios | | | about +0.6% (dashboard +2.0%) |

The box was busy for the warm run, so its figures are indicative. Every build
of TUIkit would pay the compile time, and peak compile memory rose by 0.2 to
0.45 GB (measured on a busy box, indicative). Debug information is close but
not equal: about 4% of TUIkit's functions lose a symbol of their own, and 2%
of the lines that hold code lose their line rows (session notes
`SYMS/notes.md` §2.2).

**Why not now.** The owner, 2026-10-12: not now, because the build is 45%
slower and the run time slightly worse, for 5% of the bytes.

**What would reopen it.** A size target the other levers cannot meet, or a
compiler on which the build-time or run-time cost goes away.

### Full LTO with conditional runtime records

**What it is.** A build mode, not a flag: full LTO over the whole program with
`-conditional-runtime-records` and `-internalize-at-link`, so a conformance or
type record is kept only if its type and protocol are otherwise used. Today
every record is kept, and a kept record keeps its witness table and its code,
which is why a "Hello" app keeps `Table`'s renderer. It is the app's build
that chooses it, not TUIkit's.

**What it buys (measured,** session notes `SIZE3/answers.md` Q9): "Hello"
−36%, `Stress` −28%. Three kinds of reflection descriptor (closure captures,
builtins, multi-payload enums) are still always kept by the compiler, and they
name types such as `_TableCore`, so they keep whole modules alive. With that
fixed upstream, "Hello" would be 3.73 MB, −67.6% (emulated, not built).

**Why not now.** The flags are hidden and experimental, and their known
problems apply to TUIkit: records stripped before the merge have crashed an
app (swift#65021, open); links take 35–40 s instead of 2 s; SwiftPM's final
link loses the debug information for LTO code (spm#6890); on Swift 6.4 with
SwiftBuild a plain `swift build` fails if the root package has a library
product; on Linux nothing is stripped (measured); and `_typeByName` cannot find
a type nothing references, which a saved `NavigationPath` can name. No run-time
A/B has been run. The compiler-flag stack TUIkit can apply by itself reaches
about the same size without LTO (−37.0% against −36.3%).

**What would reopen it.** The upstream fix that stops the three descriptor
kinds being always kept (a feature request is drafted in the session notes,
`SIZE3/q/condrec-request.md`), then a run-time A/B. Until both exist TUIkit
does not recommend the mode.

### The machine outliner and mergeable traps

**What they are.** `-Xllvm -enable-machine-outliner=always`, which folds
repeated instruction sequences into shared `OUTLINED_FUNCTION_n` bodies, and
`-Xfrontend -mergeable-traps`, which lets every trap in a function share one
`brk`.

**What they buy (measured,** "Hello", session notes `SYMS/notes.md` §2.3 and
§2.4): the outliner −346,080 B stripped (−2.8%) but +1,499,936 B unstripped
(18,017 more local symbols); mergeable traps −0.45% stripped.

**Why not.** Both cost debuggability, and nothing recovers it:

- With the outliner, a stop or a profile sample inside an outlined body reads
  `OUTLINED_FUNCTION_n` at `<compiler-generated>:0`, shared by many callers.
- With mergeable traps, a crash inside TUIkit keeps the function's name but not
  which check failed or where: an index out of range on line 2, another on line
  3 and a failed precondition on line 4 all stop at the same address, in lldb
  and in the crash report.

Recommended against on 2026-10-11. The owner's 2026-10-12 ruling on a related
link flag (`-non_global_symbols_strip_list`: no, "we need to support debugging
properly") applies the same reasoning.

**What would reopen it.** A way to keep the line information, or a size
target that only these can meet.

### Pay-for-use run-loop services

**What it is.** The run loop and the base module reach a feature family
through a slot that the family's views fill, rather than by name, so the
family can be carved into a leaf module and an app that never uses it links
none of it. Seven families were inventoried: gestures, drag and drop, the
toolbar, undo, timelines, tooltips and notifications.

**What it buys (estimate,** session notes `PAYU/estimate.md` §7, after a
prototype of the drag family and an independent estimate):

- "Hello", after the per-module products and internalize: −0.36 to −0.37 MB
  for all seven families (a model's upper bound).
- About half of that, ≈203 KB, needs no hook at all: the gesture API, the drag
  API and the timelines carve out as they are, in ≈1.6 lane-days (0.8–3.7).
- The hooks themselves cost bytes: the drag hook alone measured +4.7 KB.
- All seven: 4.2 / 7.6 / 15.0 lane-days (low / likely / high).

**Why not now.** The owner, 2026-10-12: deferred, and recorded here.

**What would reopen it.** Per-module products in use, with a family's bytes
mattering to a user. If it is taken up, do the plain carves first.

---

## Run time

### Computed constants for globals read across modules

**What it is.** Since the module split, a `static let` read from another
module is a call to its addressor rather than an inlined load: 1,064
addressor call sites in a release `Stress` against 672 before the split
(+392), one call and return more per read (static counts, decisions A-SPH2-1).
Writing the per-row ones as `@inlinable static var` constants (the alignment
defaults, `ANSIRenderer.reset`, `CursorTimer.standardFrameSeconds`) would
inline them into the reader again.

**Why not now.** The owner, 2026-10-12: keep the addressor. No row path
found is dominated by these calls, and for the public ones (`VerticalAlignment
.center` and its kin) a computed property is a declaration-kind deviation from
SwiftUI's `static let`, with a parity-map entry per constant.
`LocalizationService.shared`'s 157 sites are a different question: they go
with replacing the singleton.

**What would reopen it.** A profile showing an addressor call costing real
time on a hot path. Decided in
[A-SPH2-1](<SwiftUI parity/Decisions/Module split/Cost recovery, inlinable audit and package storage (SPH2).md#a-sph2-1-a-static-let-read-from-another-module-calls-its-addressor--decided-keep-the-addressor>).

### Typed feature-object keys

**What it is.** The navigation coordinator, the dialog suppression toggle,
the search objects and the notification service live in `AnyObject?`
environment slots, and each read pays an `as?`
(`swift_dynamicCastClass`): 10 sites in TUIkitNavigation, one of them per
`NavigationLink` row. `unsafeDowncast` would be sound only if the slot's type
were guaranteed by construction, and today it is a convention: the slot
subscript is `package`, so any module of the package can write any object into
any slot.

A design that would make it provable: a `FeatureObjectKey` protocol with an
associated `Object` type, written and read only through one generic subscript
into storage private to one file, keyed by the key type's `ObjectIdentifier`.
A type conforms to a protocol at most once, so the stored object's type is a
function of the key, and the downcast is sound. It is sketched in the session
notes, `MISC12/notes.md` §4.3; not built.

**Why not now.** The owner, 2026-10-12: keep the `as?`; `unsafeDowncast` only
where the cast is guaranteed by construction. The typed design needs storage
of its own in `EnvironmentValues`, which rides in every `RenderContext`: as a
stored property it adds 8 bytes and a retain and release to every copy (an
`Int` on `RenderContext` once measured +2.4%); nested in the existing storage
it trades the cast for another cast and a hash lookup. Its saving is
unmeasured and could be negative.

**What would reopen it.** `swift_dynamicCastClass` showing on a row path in a
profile. Decided in
[A-SPH2-2](<SwiftUI parity/Decisions/Module split/Cost recovery, inlinable audit and package storage (SPH2).md#a-sph2-2-a-feature-object-slot-costs-a-cast-on-every-read--decided-the-cast-stays>).

---

## Tests and type checking

### Exit tests' bodies as functions

**What it is.** Swift Testing type-checks an exit test's closure twice, once
where it is written and once in the function its macro generates. Moving the
body out of the closure halves that. The smaller of the two rewrites keeps the
body in the test as a local `@Sendable @MainActor func inChild() async { … }`
passed as `performing: inChild`; it ran correctly on Swift 6.2.4, 6.3.3 and
6.4.0, and cannot take a capture list, which no TUIkit exit test uses.

**What it buys (measured,** session notes `EXITTC/research.md` §8.1): about
2 s of a ~700 s whole-module type check of the test target (≈0.2%), across
what are now 43 exit tests in 23 files. Lane TC1's first figure, −7 to −10 s,
overstated it at least 3.5 times.

**Why not now.** The body is what the child process checks; moved out, the
test reads only `#expect(processExitsWith: .success) { … inChild … }`. The
recommendation, (c) leave them, stands, and the question is still the owner's:
[A-TC1-1](<SwiftUI parity/Decisions/Compile time and binary size/Type-check time (TC1).md#a-tc1-1-exit-tests-bodies-could-move-into-helper-functions>).

**What would reopen it.** Exit tests growing to a visible share of the test
build.

### The rest of the test targets' `#expect` floor

**What it is.** In the umbrella test targets an `#expect` costs more to
type-check than in the per-module targets (8.2 against 5.4 ms in debug batch
jobs when lane TC1 measured it), partly from the umbrella import and
`@testable`, partly from the target's own `==` overloads. Two fuller options
were priced in
[B-TC1-1](<SwiftUI parity/Decisions/Compile time and binary size/Type-check time (TC1).md#b-tc1-1-tuikittests-expect-floor-only-the-outliers-were-rewritten>):
rewrite every `#expect` over 20 ms (4,100 lines, 123 s of whole-module type
checking, 48 s of batch CPU), or move tests into module-only targets that
import nothing else.

**Where it stands.** The second option was taken: lane TESTSPLIT (9df2c1c1a,
2026-10-14) moved every test into a target of the module it tests, importing
that module and its dependencies only
([A-TS-1](<SwiftUI parity/Decisions/Compile time and binary size/Test targets split by module (TS).md>)),
after lane TT2 (b377b5f24, 2026-10-10) had split the umbrella suite by area.
What is left of this floor is the one target that still imports the umbrella,
`TUIkitIntegrationTests` (164 files, by design: its tests cross modules). Its
size there is unmeasured.

**What would reopen it.** A per-`#expect` measurement of the integration
target (one whole-module type check with `-debug-time-expression-type-checking`)
showing the floor matters there; the remedy would then be the first option,
rewriting its outliers.

---

## Features

### Tooltip placement rules 4 and 5

**What it is.** `Tooltips and help in a terminal.md` §5's popover rules 4 (prefer a placement not
under the pointer) and 5 (re-wrap to a narrower box before rejecting a
placement). The third part this entry used to carry, panels under
`.tooltips(.always)` that avoid one another, was built on 2026-10-12 (§5, "Many
panels at once"): they are placed as a set at the screen root, in reading
order, and one with no room is left out rather than drawn over another.

**Why not now.** Unbuilt since the tooltips shipped (2026-09-09): a single
panel takes the placement the shared overlay rule gives it. Rule 5 needs the
TEXT where the placement is decided, and a panel reaches the screen root
drawn; rule 4 needs the pointer there.

**What would reopen it.** A panel seen in the way of the pointer in use, or a
panel left out under `.always` that a narrower wrap would have kept.

### Handing the mouse to the terminal (A13.2)

**What it is.** One key that turns mouse reporting off (and alternate-scroll
mode on, so the wheel still scrolls), so the terminal's own selection and copy
work in any host, over ssh too; Escape or the same key gives the mouse back.
It is design D0 of
[the text-editing study](<SwiftUI parity/Design studies/Text selection and editing design study, A13, A42 and A43 (2026-10-04).md#d0--hand-the-mouse-to-the-terminal>),
about half a day.

**Why not now.** Deferred by the owner, 2026-10-05, with no default key: every
candidate was declined. ⌃] is the partner of ⌃[; ⌃\\ is the shell's quit, kept
as the backup to ⌃C; ⌥M types µ; ⎋ M would make Escape wait; the F-keys are
prime and do not arrive reliably where the OS takes them; and ⌃^ is too
obscure (Apple Terminal sends nothing for ⌃6, and `^^` for ⌃⇧6). TUIkit's own
selection (A13, shipped 2026-10-05) covers what is drawn.

**What would reopen it.** A key the owner accepts, or a host where TUIkit's
own selection cannot reach what a user needs to copy.

### Each `Text` its own selection (A13.5)

**What it is.** Selection that follows one `Text`'s characters, wrapped lines
and all, rather than the rectangle or run of cells TUIkit's screen selection
takes: design D2 of
[the text-editing study](<SwiftUI parity/Design studies/Text selection and editing design study, A13, A42 and A43 (2026-10-04).md#d2--each-text-its-own-selection-the-fuller-version>).

**Why not now.** The owner, 2026-10-04: remember the idea, do not build it
now. The screen selection (D1) shipped, and editable text keeps its own
keyboard selection.

**What would reopen it.** A port whose users select across a wrapped `Text`
beside other content, where the screen selection picks up the neighbours.

## Input

### SGR-Pixels mouse reports (mode 1016)

**What it is.** xterm's mode 1016 reports the pointer in pixels instead of
cells. iTerm2, Ghostty, kitty, foot and WezTerm implement it (session notes
`SCROLLX/notes.md`, 2026-10-12, from each terminal's source).

**Why not now.** It carries no scroll amount, phase or velocity, so it does not
help B27, and no TUIkit feature needs sub-cell positions today. Its hazards:
1006 and 1016 are one setting, the last one set wins, and TUIkit re-sends
`?1006h` on every tracking-mode change, which would silently drop a 1016
session back to cells; teardown would need `?1016l`; and iTerm2 reports 1016
positions in points but its 2048 sizes in device pixels (2x apart on Retina),
so the cell size must come from `OSC 1337 ReportCellSize` there.

**What would reopen it.** A feature that needs sub-cell pointer positions
(pixel-precise drags over images, a canvas), or an upstream pointer-events
protocol with scroll deltas: kitty's maintainer called one "the proper
solution" on 2026-07-21 (kitty #10273), "someday".

