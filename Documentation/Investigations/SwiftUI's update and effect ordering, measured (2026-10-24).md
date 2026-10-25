# SwiftUI's update and effect ordering, measured (2026-10-24)

> **Status:** measured 2026-10-24, to inform how TUIkit orders body evaluation, layout, drawing and effects; no
> decision taken yet. **Asked by:** the owner, through the lead agent. **Probe:**
> `Tools/SwiftUIProbes/Effect and update ordering/` (`ordering.swift`, `run.sh`, one `.out` per case). **Working
> notes:** none.

## Question

When does SwiftUI run a view's effects — `onAppear`, `onChange(of:)`, `onPreferenceChange`,
`onGeometryChange(for:of:action:)`, `onScrollGeometryChange`, the start of `.task` — relative to body evaluation,
layout and the frame that reaches the screen? In particular:

1. Does an effect ever run during a body evaluation or a layout pass, or always after the graph update?
2. Is the first frame drawn after a state write in `onAppear` (or `onChange`, or `onPreferenceChange`) drawn with
   the old state or the new?
3. How many update passes does one frame get when effects keep invalidating state, and where do the "tried to
   update multiple times per frame" warnings start? Does the loop stop, or go on next frame?
4. Is a `GeometryReader`'s content ever run with a provisional size and run again in the same update?
5. When does `.task` start, and on which executor?
6. What does a `@State` write inside `body` do?

## Answer

Each answer says how it is known: **measured** (a line of a log, below), or **inferred** (reasoned from the logs,
not observed directly).

1. **Never during a body or a `Layout` call; always after a graph update** (measured). Effects run in SwiftUI's
   `Update.dispatchActions()`, at one of two places: inside `NSHostingView.layout()`, from
   `ViewRendererHost.render(interval:updateDisplayList:targetTimestamp:)`, after a graph update; or, for an update
   that SwiftUI's own run-loop observer runs (after a change from outside, or the rest of a chain of effects), from
   `Update.end()`, when that update's transaction closes (the stack is from the outside change). No effect line in any log says "in a body" or "in Layout".
   They do run *inside the host's `layout()`* — between one round of graph update and drawing and the next.
2. **The new state** (measured, three ways). The state a frame shows before the write is never drawn after it:
   `onAppear`'s `loaded = true` is applied before anything is drawn, so the first `Canvas` call and the first
   committed layer tree both show `loaded = true` (`appear.out`); an `onChange` and an `onPreferenceChange` that react
   to an outside write update the graph in SwiftUI's observer and are drawn in the display cycle that follows, with
   the new state (`change.out`).
3. **Two re-updates inside the layout pass, then the rest in SwiftUI's `beforeWaiting` observer, with no count limit
   across different actions** (measured). A chain of 100 different `onChange` modifiers ran 2 steps inside the layout pass
   and the other 98 in one `beforeWaiting` callout, 101 body evaluations in all, before the first display-link
   callback, with no warning (`chain.out`). What is limited is **one action reacting to its own writes**: an
   `onChange(of: x)` that sets `x + 1`, and an `onPreferenceChange` that feeds its own preference, each ran twice
   after a draw and then not again, with `onChange(of: Int) action tried to update multiple times per frame.` and
   `Bound preference IntKey tried to update multiple times per frame.` The suppressed change is dropped, not deferred:
   it gets no call on the next frame either; a later write from outside starts the action again, for two more calls
   (`selfloop.out`, `prefloop.out`). `onGeometryChange` has no count limit (298 calls in one callout,
   `geocount.out`) but stops when the value it would deliver repeats one it delivered two calls before, with
   `Geometry action is cycling between duplicate values.` (`geofeedback.out`). That the limit is "two per draw" is
   **inferred** from two runs of the loop that are both consistent with it (below).
