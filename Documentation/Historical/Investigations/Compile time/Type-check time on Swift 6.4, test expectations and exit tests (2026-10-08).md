# Type-check time on Swift 6.4, test expectations and exit tests (2026-10-08)

> **Status:** decided; the test rewrites landed 2026-10-08, and the test-target split that followed on 2026-10-10.
> Two items stay open elsewhere: exit tests' bodies (decisions A-TC1-1, the owner's) and the `#expect` scaling
> report, drafted for the owner to file. **Decided by:** the owner set the target and the rule (6.4 first, no
> regression on 6.2 or 6.3); lanes TC1 and TC2 chose the rewrites by it. **Working notes** (not in git): `TC1/`
> (the 6.2.4 profile), `TC2/` (6.4 against 6.2.4: `profile.md`, `baseline.md`), `EXITTC/` (`research.md`, and
> `expect-scaling/` with the report and its reproducer), `buildtime/typecheck/`.

## Question

The owner asked on 2026-10-07 for TUIkit's clean release compile time to come down, starting with the simple fixes
a type-check profile finds (lane TC1, on Xcode's 6.2.4). On 2026-10-08 he moved the target: "our main focus for
improving the compile time … should be the 6.4 compiler. We still need 6.3 and 6.2 to work … We know that 6.4 is in
some ways slower than 6.2, so it might be worth rerunning an evaluation there." He also asked whether the exit-test
double type-check is reported, fixed, avoidable by a flag, and still in 6.4.

## Answer

- **6.4 type-checks TUIkit faster than 6.2.4, not slower:** function bodies in the nine carved library modules −13%,
  in TUIkitFoundation −17%, in the test targets −2%. One test target was slower (TUIkitViewTests, +15%), and
  TUIkitTests' whole-module type check peaked at 5.6 GB of memory on 6.4 against 3.3 GB (+72%).
- **What is slower on 6.4 is specific:** the first use of an overload set in each frontend (5–14 ms against 2–6 ms,
  paid once per batch job); a leading-dot operand of `==` inside `#expect` (`== .rgb(…)`: +67% on the 159 lines that
  had one), since it is inferred through every `==` in scope; and a per-`#expect` floor about 10% higher.
- **The library had nothing left to fix on 6.4;** every candidate rewrite saved under 5 ms and was reverted. In the
  test targets, four rewrites saved 1.65 s on 6.4, 1.03 s on 6.3.3 and 1.02 s on 6.2.4, slower on no compiler.
- **The cost of an `#expect` grows with how many a module holds:** linear up to about 8,000, then 2.3 to 2.5 times
  the CPU for twice the expectations. It follows the number of `#expect` expansions, not suites or tests. TUIkitTests
  held about 25,000. That made splitting the test targets worth doing.
- **The exit-test double type-check is by design and has no flag.** SE-0382 type-checks a macro's arguments before
  expansion, and the exit-test macro then copies the body into a function the compiler checks again. Nobody had
  reported it; it is still there in 6.4.0; in TUIkit it costs about 2 s of a whole-module check (≈0.2%), not the
  7–10 s lane TC1 first estimated.

## Key measurements

Swift 6.4.0 and 6.3.3 (swift.org, no assertions) and Xcode 26.3's 6.2.4, on the development machine (arm64 macOS
15.8.1 VM, shared with other lanes, so absolute times are noisy: rankings, same-session pairs and minimum-of-N runs
were trusted). Base c25452779 (part-way through the module split). Function bodies with
`-debug-time-function-bodies`, expressions with `-debug-time-expression-type-checking`, per file as primary (min of 3
or 5) and per module whole (`-typecheck`).

| | Xcode's 6.2.4 | 6.4.0 |
|---|--:|--:|
| carved library modules, function bodies | 4,538 ms | 3,957 ms |
| TUIkitFoundation, function bodies | 7,608 ms | 6,323 ms |
| test targets, whole-module | 770 s | 752 s |
| TUIkitTests, peak memory | 3.3 GB | 5.6 GB |
| trivial `#expect`, TUIkitTests | 4.93–6.24 ms | 5.18–6.77 ms |

`#expect` scaling, a generated package (20 trivial `#expect`s per test), 6.4.0, test target rebuild CPU:

| `#expect`s | 1,000 | 2,000 | 4,000 | 8,000 | 16,000 |
|---|--:|--:|--:|--:|--:|
| debug | 5.9 s | 12.3 s | 24.5 s | 50.2 s | 117.8 s |
| release (whole-module) | 7.1 s | 14.0 s | 29.3 s | 68.6–76.9 s | 192.7 s |

