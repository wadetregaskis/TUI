# Building views off the main actor

*Whether a view could be built outside the main actor, and how flexible a
handler's isolation should be: the study of 2026-10-31 (with its addendum of
2026-11-01), the owner's rulings, and what landed. Id: MAINACTOR.*

## In short

A view value is plain nonisolated data since 2026-11-01, as in SwiftUI: free
functions, enum helpers, models, actors and detached tasks can build views,
while `body` and the render loop stay on the main actor. `Button`'s action is
`@MainActor`, SwiftUI's own type for it, with a disfavoured plain overload in
place of SwiftUI's `@preconcurrency`. The study's step past SwiftUI, async
`@isolated(any)` overloads and per-button press policies, was declined by the
owner.

## The problem

`View`, its initialisers, every modifier and `ViewBuilder` inherited
`@MainActor`, so a view built in a free function, an enum or a detached task
did not compile, where SwiftUI's modifiers are `nonisolated` and `Text` is
`Sendable`. On 2026-10-31 the owner asked for it fixed, "better than
SwiftUI": research the flexible-isolation options in Swift 6.2, 6.3 and 6.4,
with a raise of the minimum Swift open if the benefit was significant.

## How it unfolded

1. **2026-10-31, the study** (the record below): every candidate feature
   tried on three compilers, designs A (SwiftUI parity), B (A plus flexible
   async overloads, recommended), C (one `@isolated(any)` signature, rejected)
   and P (B with `@preconcurrency` on `View`) prototyped. No Swift bump
   needed.
2. **2026-11-01, the owner** asked to avoid `@preconcurrency`, and whether an
   async action blocks rendering and how re-entrancy is handled (the
   addendum, which proposed per-button press policies).
3. **The owner's ruling, the same weekend:** no async overloads or policies;
   no `@preconcurrency`; the floor may rise to macOS 15 (raised 2026-10-31,
   [its story](<Raising the floor to macOS 15.md>)). No reason was recorded
   for declining the overloads and policies.
4. **2026-11-01, built:** view values and modifiers nonisolated
   (`20dc95860`, scripted); `Button`'s action `@MainActor` with a plain
   disfavoured overload (`cc23e33d9`); `Text`, `Spacer` and `EmptyView`
   `Sendable` (`6414905ee`); the literal `Text` table behind a mutex
   (`4979b70cb`); tests (`83bace46b`); and the articles on building views
   anywhere and running async work from a handler (`443c8bb49`).

## Where it stands

Design A without `@preconcurrency` is shipped. Design B's overloads and the
press policies are declined.

## For a future reader

- **Why the plain overload instead of `@preconcurrency`** (`cc23e33d9`):
  region isolation makes the unsafe shapes hard errors, where
  `@preconcurrency` turns real races into warnings. The cost is that a
  `String` title with a plain closure value no longer compiles; a plain
  overload for that shape would silently take a literal title as text rather
  than a localization key.
- **Swift 6 checks the executor on entry** to a closure a main-actor function
  hands to the standard library or `Synchronization` (about 100 ns against
  3 ns), which is why render-path classes are not `Sendable` rather than
  `@MainActor` (see [Raising the floor to macOS 15](<Raising the floor to macOS 15.md>)).
- **The study's paths into the scratchpad** no longer exist; its prototype
  and probes were not kept.

## The record

### The study, 2026-10-31

Study, 2026-10-31. Measured on macOS 15.8 (arm64), Swift 6 mode, with swiftly's 6.2.4, 6.3.3 and 6.4.0 and Xcode's 6.2.4.
Anything I did not run is marked **unverified**. Prototype, probes and logs (the scratchpad is not durable; copy it to keep it):
`/private/tmp/claude-501/-Users-robot-Documents-TUIkit/495bcd3a-b74f-4749-86b4-0c15ad58a905/scratchpad/isolation`

#### The short answer

**Your hunch is right, and TUI already does it in one place.** The feature is `@isolated(any)` (SE-0431, Swift 6.0): a function value that carries its own isolation, so whoever holds it can start it in the right place. `.task` already uses it (`View+Events.swift:403`), which is why TUI's `.task` is more flexible than SwiftUI's.