4. **No provisional size** (measured, for a stack, a `ScrollView` and a `List`). A reader's content runs once per
   update, with that update's final size; the sizing queries AppKit makes through `updateConstraints()` (proposals
   `0×0` and `∞×∞`) do not run it, and neither does a `List` sizing its rows. When the reader's size depends on its
   own content through state (an `onGeometryChange` action that resizes its sibling), every step is a full update
   with a new size, and **intermediate steps are drawn and committed**: the first commit carried the reader at 300
   points, the second at 266.67 (`geofeedback.out`). Whether that first commit is ever on screen depends on whether
   a vsync falls between the two commits (**inferred**; nothing here captures the screen).
5. **After the first commit, on the main actor, whatever its priority** (measured). Both `.task` and
   `.task(priority: .background)` start on the main thread with `#isolation` `MainActor`, after the post-commit
   handler of the first frame, never inside a layout pass (`appear.out`).
6. **The write is lost** (measured). SwiftUI logs `Modifying state during view update, this will cause undefined
   behavior.`; the body reads the old value straight after its write, no update follows, and a later body
   evaluation still reads the old value (`bodywrite.out`).

## Key measurements

`Tools/SwiftUIProbes/Effect and update ordering/run.sh` builds `ordering.swift` with Xcode 26.3's `swiftc` (Swift
6.2.4) against the macOS 26.2 SDK and runs each case in its own process, in a 400 × 300 borderless window ordered
on screen, on macOS 15.8.1 (arm64, a VM with an Aqua session), with `OS_ACTIVITY_DT_MODE=YES` so that SwiftUI's
runtime warnings reach the log (`[runtime] …`). Each log line is one event, numbered in order:

```
 seq  f<display-link callbacks so far>  ms since the window was made  event  [what it ran inside]
```

The hooks: an `NSHostingView` subclass logs its `updateConstraints()`, `layout()`, `viewWillDraw()` and each
`needsLayout = true`; bodies log at their top through `traced(_:_:)`, and say "in a body" for anything inside;
a custom `Layout` logs `sizeThatFits` and `placeSubviews`; a `Canvas` logs when SwiftUI draws it (`DRAW`); two
main run-loop observers, at the lowest and highest order of every activity, bracket the observers that AppKit, Core
Animation and SwiftUI run (`runloop: … observers begin / done`); a Core Animation post-commit handler, armed from
the host's `layout()` through the SPI `+[CATransaction addCommitHandler:forPhase:]`, marks the commit and renders
the host's sublayers (`committed layer tree: …`, the colour under a few points); a `CADisplayLink` from
`NSView.displayLink(target:selector:)` marks frames (`── vsync`). With `PROBE_STACKS` set, a few events print the
stack behind them once, demangled.

Each case was run four times. The times and frame numbers differ between runs; the order of events differed in two
ways only: whether the second commit of a long chain (questions 3 and 4) ran in the next run-loop turn's
`beforeTimers` observers, before any display-link callback, or straight after the first callback; and where the
`background`-priority task's first line fell among the other tasks' lines. The excerpts below are from the
committed `.out` files.

### Where the display cycle and SwiftUI's updates run

The first body evaluation is synchronous: it runs inside `orderFrontRegardless()` (between the log's "ordering the
window front" and "window ordered front"), or, in `chain` and `geoscroll`, inside the `contentView` assignment before
it, with no effect run and nothing drawn. AppKit's display cycle then runs as a commit handler of Core Animation's implicit transaction, from a
run-loop observer of AppKit's (stack of `host.layout`, `appear.out`; the probe leaves block frames out of its stacks,
and a full backtrace from an earlier build named that observer's block
`+[CATransaction(NSCATransaction) NS_setFlushesWithDisplayLink]`):

```
AppKit _NSViewLayout <- … <- -[NSWindow(NSConstraintBasedLayoutInternal) layoutIfNeeded] <- NSDisplayCycleObserverInvoke
  <- NSDisplayCycleFlush <- QuartzCore CA::Transaction::run_commit_handlers(CATransactionPhase)
  <- CA::Transaction::commit() <- CoreFoundation __CFRunLoopDoObservers <- __CFRunLoopRun
```

