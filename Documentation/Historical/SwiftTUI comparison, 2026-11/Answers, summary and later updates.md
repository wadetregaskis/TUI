# Intro

These are the answers to your 37 questions on the TUI and SwiftTUI comparison, written so they stand alone. **SwiftTUI** is `github.com/SwiftTUI/swift-tui` (swifttui.sh), at `207913d`, just after its 0.20.0 release. **TUI** is this project. "ST:" before a path means that repo's root.

**The headline.** I built and ran both. My first report expected SwiftTUI's retained engine to scale better. Measured, it doesn't: TUI is 5 to 100 times faster per interaction, and uses much less memory, in most of what I tried. SwiftTUI wins in four places: slow bodies whose inputs didn't change, compositing many blended layers, output bytes while scrolling, and idle with a focused control. The first is the one TUI should fix. See question 14.

**What I'd do first, of what these answers turned up.** Effort is rough.

| Item | Why | Effort | Question |
|---|---|---:|---|
| Stop re-running plain bodies whose inputs didn't change, and stop running them twice a frame | TUI's one clear engine weakness: 216 ms against 28 ms | M to L | 14 |
| `NO_COLOR` and a "still" switch that really stops all animation | `NO_COLOR` is the convention, and isn't read for a running app | days | 1 |
| The real cursor at a text field's caret, and cursor-follows-focus | The cheapest accessibility gain there is | 2 to 4 days | 25 |
| Arrow keys that move by screen position | Visible in any 2D layout | 2 to 3 days | 22 |
| `_printChanges` and `_logChanges` | Real SwiftUI API, missing here | 3 to 5 days | 34 |
| Author-facing performance page | Nothing tells an author what to do | days | 32 |
| Count ratchets on unsafe concurrency, sleeps in tests and work per scenario | They hold the gains cheaply | days | 16, 31 |

**Decisions these raise for you**, none blocking:
- Focus pulse at idle: 1.75% CPU and 1 to 2 KB/s forever, and `TUI_REDUCE_MOTION` doesn't stop it (question 14).
- `Canvas`, the command palette, `DocumentGroup` and hot reload: each is doable, and each is your call on whether it's wanted (questions 8, 7, 10, 4).

**How far to trust each statement.** Each claim carries a mark.

| Mark | Meaning |
|---|---|
| [V] | Read in source this session |
| [M] or [R] | Measured, or built and run, this session |
| [D] or [S] | The project's own docs say so; not checked further |
| [T] | A third party says so, from the web; not checked |
| [I] | My inference or judgement |

Timings come from one shared VM, so treat them as rough. Allocation counts and bytes repeat well. Effort figures are my estimates throughout.

## 13. What the 8 test programs revealed

**Answer.** Yes. I wrote eight ordinary SwiftUI programs, swapped `import SwiftUI` for `import TUI`, and compiled them. They found two real API gaps and one real usability problem, all fixed. Most of the remaining errors are decisions you've already made.

The programs are not TUI's own. They were written earlier as a survey of typical SwiftUI, and they're the closest thing here to "what will a newcomer paste in?". Results against current TUI, typecheck only, on 2026-11-01 [M]:

| Program | Errors | Seconds | What they are |
|---|---:|---:|---|
| Todo | 0 | 1 | |
| TabsAndSheets | 0 | 1 | |
| Browser | 1 | 1 | `ShareLink`: deliberate. Was 2; see below |
| SortedTable | 1 | 2 | `.inset(alternatesRowBackgrounds:)`: soft-deprecated, and the error says what to write. Was a compiler give-up at 35 s |
| SettingsForm | 2 | 0 | `defaultSize`, `windowResizability`: deliberate, one surface |
| DocumentFlow | 4 | 1 | `DocumentGroup` and `onOpenURL`: deliberate. `@Entry` needs `import TUIMacros`, which is opt-in so nobody builds swift-syntax unasked |
| AnimationGestures | 6 | 2 | `scaleEffect` and integer geometry: deliberate. Was a compiler give-up at 18 s |
| CustomStyles | 18 | 1 | Mostly `CGFloat` in a custom `Layout`, plus `scaleEffect` and `@Entry` |

