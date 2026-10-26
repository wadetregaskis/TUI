# SwiftUI's update model beside TUI's

> **Status:** written 2026-10-24, read-only against `main` at `ac1cd30cf` and lane EFFECTS (`lane-effects`,
> B-D5G-4 steps 1–5, not yet landed). No TUI builds and no timing runs were made for it. Every number is
> quoted, with its date, from a committed record, except Option C's step-0 table in §1.4, which was measured on
> 2026-09-23 and recorded nowhere else. **Asked by:** the owner, 2026-10-24. **Working notes:** none.
> SwiftUI's ordering of effects was measured the same day by a separate probe, on macOS 15.8.1's SwiftUI
> (Xcode 26.3; macOS 26's is untested): §2.3 summarises it, and the claims it settles are marked **[M]**.
> **Landed** 2026-10-24 (`910819db3` and the commits after it); moved here from `Investigations/` on 2026-10-26.
> **Decided and built:** the owner approved §6's recommendation on 2026-10-24. Option (a)'s steps 2 and 4 —
> effects held to the end of the walk in SwiftUI's order, and up to two walks more before the frame is written —
> are built on lane EFFECTS (decisions B-D5G-11). Step 3 (toolbars and focused values through the same loop) is
> not. The tables below describe TUI as it was when this was written.

## Question

> "This seems to touch on something that we've discussed before many months ago, whereby SwiftUI seems to
> have a different approach to layout and render. I don't recall if we ever actually compared SwiftUI's
> approach with TUI's systematically. Because, of course, the obvious question is: should we do what
> SwiftUI is doing? Answering that question means figuring out what advantages SwiftUI's approach has, and,
> of course, if it has any disadvantages. Performance might be one concern, but I'm particularly interested
> in any functional differences or ways in which this would hamper our capabilities or maintainability."
> — the owner, 2026-10-24

## Answer

- **The difference is one thing, and the rest follows from it.** SwiftUI keeps three results apart, each
  computed from the one before: the view values (an update of a long-lived dependency graph), the layout
  (sizes and positions, worked out from that graph), and the drawing (a display list, built from the
  layout). TUI computes all three, and runs the effects, in one walk whose output *is* the frame. So in
  TUI a view can only learn where it is after it has been drawn, a measure is a speculative partial
  drawing, an effect runs before anything after it in the walk is drawn, and whatever an effect changes
  reaches the screen a frame later.
- **What users can observe.** In TUI, frames that SwiftUI does not show reach the screen: the state an
  effect writes (`onAppear`, `onChange`, `onPreferenceChange`, `onGeometryChange`) is drawn one frame later,
  ≥ 16.7 ms at the default cap. The frame before it is drawn without that state, or with it in only some
  places. SwiftUI draws an effect's write in the first frame after it; only a chain longer than its two
  in-pass re-updates, or a size fed back through state, commits intermediate states (measured, §2.3). Geometry is predicted and then corrected by drawing the subtree again, and where a container
  drops the markers nothing checks the prediction. A body can run more than once per frame. In return,
  TUI can draw a subtree, look at what it drew, and draw it again within the same frame, and its lazy
  rows keep their state off screen. SwiftUI can do neither.
- **Should we do what SwiftUI does?** Not wholesale. A dependency graph would buy back mostly
  *performance* in one class of frame: a write to data held above a large memoized subtree. That class
  already has a smaller fix, approved and half landed: Option C, SwiftUI's value-comparison contract for
  `Equatable` rows (§1.4). A graph would cost months, every `_*Core`, and the debuggability of a
  synchronous walk. The *functional* differences that matter come from presenting the first walk, not
  from the lack of a graph. They close with a much smaller change: **walk again before writing the frame
  whenever an effect changed state, bounded as SwiftUI bounds it (per action: an action that re-triggers
  itself runs twice per draw, then is cut off; two re-updates inside the frame's own pass), then hold the
  effects to the end of the walk, which is where the probe found SwiftUI runs them** (option (a), §5).
  Lane EFFECTS' `EffectStage` already holds the effects. The geometry gap keeps closing along the path D5G
  already chose: convert the containers that still leave a correction to the residual.
- **Measure first** (§6): how many frames per session an effect writes state in (the body-mutation
  diagnostic already counts writes during the walk); and what a second walk costs on those frames once the
  memo serves it. The SwiftUI ordering that option (a) must reproduce has been measured (§2.3); what the
  probe left out is listed there.

How to read the claims about SwiftUI: **[A]** is Apple's documentation or a WWDC session, **[C]** is
community analysis (reverse-engineered or observed; marked with its author), and **[M]** is measured by
TUI's own SwiftUI probes (`Tools/SwiftUIProbes/`). Sources are listed at the end.

---

## 1. The two models, side by side

### 1.1 The table

| | SwiftUI | TUI (`main`, 2026-10-24) |
|---|---|---|
| **Identity** | Structural, from the view's position and type in the hierarchy (`_ConditionalContent` per `if`), plus explicit identity (`ForEach` ids, `.id(_:)`) [A: Demystify SwiftUI, 2021]. | Structural: a parent-linked chain of `(type, index)` nodes, rendered as a path only on demand (`ViewIdentity.swift:9-52`). Explicit identity through `ForEach` ids and `.id(_:)`. The same rules in effect. |
| **State storage** | "`State` and `StateObject` are the persistent storage associated with your view's identity"; when the identity changes the state is replaced [A: 2021]. A `@State` is a node of the graph that the view struct holds only a handle to [C: Breur 2024]. | `StateStorage`, keyed by identity, a nested scope and a property index (`StateStorage.swift:37-146`). A view binds its `@State` boxes as its body is evaluated in the walk (`evaluateCompositeBody`, `Renderable.swift:312`). An identity not marked active in a pass is collected at the pass's end, unless a windowing container or a served memo retains it (`RenderCycle.md`, step 12). |
| **Dependency tracking** | A view depends on the value its parent produced, on its dynamic properties (`@State`, `@Environment`), and on the `@Observable` properties its body read, per instance and per property [A: 2021; Demystify SwiftUI performance, 2023; Discover Observation, 2023]. The graph "really tracks dependencies": an edge from a `@State` to the body that read it, from an environment key to the views that read it [C: Eidhof 2025; Breur 2024]. | No graph. A frame walks the scene from the root. What is tracked is *what may serve a stored result*: `@State` writes and `@Observable` reads per body, scoped to the reader's identity (`RenderCycle.md`, "Cache Invalidation"); environment changes noted where a modifier applies them; a global snapshot (palette, locale, size…); and special cases: the invalidation table has sixteen rows (focus moves, drags, hovers, timelines, geometry sizes, erased types…). |
| **Invalidation** | A change marks its dependents dirty, transitively. Values are recomputed lazily when something asks for them; a node whose inputs did not change is not recomputed [C: Breur 2024, Eidhof 2025]. Bodies re-run "only [for] those views that have new values or other changed dependencies" [A: 2023]. | A change *clears* stored results: `clearAffected(by:)` drops the written identity, its ancestors **and its descendants** (`RenderCache.swift:1396`). Nothing is recomputed lazily. The next walk recomputes everything that is not served from a value memo (`.equatable()`, a `ForEach` row over an `Equatable` element). |
| **Scheduling** | An event opens a transaction. Invalidated bodies run at its close [A: Explore SwiftUI animation, 2023], in a run-loop observer before the run loop waits, batched, so a view invalidated twice runs once [C: Breur 2022]. Drawing happens when Core Animation commits [C: Breur 2022]. | Demand-driven and capped: a write sets `needsRender`, and the loop renders at most once per frame interval (`FramePacer.swift:94`, `App.maxFrameRate`, default 60). A static screen renders nothing. |
| **Body evaluation** | Once per update for each invalidated view. "After the graph is updated, the view's body value is discarded" [A: 2023]. Layout runs from the graph without re-running bodies [C: Eidhof 2025]. | Every composite on the walk not served by a memo, each frame. Also once per *measure* that reaches it (`measureCompositeBody`, `ChildInfo.swift:960-970`), and a whole subtree per measure of a view that measures by drawing (`measureFixedByRendering`, `ChildInfo.swift:994`, 18 callers). |
| **Layout** | Parent proposes, child chooses its size, parent places [A: Compose custom layouts, 2022]. A child may be asked several times per pass, at zero, infinite, unspecified or given proposals [A: `Layout.sizeThatFits`]. Layout is a separate pass over the graph; each layout modifier has a layout computer and each child a geometry node [C: Breur 2024]. | Inside each container, fused with drawing: measure the children (`measureChild`, `ChildInfo.swift:539`), then *draw* each at its allocation, then composite the buffers. Several containers place a child by its **drawn** size (`ZStack`, `.frame`, the layers, `VStack`'s cross-axis alignment; design study A2 §3). Measures run with `isMeasuring` set, which suppresses side effects (659 sites in 252 files). |
| **Layout caching** | "SwiftUI automatically reuses both the results of calls into the layout and the values that the layout reads from its subviews"; a `Layout`'s cache persists, and `updateCache` is called when the subviews change [A: `Layout.makeCache`]. | A per-pass measure memo keyed partly by the view's raw bytes, which a closure or a property wrapper makes unique on every construction (§56 of the full profile: 1–12% hits outside `Text` and memoized rows). Cross-frame sizes only inside value memos and a few named containers. A custom `Layout`'s cache is made afresh for every call pair (`Layout.swift:348-352`). |
| **Drawing** | A display list built from geometry and resolved content, combined upward into a root display list, which the system asks for on the next display cycle [C: Breur 2024, Eidhof 2025]. | `FrameBuffer`s composited bottom-up. The root buffer is diffed line by line against the last frame, and the diff is written in one `write()` (`RenderCycle.md`, steps 7–11). |
| **Geometry readers** | A `GeometryReader` defines its content "as a function of its own size and coordinate space", and returns a flexible size [A]. Its content is built after layout, from known geometry. Feeding a child's size back up through state "bypasses the layout engine, which might result in a loop" [A: 2022]. | The size is exact: the space offered (`GeometryReader.swift:276-286`). The *position* is predicted, from an origin carried down where the containers translate it. Each owner (a named space, a scroll view, a list, the root) reads the markers back out of what it drew, and draws its subtree once more in the same walk when the prediction missed (`GeometryCoordinator.swift:17-41`; decisions D5G; design study A2, "G4"). |
| **Preferences, anchors** | Values flow up through the graph. A `preference` write is read by an `overlayPreferenceValue` through graph nodes in the same update [C: Breur 2024]. | A push/pop stack during the walk (`PreferenceKey.swift:199-215`). A layer reads its base's preferences and anchor markers in the same walk, since the base is drawn first. An ancestor drawn *before* the writer, such as the window reading a `.navigationTitle` or a toolbar, reads them a frame later (deviation W1). |
| **Effects** | `onAppear`'s action "completes before the first rendered frame appears" [A]. Never inside a body or a `Layout` call: after a graph update, inside the hosting view's `layout()` before drawing, or at the end of an update in SwiftUI's run-loop observer [M]. A write in `onAppear` is in the first committed frame [M]. Two re-updates run inside the layout pass, the rest of a chain in the observer, drawn next cycle; distinct `onChange`s are not limited (100 ran) [M]. An action that feeds itself runs twice per draw, then is cut off with "tried to update multiple times per frame" and the change dropped; `onGeometryChange` instead stops on a 2-cycle of duplicate values [M] (§2.3). | In walk order, mid-walk: `onAppear` and `onChange` before their content draws (`LifecycleModifier.swift:76-85`, `OnChangeModifier.swift:62-73`), `onPreferenceChange` after (`Preferences.swift:140-163`), `onGeometryChange` and scroll visibility at the frame's end but **before** it is written (`RenderLoop.swift:568`, then `writeFrame` at `:576`), `onDisappear` after it is written (`endRenderPass`, `:584`). A drawing that may be drawn again holds its effects back once a reader in it has been told a guess (lane EFFECTS). |
| **Animation, transactions** | A transaction is "a dictionary SwiftUI uses to implicitly propagate all the context for the current update", discarded at the update's end. Animatable attributes keep a model and a presentation value; built-in effects animate "without calling into any of your view code"; a custom `Animatable` view re-runs `body` and layout every frame [A: 2023]. | `withAnimation` stamps a `Transaction` that is consumed into the environment for one pass. An `Animatable` view is substituted at the point its picture has reached, as it renders (`Renderable.swift:172-207`). Animated cell runs (spinners, pulses, `.opacity` cycles) are spliced into the frame on screen without a walk (`RenderCycle.md`, "What Triggers a Frame"); every other animating subtree is walked each frame. |
| **Off-screen rows** | A lazy stack creates a row as it nears the screen and releases it a few updates after it leaves (deviation L7). | A lazy stack draws only its window. A row out of it keeps its state (deviation L7; decisions B-D5G-1). |

### 1.2 The structural difference

SwiftUI's three results are separable because each is a *function* of the one before. The layout can be
asked about anything in the graph without drawing it, and the drawing is asked for only once, at the end.
Nothing is shown until all three agree, so an update may run several times before a frame. That is how a
`GeometryReader`'s content, an effect's write and a preference read by an ancestor all settle without
anyone seeing an intermediate state.

TUI's walk has no "before the frame". Producing the root buffer *is* presenting it: the 2026-08-07
record said it as "our walk is the commit" (`Discarded render passes and redundant frames.md`, §4).
Everything TUI does that SwiftUI does not exists to compensate for that:

- **markers and corrections**, because position is known only after drawing (`GeometryCoordinator`);
- **`isMeasuring`**, because measuring is drawing that must not count;
- **`RenderWalkCheckpoint` and `EffectStage`**, because a drawing may be discarded;
- **`EffectJournal`**, because the per-frame registries (focus ring, key handlers, hit regions, drop
  targets) are rebuilt by every walk, and a memo that skips a subtree must make its registrations again;
- **"a frame late"**, for anything an ancestor needs from a descendant (toolbars, focused values).

### 1.3 What TUI has already borrowed

TUI is closer to SwiftUI than "immediate mode" suggests. The borrowings are piecemeal, and each is
bounded by the walk:

- per-body Observation tracking, scoped to the reader's identity;
- `@State` that requests a frame, and a demand-driven loop;
- SwiftUI's `Layout` protocol and `LayoutSubviews`;
- `Transaction` and `Animatable`;
- value memos (`.equatable()`, `_MemoizedRow`), which play the part of SwiftUI's skip on equal inputs;
- the per-pass measure memo, the partial counterpart of SwiftUI's layout reuse;
- the replay of animated cell runs, the counterpart of the render server animating without the main
  thread.

### 1.4 Where this has been compared before

Not systematically, but in pieces, each time for one problem:

- **2026-07, "Locating things without drawing them"**, §4 and §7. It placed reveal and windowing against
  SwiftUI, Compose, Flutter, the web and UIKit, and declined a retained view tree (7i) and a retained layout
  tree (7j). It borrowed SwiftUI's `Layout` vocabulary (7h).
- **2026-08-07, "Discarded render passes and redundant frames"**. It found TUI's walk to be the commit,
  kept `onAppear` before its content because that matches Apple's contract, and declined staging effects
  while chrome was the only thing that discarded a walk. It also declined skipping the redundant frame by
  read stamps, because the memo would need a read set per entry.
- **2026-09-23 to 2026-09-27, Option C.** This is the comparison the owner remembers, most likely. A
  memo that dies on every write above it (§4.2) was framed as "SwiftUI = dependency graph + value diffing
  of children; TUI has partial dependency tracking and no diffing, the ancestor clear standing in for
  it". A full graph was called a months-long core rewrite and not recommended. Instead, SwiftUI's own
  *contract* for `Equatable` rows was measured: trust `==` on the row's value, and keep what lies below a
  writer. Step 0, round 2 (2026-09-23, 20 paired reps, not committed elsewhere): `editor` −37.3%, `log`
  −28.4%, `scrollfollow` −35.0%, `chat` −20.2%, `inbox` −10.4%, `churn` +13.2%, `chat` +2.4 MB. The owner
  approved it on 2026-09-26. Its foundation landed on 2026-09-27 (`4dbc98081`..`6b1977c51`,
  `2eedf8321`). The drain that keeps entries below a writer and re-checks them (C4) is not on `main`:
  `RenderCycle.md`'s `@State` row still drops descendants.

---

## 2. Functional differences users can observe

Ordered by how often an app meets them.

### 2.1 Intermediate frames reach the screen

**Mechanism.** A frame is one walk followed by one write (`RenderLoop.swift:540-584`). A write to
`@State` during or after the walk asks for another frame, and the pacer draws it no sooner than one frame
interval later (`FramePacer.swift:94`). Nothing walks again before the write, except the geometry
correction (§2.4).

**What it shows.** Every effect that writes state yields one frame drawn without the write, or with it
in only some places:

| Pattern | TUI | SwiftUI |
|---|---|---|
| `onAppear { model.load() }` where an ancestor or an earlier sibling shows `model` | The earlier views show the old value for one frame, the later ones the new: a tear (2026-08-07 record, §4, "Can frame 1 tear? yes, from views walked earlier"). | Not shown: the action completes before the first rendered frame [A], the write is updated and drawn in the same layout pass, and the first committed frame shows the new state [M]. |
| Sizes collected by `onPreferenceChange`, written to `@State`, read by the layout (the "flow layout" idiom) | On the first frame, a layout with `sizes` empty; on every later change, one frame laid out from the previous sizes. | "If a view's body needs to be evaluated twice, the first body is never rendered on screen" [C: Breur 2022]; the first draw after a preference change shows the new value [M]. |
| `onGeometryChange(for:of:action:)` writing `@State` | Reported at the frame's end, before the write (`RenderLoop.swift:568`), so the frame shows the old state, and the next frame shows the new. | Action called "whenever the data type changes" [A], in the layout pass; its write is updated and drawn in the same pass [M]. A size that keeps feeding back is drawn and committed at its intermediate steps (§2.4) [M]. |
| `onChange(of:)` writing state that an earlier view read | A tear, as for `onAppear`. A later view sees the write in the same frame. | Updated before anything is drawn; no frame shows the old state [M]. |
| `@FocusedValue` read by a view drawn before its publisher | A frame late (deviation S5, decisions B34). | Readers are mostly commands and toolbar items, updated outside the view graph (S5; not measured). |
| A toolbar placed or removed by the page | The bar appears or goes one frame later; the frame between is drawn at the old reservation (deviation W1, `RenderCycle.md` "Chrome Rendering"). | Part of the same update. |

**How much it matters.** At 60 Hz on a local terminal a single stale frame is usually invisible. It is
visible on a slow link (ssh, tmux over a network), on a terminal that paints slowly, and to anyone who
reads the screen programmatically: a headless test that asserts after one frame, or a PTY smoke test. It
also costs a whole second frame, even where the first was correct. The measured population is small but
not zero: on 2026-08-07, every observed mid-walk write was on frame 1, and none recurred in steady state
(`Discarded render passes and redundant frames.md`, §5, a "weak zero" over about a dozen pages). The
idioms in the table write on every change of their input, not only on frame 1.

### 2.2 Effects run in walk order, interleaved with drawing

| Effect | TUI | SwiftUI |
|---|---|---|
| `onAppear` | Before its content draws, mid-walk. Its content sees the write in this frame; views walked earlier do not. | Before the first rendered frame [A], after the first graph update, inside the host's `layout()` [M]. A parent's before its child's; on one view, `onGeometryChange` and `onPreferenceChange` ran before it, and the `onChange` its write caused ran after the redraw [M]. Order among siblings: not measured. |
| `.task` | Started at the appearance, mid-walk. The operation runs once the main actor is free, which is after the frame. | After the first frame is committed, on the main actor, whatever its priority [M]. |
| `onChange(of:)` | Before its content draws, mid-walk, once per frame on a changed value (`OnChangeModifier.swift:62-98`). | After a graph update, never in a body: in the host's `layout()`, or at the end of an update in SwiftUI's observer [M]. Re-fired by its own writes at most twice per draw, then cut off with a warning and the change dropped; distinct chains are not limited [M]. |
| `onPreferenceChange` | After its content draws, mid-walk, once per frame on a changed *reduced* value (`Preferences.swift:140-163`). | Where `onChange` runs, with the same cut-off for a preference it feeds itself [M]. |
| `onGeometryChange`, `onScrollVisibilityChange` | At the frame's end, before the write (`RenderLoop.swift:568`): reported once, for what was finally drawn. | `onGeometryChange`: in the layout pass, its write drawn in the same pass; no count limit, stops on a 2-cycle of duplicate values [M]. `onScrollGeometryChange` reported in the first layout pass [M]. `onScrollVisibilityChange`: not measured. |
| `onDisappear` | After the frame is written (`RenderLoop.swift:584`). | After the view disappears [A, as quoted in the 2026-08-07 record]. Its timing against the commit: not measured. |

The consequences:

- **A later view sees an earlier effect's write in the same frame; an earlier view does not.** In SwiftUI
  every view sees it, in the next update before anything is shown [M]. Results are the same once things
  settle. They differ in the frame between, as in §2.1, and in what an `onChange` *further down* the same
  walk compares against: it sees the new value this frame in TUI, and in the second update in SwiftUI.
  The number of firings is the same. Whether they fall in the same frame is not.
- **`onChange` counts.** Steady-state counts match: one firing per change of the value between frames. A
  value that changes and changes back within one frame fires in neither. The known divergence was the
  corrected subtree, which fired once from the guess to the answer. Lane EFFECTS step 1 (`48d74a60c`)
  closes it.
- **Holding effects to the end of the walk, alone, makes things worse.** Lane EFFECTS tried holding every
  effect in a drawing that may be drawn again, and found that a view drawn after an `onAppear` or
  `onChange` "no longer sees what the action wrote in the same frame". A keyframe animator restarted a
  frame late (`AnimatorViewTests.keyframesInterrupted`), and a page that loads in `onAppear` would draw
  one frame empty (D5G decisions, B-D5G-4, on `lane-effects`). SwiftUI's ordering is safe only because a
  second update precedes the drawing, which the probe confirmed [M]. Taking SwiftUI's order means taking
  its re-update too (option (a), §5).

### 2.3 SwiftUI's effect ordering, measured

From [SwiftUI's update and effect ordering, measured](<SwiftUI's update and effect ordering, measured (2026-10-24).md>)
(probe `Tools/SwiftUIProbes/Effect and update ordering/`, each case run four times, on macOS 15.8.1's
SwiftUI built with Xcode 26.3; macOS 26's SwiftUI is untested). Every item is measured unless it says
otherwise:

- **Where effects run.** Never inside a body or a custom `Layout` call. They run after a graph update, from
  `Update.dispatchActions()`, in one of two places: inside the hosting view's `layout()`, before drawing;
  or at the end of an update that SwiftUI's run-loop observer runs (after a change from outside, or for the
  rest of a chain of effects).
- **A write in `onAppear` is never drawn in its old state.** The first round of effects runs before
  anything is drawn; the write is updated (bodies, layout, the `GeometryReader`) and drawn in the same
  layout pass, so the first committed frame shows the new state. A body drawn after the effect sees the new
  value in its first drawing. `onChange` and `onPreferenceChange` reacting to a write from outside are
  updated in the observer and drawn in the next display cycle with the new state.
- **Chains.** Distinct `onChange` chains have no limit: 100, each setting the next, all ran (two inside the
  layout pass, 98 in one `beforeWaiting` callout) before the next display-link callback, with no warning.
  The first commit carried an intermediate state of the chain; the next display cycle drew the last.
- **Self-feeding actions.** An `onChange(of: x)` that sets `x + 1`, and an `onPreferenceChange` that feeds
  its own preference, each ran twice per draw and were then cut off with "tried to update multiple times
  per frame". The suppressed change is dropped, not deferred; a later write from outside starts two more
  calls. "Twice per draw" is inferred from two runs consistent with it and with no other rule tried.
- **`onGeometryChange`** has no count limit (298 calls in one callout). It stops only when the value it
  would deliver repeats the one it delivered two calls before, with "Geometry action is cycling between
  duplicate values."
- **`GeometryReader`** content runs once per update, with that update's final size, never with AppKit's
  `0×0` and `∞×∞` sizing queries, nor when a `List` sizes its rows. A reader whose size feeds back through
  state goes through full updates, and their intermediate states are drawn and committed (300 points, then
  266.67).
- **`.task`** starts after the first committed frame, on the main actor, regardless of priority.
- **A `@State` write inside `body`** is lost, with "Modifying state during view update, this will cause
  undefined behavior."; no update follows and later bodies read the old value.

The questions this section was left to settle: the order within one update is parent before child for
`onAppear`, and on one view's modifier chain `onGeometryChange`, `onPreferenceChange`, then `onAppear`;
order among siblings, `onDisappear` against the commit, `onScrollVisibilityChange`, and `onGeometryChange`
in a non-local coordinate space were **not measured**, nor were animations, `Table`, `NavigationStack`,
sheets or iOS.

### 2.4 Geometry is predicted, then corrected

`frame(in:)`, `bounds(of:)`, anchors read inside the reader's own content, and `scrollTransition` are
answered *before* the content is drawn, from a carried origin. The owner of the space checks that answer
against the markers in what it drew, and draws its subtree once more in the same walk when the two
differ (decisions D5G; design study A2, G4). The results:

- **The answer users see is exact wherever an owner finds the view**, after at most one correction. The
  cost of a miss is a second drawing of the owner's subtree, or of the whole scene for a `.global` reader
  (`RenderLoop.swift:742-761`). A reader that the corrected drawing moves again is left as a residual for
  the next frame (`noteResidual`, `:760`).
- **It is not checked where the markers do not reach an owner.** That happens under a container that
  redraws its content's lines into a new buffer without their regions: a bare `FrameBuffer(lines:)` in an
  app's own `Renderable`, as in the framework (B-D5G-2). There a reader is told where the containers
  above *would* place it, and nothing checks it. SwiftUI has no such case.
- **Some containers still leave every frame they move to the correction.** `List` rows are told the
  list's origin, so a scrolled list with a reader in a row draws once more per frame (B-D5G-9). The
  root's centring, `safeAreaInset`, content margins, `TabView`, `NavigationSplitView` and `SplitView`
  cost one correction on a reader's first frame (B-D5G-10). A reader in a presented surface costs the
  scene a second walk on the frame the surface shows or moves (B-D5G-3).
- **A correction's side effects** ran for both drawings until lane EFFECTS. Its `EffectStage` now holds
  back nine kinds of effect from a drawing armed by a guess, and keeps those of the drawing that is kept.
  Still not held: what a scroll view's band redraw does for a row only the discarded band drew; and the
  registries that take a second registration as the same one (focus ring, shortcuts, status-bar items,
  drop targets), where a view only the first drawing drew stays registered for that frame
  (`RenderWalkCheckpoint.swift:43-55`).
- **SwiftUI's own failure mode here is a loop, not a miss.** A reader whose size is written to state and
  fed back into layout re-updates, and Apple warns that it "might result in a loop" [A: 2022]. Measured,
  each step is a full update whose state is drawn and committed, and the loop runs on within one turn of
  the run loop until a value repeats two steps back [M]. TUI's walk cannot loop within a frame: such a
  cycle advances one frame at a time. Both show the intermediate steps; SwiftUI's hold the main thread
  until they end.

### 2.5 A body may run more than once per frame, and a measure is speculative

A composite's body is evaluated for every measure that reaches it, and again for its drawing (§1.1). A
measure is a partial drawing with effects switched off: `isMeasuring` suppresses focus registration,
lifecycle, `onChange`, preference callbacks and hit regions, and a view that measures by drawing draws its
whole subtree (§56 of the full profile: 195 view visits to draw three menu rows, before that section's
change, 2026-09-06). Two things
follow that a SwiftUI user would not expect:

- **A body that reads something unstable can be measured with one value and drawn with another**: the
  clock, a random number, a global counter, or state written between the two evaluations. Then the size
  laid out is not the size drawn. SwiftUI evaluates the body once per update, and layout and display
  read that one value [A: 2023; C: Eidhof 2025].
- **A `print` in `body`**, a common debugging habit, prints several times per frame, and a different
  number of times at different sizes.

### 2.6 Layout reads what was drawn

Several containers place a child by its drawn size: `ZStack` aligns by rendered size, `.frame` aligns its
content from the rendered buffer, the layers by the layer's rendered size, `VStack` its cross axis by
rendered widths, and `HStack` appends by rendered width (design study A2 §3, with file:line at
`f56c419d`). So where a child's measure and its drawing disagree, the drawing wins: what is placed is what
was drawn, and `L5` holds by construction (a view never draws outside the size it reports). The cost is
the measure/render parity traps (§3.2). A measure that disagrees with the drawing shifts the *siblings*:
the stack budgeted from the measure, and the child drew something else. Examples are a `Slider`'s 19-cell
floor under `.frame(width: 10)`, `LazyVGrid` reporting twelve rows while drawing two, and an `EmptyView`
charged a spacing slot by measure but not by drawing (`Review batch, 2026-09-09, three deep dives.md`).
SwiftUI's layout cannot see a drawing, so it has none of these, and a view that draws outside its frame
simply does (L5, SwiftUI side).

### 2.7 What TUI can do that SwiftUI cannot

- **Keep a windowed row's state.** A row a lazy stack stops drawing is still in the tree. Its state
  survives, and it is reported hidden (B-D5G-1, L7). SwiftUI destroys the row. This follows from TUI
  retaining nothing per view: retaining state for an identity costs a box, not a node.
- **Draw, inspect, draw again, within one frame.** A parent can draw a subtree, read anything the drawing
  carried (markers, hit regions, animated runs, the cells actually used), and draw it again with other
  inputs before the frame is shown. The correction, a scroll view's band redraw, and a matched geometry
  effect drawn at its matched size all do this. In SwiftUI the only upward channel is a preference, and a
  preference that changes layout costs a second update. TUI's version costs a second drawing, and only
  of that subtree. In fairness, most uses of this capability make up for the missing layout phase; none
  found is a feature SwiftUI's users ask for and cannot have.
- **Hit regions and geometry markers travel with the picture.** What can be clicked is exactly what was
  drawn, through clipping, compositing, dimming (which drops them) and memoization. There is no separate
  hit-test geometry to drift.
- **A cycle cannot hang a frame.** State → layout → state advances one frame per step and is visible.
  SwiftUI cuts off an action that feeds itself after two calls per draw, but runs a chain of distinct
  actions, or a geometry feedback, to its end in one run-loop turn (100 steps, 298 calls) [M].

### 2.8 Where the semantics already match

Identity and state lifetime (a branch flip replaces its state in both), Observation granularity (per body
read, per instance), environment flow (copy-down; a sibling sees the original), preferences reduced
upward within a frame for a reader drawn after the writer, and the lazy `List`'s identifiers gathered from
the data. None of these depends on the walk.

---

## 3. Capabilities and maintainability

### 3.1 What each model makes easy or hard

| Feature | SwiftUI's model | TUI's walk |
|---|---|---|
| **Custom `Layout`** | Natural: layout is its own pass, its cache persists, and the subviews are proxies into the graph [A]. | Shipped, but each call pair makes a fresh cache (`Layout.swift:348-352`). `LayoutSubviews` is a materialised collection, which is the windowing problem in "Locating things without drawing them" §7h. Measure and draw had to be *grounded* in the same numbers by hand for parity (`Layout.swift:403-420`). |
| **Lazy containers** | Needs subgraph creation and destruction, estimated extents, and a buffer for prefetching [A: 2023, L7]. Off-screen rows lose state. | Easy and cheap: "for it creating a view is drawing it" (L7). Windowing, anchors and O(1) reveal at any size shipped ("Locating things without drawing them", §11). The hard part was making the focus ring and `scrollTo` reach rows never drawn, which neither model gets for free (§4 of that document: Flutter's retained tree has the same 500-button bug). |
| **Scroll anchoring, reveal** | `ScrollViewReader.scrollTo`, `ScrollPosition`, geometry known before drawing. | Anchor-based, locate without drawing (shipped). The one SwiftUI advantage is that `.scrollView` geometry is exact without a correction. TUI's prediction rung for the scroll view makes the common idiom exact too (design study A2, rung 2). |
| **Matched geometry** | One geometry shared by two views, resolved in layout. | The content is drawn at its own size for the footprint, then again at the matched frame's size, with a checkpoint around it (`RenderWalkCheckpoint.swift:59-63`). Works, at the price of a second drawing and the effect staging. |
| **Alignment guides** | Pure functions of `ViewDimensions` from layout. | Resolved against drawn sizes in `VStack` and `ZStack`, measured in `HStack`. Parity rather than correctness, but every new guide placement had to be checked both ways (decisions GUIDE, GUIDE3). |
| **Transitions** | The removed view's subgraph lives on while it transitions out. | The removed view's last picture and fade record are kept (`ChildFade`, `StackGlide`). Comparable effort. |
| **Geometry readers** | Exact by construction. The loop risk is the app's. | Five pieces of machinery (markers, owners, origins, rungs, correction), the effect stage on top, and forty-odd placing files that each either translate an origin or leave a correction (design study A2 §3). |
| **Chrome** | Toolbars are part of the same update. | Last frame's answer, adopted a frame late (A28, W1). The rule "chrome's height must not need the content" exists because of the walk. |
| **Memoization** | Implicit everywhere: a node is recomputed only if an input changed. | Opt-in, at value memos, with a table of sixteen invalidation sources, a registration journal and two verifiers (`RenderCycle.md`, "Subtree Memoization"). It is the most intricate part of TUI. |
| **Animation** | Built-in effects animate in the render server without code. A custom `Animatable` view runs `body` and layout every frame [A: 2023]. | Animated cell runs replay without a walk; every other animation walks its subtree each frame. Pre-rendering several phases was declined because it multiplies every side effect by the phase count (`Animating your own view efficiently.md`). |

### 3.2 The bug classes each model produces

**TUI's, recorded:**

1. **Side effects in a measure.** Persistent state written by a speculative pass: a list's scroll clamp,
   a scroll view's focus snap, `ScrollView` and `Table` clamps, lifecycle tokens, and a `ConditionalView`
   that deleted live `@State` (fixed 2026-08-03). Six instances, each the same shape, each needing an
   `!isMeasuring` guard; 659 such guards now exist. `measureFixedByRendering` makes everything under a
   button measure-reachable (`RenderCycle.md`, "What Declines the Cache"; the 2026-08 profile §12 and
   §15).
2. **Measure/render parity.** A measure written as arithmetic beside a drawing written procedurally drifts
   from it. `MeasureRenderEquivalenceTests` exists to catch this. The 2026-09-09 review found three more
   cases (`EmptyView` spacing, the stack heights, gradient offsets).
3. **Memo invalidation holes.** Something the drawing depends on that no key or note sees: data a
   `ForEach` row captured from outside its element (four instances, documented as a known hole on
   `_MemoizedRow`, `MemoizedRow.swift`), focus, hover, drags, timelines, erased types, geometry sizes.
   Each is a row of the invalidation table, found by a bug.
4. **Per-frame registry writes a served memo drops.** `.dropDestination` and `.defaultFocus` were live
   under a clean `TUIKIT_VERIFY_RENDER_MEMO` run, because the verifier compares pictures and these change
   none (`RenderCycle.md`, the drag-session paragraphs). Every widening of what may be stored makes
   pre-existing ones reachable.
5. **Writes during the walk** (§2.1): tears, and a second frame.
6. **A discarded drawing's effects.** The app header's correction (closed by A28), and the geometry
   correction (closed by lane EFFECTS).
7. **Identity roots that must agree.** The app's `@State` hydrated under one root while the scene drew
   under another, so a write cleared no memo (fixed in `657a69b7`).

Classes 1, 2, 4 and 6 exist *because* measuring, drawing and registering share one walk. Class 3 exists
because dependencies are inferred at memo boundaries rather than recorded at reads. Class 5 exists because
the walk is the commit.

**A SwiftUI-style graph's, from Apple and the community:**

1. **Update loops**: state written during an update, or a layout feeding itself back through geometry
   ("might result in a loop" [A: 2022]; "tried to update multiple times per frame" [C, M]).
2. **Unstable identity**, which loses state and breaks animation [A: 2021], and `AnyView` or variable
   per-element view counts, which force eager creation of every row [A: 2023].
3. **Over-invalidation from broad dependencies**: passing a whole model where a field would do [A: 2023].
4. **Opacity.** The graph is private; `_printChanges` is "a best-effort explanation" [A: 2023]. Lifetimes of
   graph nodes are invisible to the app.
5. **For TUI building one**: dangling or stale nodes, edges recorded on one path and missed on another,
   and a whole new class of "the graph did not know this read" bugs. That is class 3 again, moved from memo
   boundaries to every read.

### 3.3 Debugging and tests

TUI's walk is synchronous and deterministic: one call renders a frame, a breakpoint in a body shows the
whole path from the root, and a test renders and asserts in the same function. That is worth a great deal,
and the test suite (6,000-odd tests) leans on it. The costs show up in §3.2: a bug in classes 1–4 is often
invisible to a test that renders once in a fresh context. `TUIKIT_VERIFY_RENDER_MEMO`,
`TUIKIT_VERIFY_MEASURE_MEMO`, `TUIKIT_DIAGNOSE_BODY_MUTATION` and the Stress `--selfcheck` exist for that.
SwiftUI's graph is the opposite trade: the framework guarantees consistency, and the app gets no view of
why a body ran.

---

## 4. Performance

### 4.1 The budget and where TUI stands

At the default cap a frame has 16.7 ms. A 120 × 40 terminal is 4,800 cells; a large one is a few times that.
Current costs, release, 120 × 40 (`What makes a page slow to open.md`, 2026-10-12):

| | warm µs/frame | cold µs/frame |
|---|---:|---:|
| `dashboard` | 174 | 7,013 |
| `kitchensink` | 657 | 6,969 |
| `modifiers` | 961 | 44,665 |
| `textwall` | 2,298 | 10,635 |
| `gradients` | 3,883 | 40,843 |

Opening an Example page costs 17–69 ms of CPU in release, measured as each page arrives. A static screen
costs nothing, because the loop does not render. The warm steady state is therefore one to two orders of
magnitude inside the budget. The cold path, a page arriving, is where frames go over it.

### 4.2 Where the walk's time goes

- **Redundancy.** While tabbing through Example pages, 85–100% of the walk reproduced byte-identical output.
  The reusable time sat at app-level composites with no `Equatable` conformance, out of any value memo's
  reach (2026-08 profile §19, measured 2026-08-12).
- **Measuring by drawing.** Before §56's fix, a cross-frame size for buttons was bounded at −48% on `menu`,
  −31% on `paneled` and −9% on `form`. About 34 of those 48 points are still on the table, behind
  `_ButtonStyleBody`'s procedural sizing (§56, 2026-09-06).
- **A write above a memoized subtree clears it.** `clearAffected(by:)` takes descendants, so a write to data
  held above a `List` or `Table` clears every row memo beneath it. Measured on the `table-row-memo` branch,
  2026-09-21: `churn`, `scrollfollow`, `table-churn` and `table-tail` served 0 rows, against 35–38 on the
  static scenarios. A deliberately wrong build in which rows cost nothing bounded the prize at −25.5% on
  `table-churn` and −47.1% on `truncate`. `Table` has since kept composed rows on its own handler (tiers
  landed 2026-09-20/22), and Option C (§1.4) is the general answer for `ForEach` rows.
- **The environment** was about 31% of a menu frame in September (687 reads per frame), since reduced by the
  key-path and `ResolvesOwnEnvironment` work (`Performance pass after the SwiftUI API batch (2026-10).md`
  §3).

### 4.3 What a dependency graph would save, and cost

**Saves.**

- **The ancestor-write class.** Only the reader's body re-runs; its children are re-run only where their
  inputs changed. This is the one large, measured, structural cost of the walk (up to −25% to −47%,
  above).
- **Repeated body evaluation for measuring.** A graph keeps the body's value, so layout queries it without
  re-running it.
- **The correction's second drawing**, since geometry is known before drawing.

**Costs, and limits on the savings.**

- **Comparing inputs.** To skip a child, a graph must know that the child's inputs did not change. TUI
  measured that raw bytes cannot tell it: a view holding an array, an `@Environment`, an `@State`, a closure
  or `AnyView` hashes differently on every construction, and "one unstable word anywhere below poisons
  every ancestor" (2026-08 profile §25 and §56). SwiftUI compares view fields its own way [C: inferred from
  its behaviour, not documented beyond "views are value types, SwiftUI can efficiently compare them" (A:
  2021)]. A closure-holding view such as `Button` cannot be shown unchanged by any comparison. So a graph
  saves the most where the value memos already work (Equatable data), and least on the interactive rows
  where the walk spends its time.
- **Recording dependencies at every read.** An edge per environment read (687 a frame on a menu in
  September), per `@State` read, per observable read, on every frame that re-evaluates anything. TUI
  pays this today only per body (Observation), and only scope-deep.
- **Memory.** A node per attribute rather than a buffer per memo. SwiftUI's graph for an Xcode template app
  is already "very complex" in a dump [C: Breur 2024]; per-node sizes are not public.
- **Cold frames gain least.** A page arriving has no graph to reuse, and on that path TUI's profile is
  flat: the pipeline, the allocator and reference counting, with no hot spot (`What makes a page slow to
  open.md`). A graph adds node construction to exactly the frames that are over budget.
- **The retained registries.** For the savings to reach interactive views, the focus ring, key handlers,
  hit regions, drop targets and status-bar items would have to live with their nodes instead of being
  rebuilt by each walk. That is the most valuable part of a graph for maintainability (class 4 goes away),
  and the most invasive.

At terminal scale the warm savings are fractions of a millisecond on frames already well inside the budget.
The case for a graph on performance alone is weak. The case on correctness is better made by option (a),
which costs far less.

---

## 5. Options, smallest to largest

### (a) Keep the walk; converge before presenting

**Built, 2026-10-24** (steps 2 and 4; decisions B-D5G-11). Step 3 is not.

**What.** Two pieces, both built on lane EFFECTS' `EffectStage`:

1. **Re-walk before writing.** After the walk, if an effect wrote state during it or at the frame's end
   (`onGeometryChange`, scroll visibility, preference callbacks), walk again before `writeFrame`. With
   effects still mid-walk, this alone removes the stale and torn frames of §2.1. Bound it as SwiftUI does,
   which the probe found is per action, not per frame (§2.3):
   - **Per action, two per written frame.** An `onChange` or `onPreferenceChange` action that has run
     twice since the last written frame is refused a third time, its change dropped rather than deferred
     (the value is recorded as seen, so the next frame does not fire it either), with SwiftUI's warning,
     once. A later change starts the count again.
   - **No cap on distinct chains, in principle.** SwiftUI re-updates twice inside its layout pass, then
     commits and runs the rest of a chain outside it. TUI's nearest equivalent: at most two re-walks
     before writing; if effects are still writing, write the frame and let the rest of the chain continue
     a walk per frame, as today. That spreads a chain longer than three steps over frames where SwiftUI
     finishes it in one run-loop turn; it shows intermediate frames as SwiftUI's commits do, and cannot
     hold the main thread. If the count (step (1) below) finds long chains, the rest of a chain can be
     walked unwritten before the next frame instead.
   - **`onGeometryChange`: SwiftUI's duplicate-cycle rule, no count.** Keep the last two values each
     action delivered, and refuse a delivery equal to the one before last (`A → B → A`), with "Geometry
     action is cycling between duplicate values." Its writes fall under the two-re-walk bound like any
     other.
2. **Then, optionally, SwiftUI's order.** Hold every effect to the end of its walk, on the stage that
   already holds nine kinds, and run them where the probe found SwiftUI runs them: after the walk, never
   inside a body or a measure, a parent's `onAppear` before its child's (§2.3). Lane EFFECTS found that
   holding effects without a re-walk restarted a keyframe animator a frame late, and would draw a page that
   loads in `onAppear` empty for a frame. With the re-walk, that frame is never written, which is what
   SwiftUI was measured to do. `.task` needs no change: TUI's operation already runs on the main actor
   after the frame, as SwiftUI's does.

The same loop can take a toolbar placed by the page, or a focused value published after its reader:
walk again with the new reservation or value, and W1 and S5 stop being a frame late.

**Fixes.** §2.1 entirely: no tears, no first-layout flash for the preference and geometry idioms, chrome
in the same frame. §2.2's ordering becomes SwiftUI's. Headless tests see settled frames.

**Costs.** A second walk on every frame where an effect writes. The memo serves whatever the write did not
clear, so the second walk costs what the write invalidated, not a cold frame. A frame whose effect writes
*every* frame (an `onGeometryChange` writing during a scroll) doubles in cost, which is the case to measure
first (§6). It does not touch §2.4–§2.6.

**Risks.** The 2026-08-07 record listed "converge before presenting" and set it aside as "re-walking to
fixpoint, i.e. a discarded pass, unbounded". The bound is the answer to that: an effect that does not
converge used to cost a frame per step; now it costs up to two re-walks per frame, and the next frame
continues as today. An action that feeds itself is cut off as SwiftUI cuts it off. The `onAppear` ordering the 2026-08-07 record kept ("matches SwiftUI's documented
guarantee") is preserved: the action still completes before the first frame is written.

**Steps, each landable.** (1) Count: frames with a write during the walk, by cause, across the Example and
Stress (instrumentation exists). (2) The bounded re-walk, effects unmoved, with `RenderPassScopeTests`-style
tests for each idiom in §2.1, the per-action cut-off and the geometry duplicate-cycle rule, and an A/B on
the scenarios with effects. (3) Toolbars and focused values through the same loop, which retires W1 and S5.
(4) The end-of-walk order measured in §2.3, kind by kind.

**Memo interaction.** None new. A re-walk is an ordinary walk, and lane EFFECTS' checkpoint discipline
already rolls back per-walk registries. The memo makes it cheap.

**Price.** Steps 1–3: about a week with A/Bs. Step 4: about a week, since most kinds are already on the
stage. Low risk.

### (a′) Finish the prediction rungs

**What.** Convert the containers D5G left to the residual: `List` row placement (B-D5G-9, about a day),
the root's centring, `safeAreaInset`, content margins, `TabView`, `NavigationSplitView`, `SplitView`
(B-D5G-10, about a day each by the decisions' own pricing), a presentation's placement (B-D5G-3, about a
day) and a `Table` cell's origin (B-D5G-2, about half a day).

**Fixes.** Most corrections: a reader is then exact before drawing on every converted path. That is
option (b)'s geometry benefit, container by container, with no failure mode beyond "one more correction"
where a conversion is missed.

**Price.** About two weeks, each piece with its hot-path A/B. The Stress correction counter says which to
take first.

### (b) A layout pass separated from drawing

**What.** Each container computes its children's sizes and placements before drawing any of them, from
measures alone. That gives a layout tree, or origins carried everywhere, before the drawing walk. Readers
get exact geometry; there are no corrections; alignment uses measured sizes.

**Fixes.** §2.4 entirely, and the "draw to measure" share of §2.5. Removes classes 1 and 6.

**Breaks or costs.** Measure/render parity changes from a source of correction rate into a source of wrong
pictures: every one of the 263 `Renderable` conformers must answer `sizeThatFits` exactly, without
drawing, including the 18 that measure by drawing and the procedural ones `§56` declined to duplicate
("two copies of a rule drift … with wrong layout, not a crash, as the failure"). That is G3's failure mode,
which the design study rejected for geometry ("silently wrong at each one that does not [translate]").
Bodies still run twice (once for layout, once for drawing) unless their values are kept, which is option
(c). The 2026-07 "Locating" study weighed a retained layout tree (its 7j) and declined it as a ground-up
re-architecture whose benefit the caches buy incrementally.

**Steps.** Option (a′) is this option's geometry half, done safely. The rest is one container family at a
time. Make its `sizeThatFits` exact, then place its children from the measure rather than the drawing,
with `MeasureRenderEquivalenceTests` as the gate.

**Memo interaction.** The per-pass measure memo becomes load-bearing for everything, and its byte key is
the weak point (§4.3).

**Price.** Two to three months, high risk. Most of the benefit is reachable through (a′) for two weeks.

### (c) Fine-grained dependency tracking per view

**What.** Every composite identity becomes an implicit memo with a recorded dependency set (the `@State`
boxes, observable properties and environment keys its body and its descendants read) and a comparison of
its inputs from its parent. Only invalidated subtrees re-evaluate; the rest of the frame is served, its
registrations retained or replayed.

**Fixes.** The ancestor-write class (§4.2), the memo invalidation table (class 3 becomes "every read is
recorded"), and, with retained registrations, class 4.

**Breaks or costs.** The input comparison has no sound general key (§4.3), so closure-holding children
always re-run. Every per-frame registry must become incremental: the focus manager, key dispatcher, mouse
dispatcher, drag session, preference storage and status bar. A read-tracking tax on every miss, priced on
2026-08-07 as "O(reads × nesting depth), paid on every cache miss — precisely when the expensive work is
already happening" (`Discarded render passes and redundant frames.md`, §5). It overlaps and replaces the
memo machinery, so both would have to coexist through the migration.

**Steps.** The smallest useful piece is not this option. It is Option C's remaining step (§1.4): a
`ForEach` row whose value is `Equatable` survives a write above it, and is re-checked by `==` before it
is served. That is SwiftUI's own contract for such rows, it was measured at −10% to −37% on the session
shapes, and the owner has approved it. It needs no graph.

**Price.** Three to six months, high risk. The measured prize is the ancestor-write class, and Option C
reaches most of it for `Equatable` rows.

### (d) A full SwiftUI-style graph

**What.** Values, layout and drawing as nodes of one retained graph, lazily pulled, as in SwiftUI.

**Fixes.** Everything in §2.1–§2.6, and bug classes 1, 2, 4, 5 and 6.

**Breaks or costs.** A rewrite of the render pipeline, every `_*Core`, the memo, the registries and most of
the test harness (it renders synchronously and asserts). It gives up §2.7: row state survives windowing only
by keeping nodes alive, and draw-inspect-redraw goes away. It brings SwiftUI's own classes (§3.2) and its
opacity. The cold path, TUI's actual over-budget case, gets slower.

**Price.** Six to twelve months or more. Not a migration; a second framework.

### How the options combine

(a) and (a′) are independent and complementary: (a) closes what users see in time, (a′) closes what readers
are told. Option C's remaining step is the performance piece. (b) and (c) are only worth reopening if, after
these, a measured shape still pays for the walk. Each of (b), (c) and (d) contains (a)'s problem too: any
model that runs effects must decide when their writes reach the screen.

---

## 6. Recommendation

**Do not adopt SwiftUI's architecture. Adopt SwiftUI's *ordering*: effects resolved, and their writes
converged, before a frame is written.** That is option (a), on top of lane EFFECTS once it lands. Keep
closing geometry corrections container by container (a′). Take the performance case, the one place a graph
measurably wins, through Option C's remaining step (§1.4), which the owner approved on 2026-09-26.

The reasons:

1. **The functional differences that users can see come from presenting the first walk, not from the
   absence of a graph.** Every row of §2.1's table disappears once the frame is not written until effects
   have settled. SwiftUI itself gets that property from its re-update before drawing [M], not from the
   graph as such, and only for two re-updates: past them, it too commits intermediate states (§2.3).
2. **The graph's measured win is narrow, and it has a cheaper route.** At terminal scale, warm frames are
   0.2–4 ms against a 16.7 ms budget. The structural loss is the ancestor-write class. Option C adopts
   SwiftUI's contract for it, value comparison of `Equatable` rows, without SwiftUI's machinery.
3. **The walk gives TUI real capabilities and its debuggability**: off-screen state, draw-inspect-redraw,
   regions that travel with pictures, a synchronous test harness. A graph would cost these.
4. **The maintainability debt is real, and (a) does not add to it.** Bug classes 1, 2 and 4 stay. They are
   the price of the walk, and the guards and verifiers that hold them are already paid for. A graph would
   retire them, but bring a new invisible-dependency class at every read.

**What to measure first, to confirm or overturn this:**

1. **How often effects write during or at the end of the walk.** Count with
   `TUIKIT_DIAGNOSE_BODY_MUTATION` (extended to the frame-end reports), over a full
   `Tools/Smoke/tui_walk.py` sweep of the Example and every Stress scenario. This is the "weak zero" of 2026-08-07, redone. If writes are rare
   outside navigation, (a) costs nearly nothing. If some idiom writes every frame, (a) doubles those frames,
   and that idiom is the one to price.
2. **What the second walk costs on those frames.** The memo hit rate and µs of a re-walk after each kind of
   write, on `geometry`, `preferences`, `scrollfollow` and the Example's page opens.
3. **What the SwiftUI probe left out** (§2.3): `onDisappear` against the commit, sibling order,
   `onScrollVisibilityChange`, non-local geometry, and macOS 26's SwiftUI. None changes (a)'s first two
   steps; each refines step 4 for its kind.
4. **The Stress correction counter**, per container, which orders (a′).

---

## Sources (SwiftUI)

- [A] WWDC 2021, *Demystify SwiftUI* (session 10022): identity, lifetime, dependencies, `AnyView`.
  <https://developer.apple.com/videos/play/wwdc2021/10022/>
- [A] WWDC 2022, *Compose custom layouts with SwiftUI* (10056): propose, choose, place; `GeometryReader`
  feeding sizes back "might result in a loop"; `ViewThatFits`, `AnyLayout`.
  <https://developer.apple.com/videos/play/wwdc2022/10056/>
- [A] WWDC 2023, *Demystify SwiftUI performance* (10160): the update steps, dependency narrowing, IDs
  gathered eagerly, `_printChanges`. <https://developer.apple.com/videos/play/wwdc2023/10160/>
- [A] WWDC 2023, *Explore SwiftUI animation* (10156): "a long-lived dependency graph"; attributes;
  transactions; animatable attributes; custom `Animatable` re-running body and layout.
  <https://developer.apple.com/videos/play/wwdc2023/10156/>
- [A] WWDC 2023, *Discover Observation in SwiftUI* (10149): reads tracked during `body`, per instance and
  per property. <https://developer.apple.com/videos/play/wwdc2023/10149/>
- [A] Apple documentation: `Layout`, `sizeThatFits(proposal:subviews:cache:)` (several proposals per pass),
  `placeSubviews(in:proposal:subviews:cache:)`, `makeCache(subviews:)` (results of layout calls reused
  automatically), `GeometryReader` ("a function of its own size and coordinate space"),
  `onGeometryChange(for:of:action:)`, `onAppear(perform:)` ("completes before the first rendered frame
  appears"), `onChange(of:initial:_:)`. <https://developer.apple.com/documentation/swiftui/layout> and the
  pages beside it.
- [C] Rens Breur, *The SwiftUI render loop* (2022-05-09): body evaluation in a run-loop observer before
  waiting, change handlers and `onAppear` run after it and may invalidate again, a second evaluation before
  the Core Animation commit, the "tried to update multiple times per frame" cut-off. From breakpoints in the
  run loop. <https://rensbr.eu/blog/swiftui-render-loop/>
- [C] Rens Breur, *Untangling the AttributeGraph* (2024-05-28): the graph printed from AttributeGraph's own
  debug functions; dirty flags and backward, lazy updates; layout computers and child geometries; the root
  display list; subgraphs for dynamic content; repeated update cycles on insertion.
  <https://rensbr.eu/blog/swiftui-attribute-graph/>
- [C] Chris Eidhof (objc.io), *Attribute graph* (talk, 2025-07-01) and notes: dependencies rather than
  structure, layout computers producing geometry without re-running bodies, display lists as a preference,
  mark-dirty and pull-on-demand. The talk calls these "educated guesses", based on a paper on one-way constraint
  evaluation. <https://chris.eidhof.nl/presentations/attribute-graph/>,
  <https://chris.eidhof.nl/note/attribute-graph-implementations>
- [M] TUI's own SwiftUI probes, `Tools/SwiftUIProbes/Coordinate spaces and scroll visibility (D5G)/` and
  their neighbours: scroll visibility reports, `.scrollView` in viewport space, unknown names answering
  globally.
- [M] `Tools/SwiftUIProbes/Effect and update ordering/`, written up in [SwiftUI's update and effect ordering, measured](<SwiftUI's update and effect ordering, measured (2026-10-24).md>)
  (2026-10-24, macOS 15.8.1): where effects run, re-updates and their cut-offs, `GeometryReader` sizes,
  `.task`'s start, a `@State` write in `body`.

## Links (TUI)

- `Sources/TUI/TUI.docc/Articles/RenderCycle.md`: the frame's twelve steps, the memo, its
  invalidation table and the registration replay. It still says `onAppear` fires during the walk "because
  TUI uses single-pass rendering with no layout phase", which is this document's subject in one line.
- [Locating things without drawing them](<../../../Layout and scrolling/Locating things without drawing them.md>):
  §7 weighs retained trees (7i), a retained layout tree (7j) and SwiftUI's `Layout` shape (7h).
- [Geometry design study, A2 and A7](<../../Geometry design study, A2 and A7 (2026-10-04).md>): G1,
  G3, G4 and the container audit.
- [Decisions D5G](<../../../SwiftUI parity/Decisions/Layout and geometry/Coordinate spaces, geometry and scroll visibility (D5G).md>):
  B-D5G-2, -3, -4 (lane EFFECTS rewrites it), -9 and -10.
- [Discarded render passes and redundant frames](<../../../Performance/Discarded render passes and redundant frames.md>):
  the 2026-08-07 analysis of writes during the walk and of `onAppear` timing that option (a) revisits.
- [Full performance profile of Stress and the Example](<../../../Performance/Full performance profile of Stress and the Example (2026-08).md>),
  §19, §25, §56; [What makes a page slow to open](<../../../Performance/What makes a page slow to open.md>).
- [Deliberate deviations from SwiftUI](<../../../SwiftUI parity/Deliberate deviations from SwiftUI.md>): L5, L7,
  S5, W1.
- Option C's commits: `4dbc98081`..`6b1977c51` and `2eedf8321` (2026-09-27); lane EFFECTS: `48d74a60c`,
  `63e53b6c7`, `fc134b3d7`, `f94b72be4`, `fb7cb5186` on `lane-effects`.