After a change from outside a view update, SwiftUI updates the graph in an observer of its own,
`static NSRunLoop.addObserver(_:)` (stack of a body in the `exit` observers, `change.out`):

```
SwiftUICore specialized ViewBodyAccessor.updateBody(of:changed:) <- … DynamicBody.updateValue() <- … AG::Subgraph::update(unsigned int)
  <- specialized GraphHost.runTransaction(_:do:id:) <- … GraphDelegate.beginTransaction() <- … specialized closure #1 in static NSRunLoop.addObserver(_:)
  <- CoreFoundation __CFRunLoopDoObservers <- CFRunLoopRunSpecific
```

That observer ran at `exit` after a write made by main-queue work, and at `beforeWaiting` for the rest of a chain;
it updates bodies and layout and runs effects, then sets the host's `needsLayout`; drawing waits for the next display
cycle.

### 1 and 2: `onAppear`, and what the first frame shows (`appear.out`)

```
  18 f0      36.2  host.layout begin
  19 f0      39.5  onGeometryChange of: size=400x300   [in host.layout]
  20 f0      40.2  onPreferenceChange 0   [in host.layout]
  21 f0      40.4  onGeometryChange action: 400x300   [in host.layout]
  22 f0      40.4  onAppear (loaded=false) -> loaded = true   [in host.layout]
  23 f0      45.2  AppearChild.onAppear   [in host.layout]
  24 f0      45.3  body AppearRoot loaded=true   [in host.layout]
  25 f0      45.4  body AppearChild loaded=true   [in host.layout]
  26 f0      45.7  Layout[outer].sizeThatFits proposal=400x300 begin   [in host.layout, in Layout]
  28 f0      45.8  Layout[outer].placeSubviews bounds=400x56   [in host.layout, in Layout]
  29 f0      45.8  body (GeometryReader content) size=400x40   [in host.layout]
  30 f0      46.1  DRAW loaded=true (canvas 8x8)   [in host.layout]
  31 f0      46.1  onPreferenceChange 1   [in host.layout]
  32 f0      46.2  onChange(loaded) false -> true   [in host.layout]
  33 f0      46.8  host.layout end
  35 f0      50.0  CA post-commit handler: the transaction is committed (armed by host.layout)
  36 f0      50.5    committed layer tree: pixel=GREEN
  39 f1      50.8  ── vsync f1
```

The first round of effects (geometry, preference, both `onAppear`s, parent before child) runs before anything is
drawn; their write is updated (bodies, `Layout`, the reader) and drawn (`DRAW loaded=true`) in the same layout
pass, and a second round of effects (`onPreferenceChange 1`, `onChange(loaded)`) follows the draw. No `DRAW
loaded=false` appears in any run, and the first committed layer tree is green (`loaded = true`; red would be
`false`). The stack of `onAppear`:

```
SwiftUICore Update.Action.callAsFunction() <- static Update.dispatchActions()
  <- closure #2 in closure #1 in ViewRendererHost.render(interval:updateDisplayList:targetTimestamp:)
  <- ViewRendererHost.render(interval:updateDisplayList:targetTimestamp:) <- SwiftUI closure #1 in NSHostingView.layout()
  <- AppKit +[NSAnimationContext runAnimationGroup:] <- SwiftUI NSHostingView.layout() <- AppKit _NSViewLayout <- …
```

### 2: `onChange` and `onPreferenceChange` after a write from outside (`change.out`)

```
  22 f32    545.4  TRIGGER 1: driver.flag = true (outside any update)
  23 f32    545.6  runloop: exit observers begin
  24 f32    545.6  body ChangeRoot flag=true phase=A fromPreference=0
  25 f32    548.3  host.needsLayout = true
  26 f32    548.3  onChange(flag) -> true: phase = B
  27 f32    549.7  body ChangeRoot flag=true phase=B fromPreference=0
  28 f32    549.9  runloop: exit observers done
  29 f32    550.0  runloop: beforeTimers observers begin
  32 f32    550.0  host.layout begin
  33 f32    550.1  DRAW left phase=B (canvas 8x8)   [in host.layout]
  36 f32    550.3  CA post-commit handler: the transaction is committed (armed by host.layout)
  37 f32    550.5    committed layer tree: left=GREEN right=RED
```