**Gaps that weren't deliberate, both fixed:**
| Gap | State |
|---|---|
| `List(data, selection:)` with a selection that isn't the element's id | **Fixed**, `59e4b8ae0` |
| A custom `Layout`'s geometry types didn't fit together | **Fixed**, `745064203`. `CGFloat` geometry itself stays a recorded deviation, so `FlowLayout` here still needs `Int`s |

**A usability problem, now fixed: the compiler giving up.** SortedTable's `Table` body and AnimationGestures' `RotatingBadge` both hit "unable to type-check this expression in reasonable time" at `var body`, after 35 and 18 seconds, with no hint of which line [M]. One unsupported modifier in a long chain sent the type checker through everything it could have meant. `RotatingBadge`, for instance, uses `.background(Capsule().fill(.purple))`: SwiftUI has soft-deprecated that form, so it warns nobody and plenty of real code uses it. Under your earlier ruling, TUI doesn't implement deprecated SwiftUI API.

The stubs you approved fixed it, and they've landed. An `@available(*, unavailable, message:)` declaration ends the search at once and says what to write instead. Both programs now finish in 2 seconds with errors like `'background(_:alignment:)' is unavailable: Put the view in a closure: .background(alignment: .center) { ... }` [M].

**For scale, a count I ran for this.** SwiftUI has 127 soft-deprecated declarations that TUI lacks and that the parity map doesn't explain [M]. `NavigationView`, `Alert`, `.accentColor`, `\.presentationMode` and `Section(header:)` are among them. Your ruling covers all of these, and they aren't counted as gaps. Their importance is that old code and tutorials use them freely, which is why stubs matter more than the parity numbers suggest.

**What this doesn't show.** It's compile only: whether each program then behaves is a separate question, covered by `Tools/SwiftUIProbes` and the compile corpus for the areas they reach. Eight programs are also a small sample, so more gaps may exist.

## 26. The 16-colour claim

**Answer.** You were right, and my report was wrong. TUI has real 16-colour support. `ColorDepth` has an `.ansi16` level, `.ansi` colours follow the user's own palette slot for slot, and the downsampling path maps truecolour and 256-colour values down to 16 through the `palette256ToANSI16` table [V]. My report implied SwiftTUI had something TUI lacked here, and it didn't. I corrected the report when you raised it.

Question 27 compares the two frameworks' colour handling in general.

## 16. Unchecked Sendable and nonisolated(unsafe)

**Answer, now done.** We do have them, and most are gone. They went from about 147 `@unchecked Sendable` and 74 `nonisolated(unsafe)` lines, comments included, to **8 and 4** declarations, each with its reason at the site [M]. It landed with the macOS 15 floor. A lint rule, `concurrency_escape`, now fails any new one that doesn't carry an explicit exception, so `git grep "disable:this concurrency_escape" Sources` is the complete list.

**Why these twelve stay, by reason:**

| Reason | Count | Example | What was tried, and why it doesn't work |
|---|---:|---|---|
| SwiftUI's own signature takes an unconstrained type, and the value has to cross a `Sendable` boundary | 6 | `TextAttributes` (`Text+CustomAttribute.swift:31`). `Text` must be `Sendable`, but SwiftUI's `TextAttribute` is only `Hashable`. The others: `TransactionExtras`, `PublishedEnvironment`, `FormattedTimeSource`, `StoredValue`, `HandedItem` | `Mutex` won't hand a non-`Sendable` value out. A `Sendable` constraint breaks SwiftUI source that compiles today. `Disconnected` (SE-0538) isn't in Swift 6.4.0 |
| An Apple class its SDK marks not `Sendable`, though thread-safe | 2 | `UserDefaultsStorage` holds a `let defaults: UserDefaults`, thread-safe by Apple's docs. The other is `_DecodedImage`'s `NSImage` owner | A `Mutex` would hold its lock across KVO observers that may read this store, and re-entering a `Mutex` kills the process. Isolating the owner needs `@MainActor` inits |
| Raw memory a signal handler reads | 3 | `savedTermios` (`FatalSignalTerminalRestore.swift:257`). A signal handler can't take a lock and gets no context | `Atomic<UnsafeMutablePointer<T>>` doesn't compile, a pointer not being `Sendable`. An address stored as an integer only hides the same thing. Every count and flag here did become atomic |
| Confined to the walking thread by a runtime check | 1 | `BindingReads.noted` (`FrameObservation.swift:132`). `Binding.wrappedValue` is nonisolated, as SwiftUI's is, and it notes a non-`Sendable` getter | `Mutex` won't take it, and `assumeIsolated` can't be handed it. Moving the note into each core risks silently missing one |