**But it cannot be the whole answer, because it only works with `await`.** On all three compilers there is no way to call an `@isolated(any)` closure synchronously, even inside `assumeIsolated` on its own isolation. A `Button` built on it alone makes every press a task hop, and code that compiles on SwiftUI stops compiling. So the best design uses each tool where it fits:

1. **Building a view stops needing the main actor.** View values become plain nonisolated data, as in SwiftUI. Free functions, enum helpers, models, actors and detached tasks can build them. `body` and the render loop stay on the main actor. No hop and no allocation are added per view.
2. **Ordinary handlers take `@preconcurrency @MainActor` closures**, SwiftUI's own type for `Button`. They still run synchronously and inline. This is parity and a little better: a handler written in a free function may touch main-actor state, which SwiftUI's `onChange` refuses.
3. **The flexible part is a second overload taking an async `@isolated(any)` closure.** `Button("Save") { await model.save() }` is accepted anywhere, and TUI starts it on the isolation the closure carries. `{ @Database in … }` works too, and `Button("x", on: actor) { actor in … }` runs synchronously on a named actor. All additive, none of it on the render path. SwiftUI has none of these.

**No Swift bump is needed**, on any of this (section 7). The migration is large but mostly a script: I ran it on a copy of the whole framework, and `Example` compiled with its source untouched (section 6).

#### 1. What is wrong today

`View` is `@MainActor` (`Sources/TUIView/Core/View.swift:58`). A struct listing `View` in its declaration inherits that, so do
its initialisers, and so do the modifiers in `extension View`. `ViewBuilder` is `@MainActor` too (`ViewBuilder.swift:29`).

SwiftUI's protocol is the same: `@preconcurrency @MainActor public protocol View`, with `body` isolated. The difference is the
rest (macOS 15.5 SDK interfaces):

- **Modifiers:** `nonisolated public func`, about 261 against 48 `@MainActor` in SwiftUICore by grep. **`ViewBuilder`:** no isolation.
- **`Text`:** `public struct Text: Equatable, Sendable`, with `View` conformance in an extension.
- **`Button`:** `@preconcurrency nonisolated public init(_:action: @escaping @MainActor () -> Void)`. **`onChange`, `onAppear`:** a plain `() -> Void`.
- **`Binding(get:set:)`:** `@_inheritActorContext get: @escaping @isolated(any) @Sendable () -> Value`, so Apple uses it too.

#### 2. Every candidate, tried

Compile results are from all three compilers unless marked.