The `onChange` runs outside any layout pass, in SwiftUI's observer, straight after the update that saw the change;
its stack ends `_ValueActionModifier2.sendAction(old:) <- ValueActionDispatcher.updateValue() <-
Update.dispatchActions() <- static Update.end() <- closure #1 in static NSRunLoop.addObserver(_:)`. The first
`DRAW` after the write already has `phase=B`. The preference trigger at 1 s reads the same way: `body PrefSource
prefFlag=true`, `onPreferenceChange 1: fromPreference = 1`, `body ChangeRoot … fromPreference=1`, all in the `exit`
observers, then `DRAW right fromPreference=1` and `left=GREEN right=GREEN`.

### 3: chains and loops

`chain.out`, 100 `onChange` modifiers, each setting the next one's value:

```
  10 f0      27.1  onAppear -> s[0] = 1   [in host.layout]
  11 f0      27.9  body ChainRoot ones=1   [in host.layout]
  12 f0      28.9  DRAW last=0 (canvas 8x8)   [in host.layout]
  13 f0      28.9  onChange(s[0]) -> s[1] = 1   [in host.layout]
  14 f0      29.0  body ChainRoot ones=2   [in host.layout]
  15 f0      30.1  onChange(s[1]) -> s[2] = 1   [in host.layout]
  16 f0      30.1  host.layout end
  19 f0      33.7    committed layer tree: pixel=RED
  21 f0      34.3  runloop: beforeWaiting observers begin
  22 f0      34.3  body ChainRoot ones=3
  …                (98 onChange steps, one body evaluation after each)
 217 f0     119.2  body ChainRoot ones=100
 219 f0     120.1  runloop: beforeWaiting observers done
```

and the last state is drawn and committed in the next display cycle (green). No warning.

`selfloop.out`, one `onChange(of: x)` that sets `x + 1` up to 200:

```
  10 f0      23.1  onAppear -> x = 1   [in host.layout]
  12 f0      23.4  DRAW x=1 (canvas 8x8)   [in host.layout]
  13 f0      23.4  onChange(x) saw 0 -> 1 -> x = 2   [in host.layout]
  15 f0      23.5  DRAW x=2 (canvas 8x8)   [in host.layout]
  16 f0      23.9  onChange(x) saw 1 -> 2 -> x = 3   [in host.layout]
  22 f0      26.6  runloop: beforeWaiting observers begin
  23 f0      26.6  body SelfLoopRoot x=3
  25 f0      29.0  onChange(x) saw 2 -> 3 -> x = 4
  26 f0      29.1  body SelfLoopRoot x=4
[runtime] [Invalid Configuration] onChange(of: Int) action tried to update multiple times per frame.
  33 f1      29.9  DRAW x=4 (canvas 8x8)   [in host.layout]
  …                (nothing for half a second: x stays 4)
  40 f32    541.8  TRIGGER: driver.flag = true (outside any update)
  44 f32    544.2  onChange(flag): x = 100
  46 f32    544.3  onChange(x) saw 4 -> 100 -> x = 101
  48 f32    544.4  onChange(x) saw 100 -> 101 -> x = 102
  49 f32    544.4  body SelfLoopRoot x=102
  55 f32    544.6  DRAW x=102 (canvas 8x8)   [in host.layout]
```

The change to 4 and the change to 102 got no call, then or later; the second suppression printed no second warning.
`prefloop.out` is the same with `onPreferenceChange` (0 → 1 → 2 in the layout pass, 3 in the `beforeWaiting`
observer, then `Bound preference IntKey tried to update multiple times per frame.` and `DRAW n=4` next frame).