With one `#expect` per test, the same suites and tests stay linear (7.2 s and 14.3 s); without `@Suite` the curve
barely changes. 6.2.4 and 6.3.3 show the same shape (8,000 to 16,000: 2.2× and 3.0×, `swiftc -typecheck -wmo`).

## Reasoning

- **Rewrites only where they pay on 6.4 and do not cost on 6.2 or 6.3**, measured per file on all three: the row-fill
  goldens built by appends (`f6ce6fc20`), named values in the worst `#expect`s of nine files (`2aceec998`), colour
  operands that name `Color` (`7e19ae3d2`), and two named verdicts (`1f883cc53`). TC1's 6.2.4 rewrites came first
  (`f0be9f936` and others; decisions TC1).
- **A first-use cost is not a property of its site:** rewriting one moves the cost to the next first use, as a
  warm-up probe showed (sites dropped from 5–14 ms to 0.3–2 ms when another file paid first). So no library code was
  changed for it.
- **The split test targets** (`b377b5f24`, decisions TT2) took a one-file test edit from about 60 to about 18 CPU
  seconds; that, and the rest of the `#expect` floor, are in
  [Future options](<../../../Future options.md#the-rest-of-the-test-targets-expect-floor>).
- **Exit tests:** moving each body into a function halves the check, and a local `func inChild()` passed as
  `performing:` is the smallest such rewrite. For about 2 s it would hide what the child process checks, so the
  recommendation is to leave them
  ([A-TC1-1](<../../../SwiftUI parity/Decisions/Compile time and binary size/Type-check time (TC1).md#a-tc1-1-exit-tests-bodies-could-move-into-helper-functions>),
  [Future options](<../../../Future options.md#exit-tests-bodies-as-functions>)).

## The modules carved after it (2026-10-19)

The owner asked for a per-module pass once the split had a first solid draft. This record's profile predates
thirteen modules: Chrome, Effects, Menus, Bitmaps, Lists, TextInput, Tables, Tabs, Grid, Forms, Search, Pickers and
NumericControls. They were profiled on swift.org 6.4.0, in a debug build of the library (a fresh scratch path) with
`-warn-long-expression-type-checking=5` and `-warn-long-function-bodies=5`. That reported 152 expressions and 436
function bodies of 5 ms or more in those modules, on a busy machine. Each candidate was then re-measured by touching
its file and rebuilding its module three times, keeping the minimum. The two kinds this record describes account for
the rest:

- **First use.** `_SidebarSectionList.body`'s `List(selection:) { … }`, the worst expression (48 ms of a 66 ms
  body), stayed at 48–49 ms with the section moved to a method of its own, and again with the whole content moved to
  a builder method. A trivial `List(selection:) { EmptyView() }` placed before it took the 48 ms, and the real call
  dropped under 5 ms: the cost belongs to the first use of `List`'s initializers in that frontend, not to the site.
  The next worst (`List+BindingTree.swift:33`, `Table+Children.swift:53`, `Table+Customization.swift:32`,
  `List+RequiredSelection.swift:36`, 25–34 ms) have the same shape: one `self.init` into an overloaded set.
- **Bodies of many cheap expressions.** `TrackRaster.picture` (26 ms, min of 3) has no expression over 6 ms. The
  two `==` bodies on the list (`ProgressView`, 14 ms; the image placeholder's, 11 ms) are guard lists already, the
  form this record's fixes used; what they pay is the first use of `==`.

One site was a real one: `PanelToggleButton.name` trimmed a label as
`String(line.drop { … }.reversed().drop { … }.reversed())`, 11 ms. Found by index, its body went from 16 to 11 ms;
the 5 ms left is the first use of `String.init`. Nothing else qualified, which is this record's finding for the
first nine modules too.

## Side findings

- Swift 6.3.3 could not build TUIkit in release (`Theme.swift:198`, a false data-race error): its `-O` pipeline
  clones a nested function without its main-actor isolation. Fixed in `fed3b535e`, whose message holds the
  reduction; CI has built release on 6.3 and 6.4 since `87139596a`.
- The release build's whole Sema phase is longer on 6.4 (TUIkitFoundation's job 9.1 s against 6.7 s), outside
  function bodies; where is unmeasured.

Related: the [compile time and binary size analysis](<../../Compile time and binary size analysis (2026-10-07).md>)
(on 6.2) and decisions
[TC1](<../../../SwiftUI parity/Decisions/Compile time and binary size/Type-check time (TC1).md>) and
[TT2](<../../../SwiftUI parity/Decisions/Compile time and binary size/Test targets split by area (TT2).md>).
