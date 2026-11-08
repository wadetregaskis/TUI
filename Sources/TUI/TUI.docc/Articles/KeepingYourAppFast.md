# Keeping Your App Fast

What you can do when a screen feels slow, and how to find out which of those things it needs.

## Overview

Most apps need nothing from this page. It assumes you know how `@State` and `@Observable` cause a view to be drawn again: <doc:StateManagement> explains that. A frame of a page of ordinary controls takes a small fraction of the time between two frames, and a screen with nothing changing does no work at all. Start here when a key press feels late, an animation stutters, or a terminal over a slow link falls behind.

Then, in this order:

1. Measure, so that you change what's slow.
2. Keep each `body` cheap.
3. Wrap what doesn't change in ``View/equatable()``.
4. Give your rows a stable identity.
5. Use a lazy container for a long list.

## What a Frame Costs

A frame is drawn when something asks for one: a key, the mouse, a state change, an animation that's due. <doc:RenderCycle> has the whole pipeline. Three facts about it matter here.

**A frame walks the view tree from its root.** There's no list of what changed, kept between frames, to go to directly. What makes this affordable is the render cache, which hands back the picture a subtree drew last time if it can tell that nothing has changed.

**The cache can tell for a view of yours, by comparing what it holds, and for `.equatable()` views and `ForEach` rows, by their `==`.** Anything else draws again.

**A view of yours whose inputs didn't change doesn't run `body` again, as in SwiftUI.** A closure or a `Binding` it holds counts as changed only when something above it wrote. What the cache can't compare, an existential say (a value stored as `any SomeProtocol`, whose type is known only at run time), or a subtree with an `.onAppear` or a focused control in it, draws on every frame, usually running `body` twice: once to measure the view and once to draw it. A read nothing tracks, of a global, a plain class or the clock, stays as it was drawn: if a part of your screen goes stale, `TUI_VERIFY_RENDER_MEMO=1` names the view, and `TUI_RUN_BODY_ON_EVERY_FRAME=1`, which runs every body on every frame, shows it fresh. The fix is to keep the value where TUI can see it change: in `@State`, the environment, an `@Observable` model, or a property the parent hands the view.

## The Controls

| Control | What it does | When to use it |
|---|---|---|
| `TUI_FRAME_TRACE=file` | Writes a line per frame: how long it took, the bytes it sent, its cache hits and misses, and what caused it. | First, always: it says which frames are slow and which shouldn't have happened. |
| `TUI_DEBUG_RENDER=1` | Writes the render cache's numbers for each frame to standard error. | A frame draws far more than it should. |
| `TUI_DIAGNOSE_BODY_MUTATION=1` | Reports a `body` that changes state as it draws, with where it is in the tree. | A screen that should be idle draws frame after frame, the trace giving `state` as the cause. |
| `TUI_DIAGNOSTICS_FILE=file` | Appends TUI's diagnostics to the file, rather than standard error. | With the diagnostic above, so that its reports don't land on the screen. |
| `TUI_VERIFY_RENDER_MEMO`, `TUI_VERIFY_MEASURE_MEMO` | Draw or measure again everything the cache hands back, and report what differs. Give a path to log to. | Part of the screen is stale. Never as a fix: they cost more than the cache saves. |
| `TUI_RUN_BODY_ON_EVERY_FRAME=1` | Runs every `body` on every frame, rather than only those whose inputs changed. | To check that a stale view is reading something TUI can't see change. |
| `.equatable()` | Draws a view again only when your `==` says it changed. | A slow view the cache can't compare by itself, or one beside something that changes all the time. |
| `maxFrameRate` on your `App` | Caps the frames drawn a second. 60 unless you say otherwise. | A busy screen costs too much CPU, or too many bytes over a slow link. |

All but `TUI_RUN_BODY_ON_EVERY_FRAME` are for you, not for the people running your app. That one is also listed for them, since it's the thing to try when a screen stays out of date, and worth their telling you about if it helps. <doc:EnvironmentVariables> has every variable.

## Measure First

Measure a release build. Swift's debug builds are many times slower, and by different amounts in different code, so a debug profile can point at the wrong thing:

```sh
swift build -c release
```

Then ask what your app draws and why.

**What each frame was for.** `TUI_FRAME_TRACE` writes one tab-separated line per frame to the file you name, as it happens, so that it can be read while the app runs:

```sh
TUI_FRAME_TRACE=frames.tsv .build/release/MyApp
```

```
#frame	at_ms	ms	bytes	hits	misses	cause
1	1510	197.2	9781	0	153	launch
2	1727	54.8	183	93	33	input+state
3	1915	0.3	68	0	0	replay
```

Each line says when the frame began, how long it took, how many bytes it sent, what it found in the render cache, and what caused it, with a `+` where several things did:

| Cause | What it means |
|---|---|
| `launch` | The first frame. |
| `input` | A key, the mouse or a report from the terminal has been read since the last frame. |
| `state` | State changed. Without `input`, it was changed by a timer or a task of your app's. |
| `tick` | An animation clock ticked, and showing it took a walk of the view tree. |
| `replay` | An animation clock ticked, and the frames were written with no walk, which is the cheap way. |
| `wake` | Something asked for a frame at this instant, such as a `TimelineView`. |
| `resize` | The terminal changed size. |
| `resume` | The app was stopped, and is running again. |
| `other` | None of those, such as a report of the window's size. |

A screen that should be quiet and isn't shows up here at once, as a stream of `state`, `tick` or `wake`. A line with a large `ms` and many `misses` is a frame that drew everything.

**The render cache's own numbers.** `TUI_DEBUG_RENDER=1` writes the cache's hits, misses and stores for each frame to standard error, so send that to a file:

```sh
TUI_DEBUG_RENDER=1 .build/release/MyApp 2>render.log
```

A hit rate near zero on a page that shouldn't be changing says that something is making the cache draw everything again. <doc:RenderCycle> has more on reading it.

**A profiler.** Bodies run on the main actor, so a slow one shows up plainly on the main thread of any sampling profiler. Instruments' Time Profiler works on a terminal app, as does `perf` on Linux. Look for your own `body` getters high in the inclusive column (the time spent in a function and everything it calls). `Tools/Profiling/README.md` in TUI's repository describes how TUI profiles its own Example through a terminal, should you want to do the same.

## Debugging a Slow Screen

Put together, in order:

1. Build for release, run with `TUI_FRAME_TRACE`, and do the slow thing. Find the lines that are slow, and the ones that shouldn't be there at all.
2. **Frames nobody asked for**, a stream of `state` with no `input`, are a timer, a task or a `body` writing state. Run with `TUI_DIAGNOSE_BODY_MUTATION=1` and `TUI_DIAGNOSTICS_FILE`: a report names the view. A stream of `tick` or `wake` is an animation or a `TimelineView` that's still running.
3. **Slow frames with many `misses`** draw what they could have kept. Look for what the cache can't compare, and split it from the rest, or wrap the rest in `.equatable()`. `TUI_DEBUG_RENDER=1` shows whether that worked.
4. **Slow frames with few `misses`** are a slow `body`. A profiler names it. Move the work out of it, as below.
5. **Many `bytes`** over a slow link: lower `maxFrameRate`.
6. If a change leaves part of the screen stale, check it with `TUI_VERIFY_RENDER_MEMO=file` and `TUI_RUN_BODY_ON_EVERY_FRAME=1`. <doc:RenderCycle#Checking-What-the-Cache-Serves> has the details.

## Keep Each Body Cheap

`body` says what the view looks like. Anything slower than that belongs somewhere that doesn't run on every frame: in the action that changes the data, or in a `.task`, with the answer kept in state.

```swift
// Sorted each time this view is drawn, which may be every frame:
struct Report: View {
    let entries: [Entry]

    var body: some View {
        ForEach(entries.sorted(by: Entry.byDate)) { Row(entry: $0) }
    }
}

// Sorted when the entries change:
struct Report: View {
    let entries: [Entry]
    @State private var sorted: [Entry] = []

    var body: some View {
        ForEach(sorted) { Row(entry: $0) }
            .task(id: entries) { sorted = entries.sorted(by: Entry.byDate) }
    }
}
```

The same goes for reading a file, formatting a long string and building a large `AttributedString`. Something that takes seconds doesn't belong on the main actor at all, since while it runs no frame can be drawn and no key can be read. <doc:CustomViews> shows how to run async work from a handler.

## Wrap What Doesn't Change

The cache does this by itself for a view of yours whose fields it can compare. ``View/equatable()`` is for one it can't, or where you know better than its fields do. It tells the cache to compare this view with the one it drew last time by your `==`, and hand back the same picture if they're equal, without running `body`:

```swift
struct Header: View, Equatable {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title).bold()
            Spacer()
            Text("\(count) items")
        }
        .padding()
        .border()
    }
}

Header(title: "Inbox", count: messages.count).equatable()
```

It's worth it for a view that's slow to draw, or one that sits beside something changing all the time. It isn't worth it for one `Text`, or for a view that changes on every frame, which pays for the comparison and then draws anyway.

Two limits come up in practice:

- A view must be able to say that it's equal, which a closure can't. A view holding a `Button` won't get a synthesized `==`. Wrap the parts around the button instead, or write `==` yourself to compare what the view draws, if you can be sure the closure doesn't change anything that it draws.
- A view that reads its own `@State` directly compares as equal even when that state has changed, because `@State` is a box and what's compared is the box. Put `.equatable()` on a view that's handed its data, and keep the state above it.

A `ForEach` row whose view is `Equatable` gets this without asking, when the data above it changes: its value is built again and compared, and only the rows that differ are drawn. A row holding a `Binding` isn't compared, since the bytes of a binding don't say what its value is. <doc:RenderCycle> has the details of what can be compared.

## Give Your Rows a Stable Identity

What the framework keeps for a view, its state and its place in the cache, belongs to that view's identity. For a `ForEach` row, that's its `id`.

```swift
// Stays with the message, wherever it moves to:
ForEach(messages) { MessageRow(message: $0) }

// Belongs to the position: delete the first row, and every row below
// now has another message's state and draws again.
ForEach(messages.indices, id: \.self) { MessageRow(message: messages[$0]) }
```

An `id` that changes when the row's content changes is no better. `ForEach(lines, id: \.self)` over strings makes an edited line a different row, and the old one's state is gone with it.

For a view outside a `ForEach`, its identity is its place in the tree, and each branch of an `if` is a different place. When the two branches are the same view with a different look, say so with a value, which keeps the view's state and its place:

```swift
// Two views, so `MeterView`'s state starts again whenever `isWarning` changes:
if isWarning { MeterView(value).foregroundStyle(.red) } else { MeterView(value) }

// One view:
MeterView(value).foregroundStyle(isWarning ? .red : .primary)
```

## Use a Lazy Container for a Long List

A plain ``VStack`` draws all of its rows on every frame, however few of them show. That's fine for a few thousand rows at most.

For more than that, choose by what you need:

- **``List`` and ``Table``** are built for a lot of data. They draw only the rows that show, with a cost per key that doesn't grow with the number of rows. Reach for these first. See <doc:ListAndTable>.
- **``LazyVStack`` directly inside a ``ScrollView``** draws only the rows it can show, for when a list's look or behaviour isn't what you want. Rows that have scrolled away stay in the view tree, so it doesn't save as much as it does in SwiftUI, and one nested inside other scrolling content draws everything. See <doc:ScrollingGuide>.

```swift
ScrollView {
    LazyVStack(alignment: .leading) {
        ForEach(entries) { EntryRow(entry: $0) }
    }
}
```

## Animate Without Drawing

A built-in ``Spinner``, an indeterminate ``ProgressView`` and the breathing focus indicator don't walk the view tree as they move. They leave their frames with the run loop, which writes only the cells that change. A view of your own can do the same, and <doc:AnimatingYourOwnView> shows how.

A view that asks what time it is as it draws does the opposite: it costs a walk of the whole tree for every frame of its animation. A ``SpinnerStyle/custom(_:)`` spinner whose frames differ in width has to work this way, so its neighbours are the views that gain most from ``View/equatable()``.

## The Frame Rate

An app renders at most 60 frames a second, unless you say otherwise. That counts from the start of one frame to the start of the next, so a frame that takes 20 ms is followed straight away by the next one, if anything has asked for it. To say otherwise, give your `App` a `maxFrameRate`:

```swift
@main
struct MyApp: App {
    var maxFrameRate: Int { 30 }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

It's a cap and not a rate. A burst of changes draws one frame rather than many, and a screen with nothing changing draws nothing. Lowering it limits what a busy screen costs in CPU and in bytes, which can help over a slow link. Raising it only helps animation on a terminal and a link that can keep up.

## Topics

### Related Articles

- <doc:RenderCycle>
- <doc:EnvironmentVariables>
- <doc:AnimatingYourOwnView>
- <doc:ListAndTable>
- <doc:ScrollingGuide>