**Inferred:** the action runs at most twice after each draw of its host. In the first run, the calls for 2 and 3
come after `DRAW x=2` and the one for 4 is refused; in the second, no draw comes between the calls for 100, 101 and
the refused 102. "Two calls per update", "three per frame" and "a fixed count of changes" each contradict one of the
two runs. Not tested: a loop whose writes are spread over several draws for longer.

`geocount.out`: an `onGeometryChange` whose action widens its sibling by one point, so that every value is new,
was called 3 times in the layout pass and 298 times in one `beforeWaiting` callout, until its own stop at a sibling
of 300 points, with no warning.
`geofeedback.out`: one whose action sets the width of a sibling to half the reader's width converges by halving to
266.67 points; after 50 calls in the `beforeWaiting` callout the value it would deliver, `266.66666666666663`, was
one it had delivered two calls before (seq 225), and SwiftUI stopped:

```
 229 f0      28.9  onGeometryChange action: 266.6666666666667 -> readerWidth
 232 f0      29.1  onGeometryChange of: width=266.66666666666663
[runtime] [Invalid Configuration] Geometry action is cycling between duplicate values.
```

### 4: `GeometryReader` sizes

In `appear.out` the reader's content ran at `400x40` during the window's first update; then `updateConstraints()`
asked the custom `Layout` for `proposal=0x0` and `proposal=infxinf` without running the content; the next run of
the content, after the `onAppear` write, was again at the placed size, `400x40`. In `geoscroll.out` the reader in a
`ScrollView` ran once, at `400x10` (no height was offered, and a reader's ideal height is 10), and
`onScrollGeometryChange` delivered `contentSize=400x410 container=400x300` in the first layout pass. In `geolist.out`
each reader in a `List` row ran once (`368x16` alone in a row, `160.50x16` behind a row's text), during the display
cycle but outside the outer host's `layout()` (rows are laid out by the table's own row views), and the row's
`onGeometryChange` and `onAppear` followed its content.

`geofeedback.out`, in the first layout pass:

```
  11 f0      16.2  onGeometryChange of: width=400.0   [in host.layout]
  12 f0      16.4  onGeometryChange action: 400.0 -> readerWidth   [in host.layout]
  14 f0      16.5  body (GeometryReader content) size=200x300   [in host.layout]
  16 f0      16.6  DRAW reader content for 200x300 (canvas 8x8)   [in host.layout]
  17 f0      16.6  onGeometryChange action: 200.0 -> readerWidth   [in host.layout]
  19 f0      16.6  body (GeometryReader content) size=300x300   [in host.layout]
  21 f0      16.7  DRAW reader content for 300x300 (canvas 8x8)   [in host.layout]
  22 f0      17.0  onGeometryChange action: 300.0 -> readerWidth   [in host.layout]
  26 f0      19.2    committed layer tree: red begins at x=300
```

then 50 more steps in the `beforeWaiting` callout (`250`, `275`, `262.5`, … `266.67`), and
`242 f1 … committed layer tree: red begins at x=267`. The reader's content at the first size, `400x300`, was run
(during the window's first update) but never drawn. Each later size was the size of a completed update, not a guess
inside one.

### 5: `.task` (`appear.out`)

```
  35 f0      50.0  CA post-commit handler: the transaction is committed (armed by host.layout)
  39 f1      50.8  ── vsync f1
  40 f1      52.3  runloop: after beforeSources: CFRunLoop blocks, version-0 sources, and main-queue work already waiting
  41 f1      52.3  task starts: main thread=true isolation=Optional(Swift.MainActor) priority=TaskPriority.high
  42 f1      52.3  task(priority: .background) starts: main thread=true isolation=Optional(Swift.MainActor)
  44 f1      52.4  task after Task.yield()
  46 f1      53.6  task after Task.sleep(1 ms)
```

In every run both tasks started after the first commit, outside any observer and any layout pass, at the point of
the run loop where it services main-queue work that is already waiting; in one of four runs that was before the
first display-link callback rather than after it. The stack of a task's first line names no caller that means
anything (an async function's frames start at the executor), so it is not quoted.

### 6: a `@State` write in `body` (`bodywrite.out`)

```
   4 f0       7.3  body BodyWriteRoot n=0 flag=false prefFlag=false
   5 f0      11.6  body writes n = 1   [in a body]
[runtime] [SwiftUI] Modifying state during view update, this will cause undefined behavior.
   6 f0      11.7  body after the write reads n=0   [in a body]
  12 f0      17.3  DRAW n=0 (canvas 8x8)   [in host.layout]
  23 f32    535.5  body BodyWriteRoot n=0 flag=true prefFlag=false
  24 f32    537.7  body writes n = 2   [in a body]
[runtime] [SwiftUI] Modifying state during view update, this will cause undefined behavior.
  25 f32    537.8  body after the write reads n=0   [in a body]
  41 f64   1059.0  body BodyWriteRoot n=0 flag=true prefFlag=true
```

The write warned both times (once during the window's first update, once in SwiftUI's observer), and was lost both
times: no update followed it, nothing was drawn green, and the body re-run by a third, unrelated change still read
`n=0`.

## Reasoning, and what is not measured

- **"After the graph update" is measured by stacks, not only by order.** Every effect stack the probe printed (the
  root's `onAppear`, a `List` row's `onAppear`, `onChange(flag)`) goes through
  `Update.dispatchActions()`, called either from `ViewRendererHost.render(…)` or from `Update.end()`; none goes
  through `ViewBodyAccessor.updateBody` or a `Layout` call. SwiftUI's internal symbols are not exported, so a frame
  in a SwiftUI module is printed as the nearest exported symbol; the names quoted here are consistent with each other
  and with the order of the log, but a single frame's name could be a neighbour's.
- **"Drawn" means SwiftUI drew it into layers, and "committed" means Core Animation sent it to the render server.**
  A `Canvas` renderer call is SwiftUI drawing that view; the post-commit handler's render of the layer tree is what
  was committed. What the display showed was not captured: that a commit appears at the next vsync, and that of two
  commits with no vsync between them only the second is seen, is how Core Animation works, not something these logs
  show.
- **The frame counter counts display-link callbacks, not vsyncs.** A callback cannot run while the main thread is
  busy, so the 86 ms of the chain's `beforeWaiting` callout count as "f0". Several vsyncs passed during it; the
  first commit (the chain's second state) was very probably on screen for some of them (inferred).
- **Not measured:** animations and transactions; `onDisappear`; `onReceive`; effects in a `Table`, `NavigationStack`
  or sheet; iOS (`UIHostingController`), where the hosting view's layout pass differs; macOS 26's SwiftUI, which this
  macOS 15 machine cannot run. The probe does not prove there is no global limit on update passes per frame, only that
  101 body evaluations, and 298 `onGeometryChange` calls, in one callout met none.

## What this suggests for TUIkit (inferred)

These are readings of SwiftUI's behaviour for TUIkit's design, not checks of TUIkit's current code:

- Effects belong after an update completes, outside any body evaluation and any `Layout` call; SwiftUI then
  updates and draws again within the same layout pass, so that a write in `onAppear` is in the first frame.
- A bounded number of re-updates per frame inside the frame's own pass (two, in SwiftUI), with the rest of a chain run
  outside it and drawn as an extra frame, keeps a long chain from blocking a frame's first draw; a frame of an
  intermediate state can then reach the screen.
- The guards are per action: twice per draw for `onChange` and preference actions, a repeat-value check for
  geometry actions; a dropped change is not replayed.
- A `GeometryReader`'s content needs only the final size of each update; measuring passes never run it.
- `.task` work starts on the main actor after the first frame is committed.
- A write to `@State` from `body` is dropped with a warning.

TUIkit's corresponding code: `Sources/TUIkitFoundation/Extensions/View+Events.swift` (`onAppear`, `onChange`),
`Sources/TUIkitFoundation/Extensions/View+Preferences.swift` (`onPreferenceChange`),
`Sources/TUIkitFoundation/Modifiers/OnGeometryChangeModifier.swift`.