**What the floor gave.** macOS 15 carries Swift 6.0's runtime. Adopted: `Mutex`, `Atomic`, `String(validating:)`, five more `UTType`s for Linux, and every dead macOS 15 availability gate deleted (39 attributes plus the `#available`s). Not unlocked, though it's easy to assume otherwise: `Array.span`, `InlineArray`, `Observations` and `Task.immediate` stay macOS 26, and `libswiftCompatibilitySpan` stays. The full survey, feature by feature with its evidence, is in `Documentation/Working notes/floor-macos15.md`.

**Things that changed as a result:**
- **Hot paths.** Swift 6 checks the executor on any closure a main-actor function hands to the standard library, about 100 ns against about 3 ns for a `Mutex` [M, under load, so order of magnitude only]. So render-path classes became not `Sendable`, rather than `@MainActor`. SwiftUI's own `EnvironmentValues` isn't `Sendable` either, which is what allowed this.
- **Locks removed.** `StateBox`'s stamp locks, and those in `LifecycleManager` and `ObjectHub`. A non-`Sendable` value can't compile its way to another thread.
- **A sharper failure.** Re-entering a `Mutex` on macOS is an uncatchable kill, where re-entering `NSLock` hung [M]. So each lock that calls out was read before it moved.

**Small parity changes for you to judge,** all in the CHANGELOG:
- `GestureState` is no longer `Sendable`; SwiftUI's is `@unchecked` when its value is.
- `withAnimation` with a completion held in a variable needs `{ done() }` in Swift 6 mode, because `@preconcurrency` beside an `isolated` parameter trips a compiler assertion on 6.2.4.
- A `static let` toolbar placement must become `static var`, as under SwiftUI in Swift 6.

**Not yet shown.** Windows has no local lane, and the lower modules now import `Synchronization`, so that CI lane is the first real test. There's no quiet-box A/B yet either; I expect a small gain, and I'll run one.

**How it looked before, and how SwiftTUI compares:**

## 1. Turning off render features (colour, motion)

**Update: the colour conventions are done, after your reply.** TUI now honours `NO_COLOR`, `FORCE_COLOR`, `CLICOLOR_FORCE` and `CLICOLOR` for a running app and for `renderOnce`, in that order of precedence, through one shared reading in `ColorRequest.swift`. An empty variable counts as unset, and bold, underline and italic stay. TUI still parses no arguments: an app that takes `--color=always` assigns `ColorDepth.current`, which outranks the environment.

**The conventions disagree in places, so these were choices:**

| Conflict | Chosen | Agrees with | Disagrees with |
|---|---|---|---|
| `NO_COLOR` and `FORCE_COLOR` both set | no colour | clicolors, Python | Node, force-color.org's example order |
| `FORCE_COLOR=0` or `false` | off | Node, supports-color | force-color.org, Python |
| `FORCE_COLOR` digits | that exact level, capped at 3 | supports-color; Node for 1 to 3 | Node turns `4` off |
| `CLICOLOR=0` | off | clicolors text until June 2023, Rust's `anstyle-query` | current clicolors text |

**One for you:** `FORCE_COLOR=1` on a truecolor terminal lowers it to 16 colours, because I took it as an exact level. If you'd rather it were a floor, that's a small change.

**Turning colour off found more than I expected.** Focus was invisible on prominent buttons, links, toggles, radios, steppers, sliders, tabs and menus. Disabled was invisible on nearly every control. So were a text field's caret and selection, and a scroll bar's thumb. All are fixed, using reverse video, faint text and glyphs, with tests comparing what a terminal would paint. Focus breathing also stops costing anything without colour: 0 bytes/s and 0.0% CPU, against 443 bytes/s and 0.6%, in one run on a debug build.

**Known limits.** Faint text is measured on Apple Terminal only, and on a terminal that ignores it most disabled controls will look enabled. A custom `ButtonStyle` or `ToggleStyle` isn't reversed for focus.

**Still open from your reply.** The mode that replaces chrome is a plain-chrome mode, not ASCII-only, as you spotted, and it isn't built. "Still" isn't built yet either. Everything below is the original answer, so some of its "not read" statements about colour are out of date.