| Feature | What it would do here | Verdict |
|---|---|---|
| `nonisolated` on types, extensions, inits (SE-0449, 6.1) | A view is data anyone may build | **Yes: the core of the fix** |
| `@isolated(any)` (SE-0431, 6.0) | A closure carries its isolation, in 16 bytes like a plain one | **Yes, for async closures only.** A sync call fails with `call to @isolated(any) parameter 'f' in a synchronous … context`, also inside `assumeIsolated` and with an `isolated` parameter. It cannot differ from a `@MainActor` overload by isolation alone (`invalid redeclaration`). As a generic argument it needs the macOS 15 runtime (TUI's floor is 14) |
| `@MainActor` closure parameter + `@preconcurrency` | A literal is main-actor isolated wherever it is written | **Yes: SwiftUI's `Button`.** Without `@preconcurrency`, `Button("x", action: plainClosure)` is a hard error |
| `@_inheritActorContext`, and `(always)` | Closure takes the caller's isolation | **Yes, as `.task` has it.** Documented as doing nothing for a sync closure; warns on a non-`Sendable`, non-`sending` parameter. `(always)` compiles on all; not needed so far |
| `sending` (SE-0430, 6.0) | Hand over a non-`Sendable` value | At the edges. `-> sending VStack<Text>` compiles on all; `-> sending some View` only on **6.4.0** |
| `nonisolated(nonsending)`, `@concurrent` (SE-0461, 6.2); `isolated deinit` (SE-0371); `assumeIsolated` | Where async code runs; a deinit's isolation; claiming the main actor | Not relevant to building: sync functions are unaffected; a deinit is unrelated; `assumeIsolated` crashes off the main actor. Inside TUI already, no fix |
| `#isolation`, `isolated` params (SE-0420, 6.0); successor to `@_unsafeInheritExecutor` | A function runs on its caller's isolation | A sync nonisolated function already does. Its use here is `(isolated A) -> Void`, the `on:` overload |
| Isolated conformances (SE-0470) | `struct Row: @MainActor View` | **No.** From a free function: `main actor-isolated conformance … cannot be used in nonisolated context`, on SwiftUI too |
| Default isolation (SE-0466, 6.2) | The app's module defaults to `@MainActor` | **Document it today.** With `-default-isolation MainActor` in the app, free functions, enum helpers and models compile on *today's* TUI. It does not help detached tasks or other actors, and it is the app's choice |
| Region isolation (SE-0414, 6.0) | Non-`Sendable` values move safely | **What makes this sound:** a view built on an actor stays in its region and cannot reach the main actor unless `Sendable` or `sending` |
| Closure isolation control (`{ [isolated vm] in }`) | Say which actor a literal runs on | **The missing piece, never accepted:** a forum pitch, absent from the Evolution index. `(isolated A) -> Void` is the substitute |
| SE-0478 file-level `default nonisolated` | One line per file | **Not in 6.4.0** (does not parse). "Swift next" in the changelog |
| SE-0538 `Disconnected` | `Sendable` box for a non-`Sendable` value | **Not in 6.4.0** (`cannot find`). Accepted only |
| `Task.immediate` (SE-0472, 6.2) | A press runs inline until its first suspension | Compiles; runtime needs **macOS 26**. Not run here: **unverified** |
| `~Sendable` (SE-0518, 6.4); SE-0506 tracking API (6.4) | Tidier "not Sendable"; cancellable tracking | Cosmetic; maybe useful to `ObservationLease`, **unverified**. Neither bears on this |

#### 3. The designs I prototyped, and what compiles

Each is a small module with `View`, `Text`, `.padding`, `VStack`, `@ViewBuilder`, `ForEach`, `Button`, `.task`, `.onChange`, `@State`:

- **Today:** everything inherits `@MainActor`.
- **A, SwiftUI parity:** `nonisolated` value types; `@MainActor` on `body` and rendering; `@preconcurrency @MainActor` handlers.
- **B, A plus flexible overloads (recommended):** `Button` and `onChange` also take `@isolated(any) @Sendable () async` closures,
  and `Button(on:)` takes `(isolated A) -> Void`. All funnel into the one stored `@MainActor () -> Void`, so the render path
  cannot tell them apart.
- **C, one signature:** `@isolated(any)` only, with an `unsafeBitCast` for the synchronous path.
- **P, B with `@preconcurrency` on `View`,** as SwiftUI's is: open question 1.

Swift 6 mode. Same on 6.2.4, 6.3.3 and 6.4.0 except where marked. "warn" compiles with a warning.

| User code | Today | A | B | C | SwiftUI |
|---|---|---|---|---|---|
| **Free function returning `some View`** (text, stack, modifier, `ForEach`) | no | **yes** | **yes** | **yes** | yes |
| **Helper on an enum** | no | **yes** | **yes** | **yes** | yes |
| Helper on a model; `let t = Text("x")` at file scope | no | yes | yes | yes | yes |
| Free function: `Button("x") { mainActorModel.inc() }` | no | yes | yes | **no** | yes |
| Free function: `.onChange(of: v) { _, _ in mainActorModel.inc() }` | no | yes | yes | no | **no** |
| **`Task.detached { Text("x") }.value`** | no | yes | yes | yes | yes |
| `Task.detached { VStack { Text("a") } }.value` (conditional `Sendable`) | no | yes | yes | yes | **no** |
| `Task.detached { VStack { … }.padding() }.value` (`some View` is not `Sendable`) | no | no | no | no | no |
| Same with `-> sending some View` | no | 6.4 | 6.4 | 6.4 | 6.4 |
| Actor method builds a `Text`, main actor awaits it | no | yes | yes | yes | yes |
| **Closure on a custom actor:** `Button("x") { await vm.inc() }`, in `body` or free | no | no | **yes** | no | no |
| In `body`: `Button("x") { s = await vm.get() }` (writes `@State`, on main) | no | no | **yes** | no | no |
| `Button("x") { @Database in count += 1 }` (global actor) | no | no | **yes** | yes | no |
| `Button("x", on: vm) { vm in vm.inc() }` (sync, on that actor) | no | no | **yes** | no | no |
| In the actor's own method: `Button("x") { await self.inc() }` | no | no | **yes** (warns `await` is redundant) | no | no |
| In the actor's own method: `Button("x") { self.n += 1 }` | no | warn, **unsafe** | warn, **unsafe** | yes | warn, **unsafe** |
| `Button("x", action: vm.inc)` (actor method reference) | no | no | no | no | no |
| `.task(vm.run)` (async actor method reference) | no | yes | yes | yes | yes |
| `.onChange(of: v) { _, _ in await vm.inc() }` | no | no | **yes** | no | no |
| Existing: `Button`, `@State`, `.task`, `.onChange` in `body` | yes | yes | yes | yes | yes |
| Existing: `Button("x", action: plainClosureVariable)` | yes | **warn** | **warn** | yes | yes |
| User's `struct Row: View` of `Sendable` lets, from a free function | yes | yes | yes | yes | yes |
| Same with a generic or non-`Sendable` field, or its own `init` | no | no | no | no | warn |
| Same, with `nonisolated init` or `nonisolated struct` written by the user | yes | yes | yes | yes | yes |
| `{ @DB in stateVar += 1 }` on a `Button` (must be refused) | refused | refused | refused | not run | refused |

- **The warning on `Button("x", action: plainClosure)`.** SwiftUI escapes it only by being compiled in Swift 5 mode: I built the
  same declaration both ways, and the warning appears only when the *defining* module is in Swift 6 mode. The fix is `{ plainClosure() }`.
- **The unsafe case.** `@preconcurrency` turns `actor-isolated property 'n' can not be mutated from the main actor` from an error
  into a warning, and the closure would run on the main actor. SwiftUI has the same hole. It is the price of accepting
  `plainClosure` at all and only arises inside a custom actor. Writing `await` picks the async overload, which is safe. (Warning
  confirmed; a race at run time not attempted.)
- **Why C loses.** It needs an `unsafeBitCast` to call synchronously, adds an allocation per button per frame (section 6), and
  refuses `Button("x") { model.inc() }` in a free function, because the closure is then nonisolated.
- **Client settings.** `NonisolatedNonsendingByDefault` plus `InferIsolatedConformances` changed no result for Today, A or B.

#### 4. Handlers and custom actors: "flexible isolation" in practice

A press in design B, with `preconditionIsolated` inside each action, which passed on all three. This is 6.4.0's output; the order of the
hops varied between compilers, as it should:

```
free function sync: ran inline on main           sync @MainActor closure: before the press returns
after press 1
after press 2                                    `await vm.check()`: the press returns first, then…
free function async: ran on VM, n=0
on: actor: ran on VM, n=1                        Button("x", on: vm) { vm in … }
global actor closure: ran on DB, count=1         { @DB in … }
body async: back on main, s=1                    { s = await vm.get() } writes @State on main
actor's own closure: isolated to VM              closure written in the actor's method
```

So the hops really are automatic, and a sync main-actor action stays as it is today. That matters: a press that always hopped
would land after the frame it caused, and key order would be up to the scheduler.

**Choosing the overload.** A sync literal takes the `@MainActor` one, a literal containing `await` takes the async one, and
`{ @DB in … }` takes the async one, from a main-actor or a nonisolated caller (run on 6.3.3 and 6.4.0). So SwiftUI code cannot
land on the new overload by accident.

A view model on a custom actor then looks like this, and the shape compiles under B:

```swift
actor Downloads { func start() { … }; func count() -> Int { … } }

struct DownloadsView: View {
    let downloads: Downloads
    @State private var count = 0
    var body: some View {
        VStack {
            Text("\(count)")
            Button("Start") { await downloads.start(); count = await downloads.count() }
        }
        .task { count = await downloads.count() }
    }
}
```

**Three limits no design here lifts:**

- **`body` cannot read an actor synchronously.** The state has to be mirrored into `@State`. `@Observable` refuses actor types
  (`'@Observable' cannot be applied to actor type`). `@Database @Observable final class` compiles, and so does
  `Observations { @Database in model.n }` behind `#available(macOS 26, *)`, but `body` still cannot read that model without `await`.
- **`Button("x", action: vm.inc)` is refused** everywhere: an actor instance's method cannot be partially applied from outside.
- **A sync closure literal cannot name an actor *instance*,** for want of closure isolation control. `await`, a global actor or `on:` can.

**A press costs** a task allocation under the async overload, not a render cost. `Task.immediate` behind `#available` would run it inline
up to the first suspension on macOS 26 and Linux: **unverified at run time**.

#### 5. `body`, the render loop and Linux

**`body` stays `@MainActor` and the render loop stays on the main actor.** SwiftUI code relies on `body` calling main-actor models, and `Sources` has 1,539 `@MainActor` mentions: the caches, the memo stores and `StackGuard`'s extent all use the actor for mutual exclusion. Every per-view hop would land on the hottest path there is.

**Linux.** The main actor is drained by a pool thread after the first suspension (`StackGuard.swift:40`), and this does not disturb that. A nonisolated sync init runs on whichever thread calls it and touches no thread-keyed state. The async overloads hop as `.task` already does; the loop releases the main actor while it waits (`App.swift:684`), and an off-main `setNeedsRender` already wakes it (`App.swift:538`). Prototype B cross-compiles for static Linux on 6.3.3. **Running it on Linux is unverified:** no container runtime here. **Windows** is unaffected: no POSIX API is added.

#### 6. Cost

##### Runtime, in the prototype

Release, cross-module, one frame of a small tree (two stacks, four `Text`, a `Button`, two paddings, a user `Row`). Allocations from
the runtime's own swizzle hook, checks are calls to `swift_task_isCurrentExecutor` and kin in the binary, bytes on 6.4.0.

| | Today | A | B | C | P |
|---|---|---|---|---|---|
| Allocations per frame | 1 (160 B) | 1 (160 B) | 1 (160 B) | **2 (200 B)** | 1 (160 B) |
| Executor checks in the binary | 2 | 2 | 2 | 2 | 2 |
| `Text` / `Button<Text>` bytes | 16 / 32 | 16 / 32 | 16 / 32 | 16 / 32 | 16 / 32 |
| Executable bytes | 144,984 | 143,640 (−0.9%) | 152,312 (+5.1%) | 145,816 | 152,312 |

The allocation and struct-size rows were the same on all three compilers. The 2 checks are the harness's own.
By language rule (SE-0431: a sync nonisolated call "runs immediately without changing the current isolation"), and as the counts
agree, **A and B add no hop and no allocation per view.** I also timed it at 945–1,270 ns per frame across all designs and compilers,
but on a busy machine with no consistent order: read that as "no large difference", not as an A/B. **A real A/B on real TUI on a
quiet box is still needed before landing,** and an agent is the wrong one to run it.

##### Compile time and bytes at scale

Generated module of 300 views and 600 modifiers plus a client, `-O -wmo`, user + system CPU, minimum of 3, busy machine.

| | Library CPU s (6.4.0 / 6.3.3 / Xcode 6.2.4) | Client CPU s | Library bytes (6.4.0) | Client bytes (6.4.0) |
|---|---|---|---|---|
| Today | 1.98 / 2.14 / 1.65 | 1.01 / 1.45 / 1.10 | 1,322,536 | 677,256 |
| A | 1.96 / 2.23 / 1.56 | 1.01 / 1.30 / 1.19 | 1,294,840 (−2.1%) | 685,040 (+1.1%) |
| B, *every* view and handler with an overload | 2.69 / 2.58 / 2.49 | 0.97 / 1.34 / 1.18 | 2,138,008 (+65%) | 685,040 |

So A costs about nothing to compile. An async overload weighs about 0.9–1.4 KB of object code each (936 B on 6.3.3, 1,405 B on 6.4.0),
and the generated module gives one to all 600. **Keeping them to the handlers that matter, say 30, is about 30–40 KB unstripped.**
A client calling the sync form pays nothing.

##### Migration, tried on the real code

`trial_migrate.py`, run on a copy of `Sources`, marks public view and modifier types `nonisolated`, puts `@MainActor` on their other
members and extensions, and puts `nonisolated` on public modifiers and inits.

| Across all library modules | Count |
|---|---|
| Files / lines the script changes | 536 / about 3,180 (a token each) |
| Types made `nonisolated` | 347 |
| `nonisolated` modifiers in `extension View`; other inits and funcs | 643; 397 |
| `@MainActor` added on extensions / members | 969 / 824 |
| Public plain-closure handler parameters to make `@MainActor` | 135 |
| Public `@ViewBuilder` closures, staying plain as in SwiftUI | 214 |

**What the trial did (6.3.3; only TUIView and TUIFoundation were migrated, 2 of 30-odd modules):**
- **TUIView, 29k lines:** the script, then 1 hand fix. Clean, no warnings.
- **TUIFoundation, 155k lines:** the script, an autofixer, about 15 hand edits, and `Button` moved to `@preconcurrency @MainActor`
  closures (9 parameters). **0 errors on 6.3.3 and on 6.4.0.** 92 public members are parked at `@MainActor` for now. Trying to free them
  showed about 48 distinct callees behind them, mostly a one-line `nonisolated` on a private `_*Core` or modifier init. So roughly 50
  more small hand edits there.
- **Everything above, unmigrated, compiled against that** with hand edits in 12 files, mostly a `@MainActor extension` or a
  `{ action() }` wrapper. **`Example` (34k lines) compiled with its source untouched, and 1 new warning**, the one above
  (`TrackStyleEditor.swift:291`). In a PTY it drew and took 6 scripted keys for 5 s without dying (a weak smoke; no test suite run).
- **27 of 37 expressions already compile on the real framework from a free function** (2 more of the probes were my own mistakes),
  including `Text(verbatim:)`, `Text(someString)`, the stacks, `.bold()`, `.foregroundStyle`, `.frame`, `.background`, `.opacity`,
  `.disabled`, `.onAppear`, `.task`, `.onChange`, `.onTapGesture { model.inc() }`, `Button(someString) { model.inc() }`, `Toggle`,
  `AnyView`, `GeometryReader`, `ScrollView`, `Group`, `Image`. **Not yet, for lack of those root fixes:** `.padding`, `.border`,
  `.hidden`, `.id`, `ForEach`, `Label`, `Section`, and everything taking a literal key.

**The one fix that needs thought is `Text("literal")`,** whose init interns a source in a `@MainActor` table (`Text+Locale.swift:86`).
I put it behind an `NSLock` in the trial. CLAUDE.md's exemption for a process-wide memo of a pure function fits, and
`LocalizationService` already takes an `NSLock` on that path. **The cost of that lock is not measured, and this init is hot.**

**Traps found:**

- A `nonisolated` type loses its implicit `Sendable`, so a `static let` of one fails until declared (`EmptyModifier`,
  `ContainerBackground`). `Text`'s and the stacks' `Sendable` still need declaring and auditing: **unverified**.
- Members of an extension of a `nonisolated` type are nonisolated even when the extension adds a `@MainActor` protocol. Hence
  `@MainActor extension X: Renderable`, among the 969.
- `@preconcurrency` on a function also downgrades errors *in its own body* to warnings (`onTapGesture` in the trial). The
  zero-warnings rule is what catches these.
- 6.4.0 adds one warning 6.3.3 lacks (`StyledContent.swift:32`, `sending 'view' risks causing data races`).
- **On 6.2.4 a `nonisolated struct` may not hold a property wrapper** (`'nonisolated' is not supported on properties with property
  wrappers`); 6.3.3 and 6.4.0 accept it. All 16 errors on 6.2.4's TUIFoundation are this, and **67 types** across the framework hold one.
  For those the 6.2 spelling is a plain struct with `View` in an extension, as SwiftUI's `Text` is: `body` then infers `@MainActor`,
  other members must state it. Tested in miniature on all three, not on those 67.

**Source compatibility.** Nothing becomes `@MainActor` that was not, so callers stay in the same or a wider isolation. The breaks seen:
the warning above, and code that assigned a TUI handler parameter to a plain closure. **Custom `Renderable` views need no change:**
`struct X: View, Renderable` is still inferred `@MainActor`. One that wants building off-main adds `nonisolated init`.

**The size of it:** my judgment, not a measurement: about 3 lanes, mostly mechanical.

#### 7. What a bump of the minimum Swift would and would not gain

| Bump to | Gains (measured) | Does not gain |
|---|---|---|
| **6.3** | `nonisolated struct` with a property wrapper: 67 types keep the simple spelling | Anything else in your ask |
| **6.4** | `-> sending some View`; `~Sendable`, async `defer`, cancellation shields and the `Observation` tracking API, none needed here | Sync `@isolated(any)` calls; overloading on isolation; partial application of actor methods; closure isolation control; `default nonisolated` and `Disconnected`, neither in 6.4.0 |

**Not worth a bump.** The features that would really help do not exist in any installed compiler, and the two biggest runtime limits are the OS rather than Swift: `Task.immediate` needs macOS 26, and `@isolated(any)` as a generic argument needs macOS 15. SE-0478 is worth watching: `default nonisolated` per file would make this migration far smaller, though it is not yet in 6.4.0.

#### 8. Recommendation

**Adopt design B in this order. No Swift bump. Each stage lands alone and leaves TUI better than the last.**

1. **Now, no code:** document `@MainActor` and `.defaultIsolation(MainActor.self)` in `ComingFromSwiftUI.md` and `CustomViews.md`, whose `makeView` sample hits this today (survey finding 3).
2. **Build anywhere.** `ViewBuilder` loses `@MainActor`; view values and modifiers go nonisolated, bottom module up; fix `Text`'s table; run the A/B including the literal path. Free functions, enums and models then compile as on SwiftUI.
3. **Handlers.** `@preconcurrency @MainActor` on the 135 parameters, starting from `Button`, which then matches SwiftUI exactly.
4. **`Sendable` view values where cheap:** `Text`, stacks, `Button` conditionally, so `Task.detached { VStack { … } }` compiles.
5. **Flexible overloads.** The async `@isolated(any)` overload and `on:` on `Button`, then whichever handlers you choose. This is where TUI passes SwiftUI, and it is cheap once the rest is done.

**Do not adopt C** (one `@isolated(any)` signature): it breaks SwiftUI code, adds an allocation per view per frame, and rests on an `unsafeBitCast` of a function value.

#### 9. Open questions for you

1. **`@preconcurrency` on `View` itself?** With it (P), a user's `struct Row: View { let c: Content }` built in a free function compiles with a warning, as on SwiftUI; without it that is an error, fixed by `nonisolated init` or `@MainActor` on the function. But it also turns real races into warnings: `Button("x") { @DB in stateVar += 1 }` warns in P and is an error in B. No extra executor check appeared in the prototype either way. **I recommend no:** the program does not misbehave, it fails to compile with a precise message and a one-word fix.
2. **Conditional `Sendable` on `State` and `Binding`?** SwiftUI's `Binding` has it. With it, `struct Row: View { @State var n = 0 }` keeps a nonisolated memberwise init and works from a free function (verified in miniature on all three). But a detached task could then write to it, and I would not assume `StateBox` is safe off the main actor. **I recommend no, unless `StateBox` is made safe**, at some cost to every state read.
3. **How far should the overloads spread?** `Button` and `onChange` are the obvious pair; `onTapGesture`, `onAppear`, `onSubmit` and `onKeyPress` could follow. I recommend `Button` alone until it is wanted elsewhere.
4. **What should an async press do when pressed twice, or when its button goes away?** As prototyped, each press is its own task, they may overlap, and leaving the screen cancels nothing, unlike `.task`. No SwiftUI precedent, so your call.
5. **An actor-model helper?** Users mirror into `@State` by hand. A small helper could keep the mirror fresh (say `.task` over `Observations`, macOS 26 and Linux). Not designed.
6. **Is the warning on `Button("x", action: plainClosure)` acceptable?** Avoiding it means giving up `Button { model.inc() }` in a free function, or building a TUI module in Swift 5 mode. I would accept it.

#### 10. Not verified

- Anything run on Linux or macOS 26 (`Task.immediate`, `Observations`): compiled only.
- Performance and compile time on real TUI: no A/B, no profile. The prototype's counts are sound, its timing is not an A/B. The lock on literal `Text`.
- The test suites, the parity tool, DocC and the macros against the changed declarations.
- The trial's scope: 6.2.4 only far enough to see the wrapper errors; upper modules not migrated; the 67 wrapper types; the `Sendable` audit of real views.

#### Sources

Swift Evolution: [SE-0431](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0431-isolated-any-functions.md), [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md), [SE-0449](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0449-nonisolated-for-global-actor-cutoff.md), [SE-0434](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0434-global-actor-isolated-types-usability.md), [SE-0470](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0470-isolated-conformances.md), [SE-0472](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0472-task-start-synchronously-on-caller-context.md), [SE-0420](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md), [SE-0478](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0478-default-isolation-typealias.md), [SE-0538](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0538-disconnected.md), [SE-0506](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0506-advanced-observation-tracking.md); status from [the Evolution index](https://download.swift.org/swift-evolution/v1/evolution.json). [Swift CHANGELOG](https://github.com/swiftlang/swift/blob/main/CHANGELOG.md); [underscored attributes](https://github.com/swiftlang/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md); [closure isolation control pitch](https://forums.swift.org/t/closure-isolation-control/70378). SwiftUI: `SwiftUI.swiftinterface` and `SwiftUICore.swiftinterface`, macOS 15.5 SDK.

#### 11. Addendum: no `@preconcurrency`, blocking, re-entrancy (2026-11-01)

The owner asked to avoid `@preconcurrency`, whether an async action blocks rendering, and how re-entrancy and order are handled. Probes: `scratchpad/isolation/nopc` (`Z4.swift`, `cases2.py`, `run/probe.swift`), Swift 6 mode, through SIL (`-typecheck` alone skips the region checks and wrongly passed every unsafe case).

**Avoiding `@preconcurrency`.** `Button` takes three overloads: `@MainActor () -> Void`; a `@_disfavoredOverload` plain `() -> Void`; and `@isolated(any) @Sendable () async -> Void`, plus `on:`. The struct stores a plain closure, so it is not `Sendable`. Same on 6.2.4, 6.3.3 and 6.4.0, no warnings: a literal in `body`; a stored plain closure passed through; a literal in a free function using a main-actor model; `await` on an actor; `on:`. Five unsafe shapes are hard errors, where `@preconcurrency` gave a warning for those it caught. Lost: a sync `{ @DB in … }` literal, with a poor message (one with `await` still compiles), and `Button` crossing actors. Unmeasured: the solver cost of the extra overload on real TUI.

**Blocking (a model of the loop, not TUI).** Press returned in 0 ms; 13 to 14 frames ticked in 300 ms during a 200 ms save on another actor (no baseline taken). With 200 ms of sync work before the first `await`, on the main actor, 5 to 6 frames: sync code on the main actor holds frames, as any handler's does today.

**Re-entrancy and order, unguarded.** Two presses of a save on an actor both saw `n=2` and left `n=3`: a lost update, as an actor gives up isolation across `await`. Start order: 200/200 for main-actor closures, 193 to 194/200 for nonisolated ones.

**Proposal.** A per-button policy: ignore a press while its action runs (default), queue in press order, restart, or concurrent; a container modifier for one queue across buttons. Don't cancel when the button leaves the screen, which would lose a save: this reverses the suggestion in section 9, question 4.
