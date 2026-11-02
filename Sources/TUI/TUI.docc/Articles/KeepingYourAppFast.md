# Keeping Your App Fast

What you can do when a screen feels slow, and how to find out which of those things it needs.

## Overview

Most apps need nothing from this page. A frame of a page of ordinary controls takes a small fraction of the time between two frames, and a screen with nothing changing does no work at all. Start here when a key press feels late, an animation stutters, or a terminal over a slow link falls behind.

Then, in this order:

1. Measure, so that you change what's slow.
2. Keep each `body` cheap.
3. Wrap what doesn't change in ``View/equatable()``.
4. Give your rows a stable identity.
5. Use a lazy container for a long list.

## What a Frame Costs

A frame is drawn when something asks for one: a key, the mouse, a state change, an animation that's due. <doc:RenderCycle> has the whole pipeline. Three facts about it matter here.

**A frame walks the view tree from its root.** There's no list of what changed, kept between frames, to go to directly. What makes this affordable is the render cache, which hands back the picture a subtree drew last time if it can tell that nothing has changed.

**The cache can tell for `.equatable()` views and for `ForEach` rows.** Anything else draws again.

**A plain view's `body` runs on every frame, usually twice: once to measure the view and once to draw it.** This is the one that surprises people coming from SwiftUI, where a `body` whose inputs didn't change doesn't run again.

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

**A profiler.** Bodies run on the main actor, so a slow one shows up plainly on the main thread of any sampling profiler. Instruments' Time Profiler works on a terminal app, as does `perf` on Linux. Look for your own `body` getters high in the inclusive column. `Tools/Profiling/README.md` in TUI's repository describes how TUI profiles its own Example through a terminal, should you want to do the same.

## Keep Each Body Cheap

`body` says what the view looks like. Anything slower than that belongs somewhere that doesn't run on every frame: in the action that changes the data, or in a `.task`, with the answer kept in state.

```swift
// Sorted on every frame, and more than once:
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

``View/equatable()`` tells the cache that it can compare this view with the one it drew last time, and hand back the same picture if they're equal, without running `body`:

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

An app renders at most 60 frames a second, unless you say otherwise. To say otherwise, give your `App` a `maxFrameRate`:

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
- <doc:AnimatingYourOwnView>
- <doc:ListAndTable>
- <doc:ScrollingGuide>
