# Scrolling

Scroll content that doesn't fit, jump to a place from your code, and choose how scroll bars look.

## Overview

You'll start with a plain ``ScrollView``, then move it from code, and finish with its scroll bars.

```swift
struct LogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(1...200, id: \.self) { line in
                    Text("Line \(line)")
                }
            }
        }
    }
}
```

A scroll view takes the space it's given and shows as much of its content as fits. When the content doesn't fit, a scroll bar appears, and people can scroll it in the ways they'd expect:

| Input | What it does |
|---|---|
| Up and Down | One row |
| Page Up and Page Down | One screenful |
| Home and End | The very top and bottom |
| Mouse wheel | Three rows at a time, wherever the keyboard is |
| Clicking the scroll bar | A screenful towards the click |
| Dragging the scroll bar's thumb | Follows the mouse |

The keys work while the scroll view has the keyboard, so press Tab to reach it if another control has it. A scroll view whose content fits is skipped by Tab, since there's nothing to scroll.

Scrolling moves whole rows and columns. There's no momentum and no bounce.

## Scrolling sideways, or both ways

Give the scroll view the directions you want:

```swift
ScrollView(.horizontal) {
    Text("A long line that needs more room than it has, so that you scroll sideways to read it.")
        .fixedSize()
}
```

Use `[.horizontal, .vertical]` for both, and Left and Right will scroll too. A mouse wheel scrolls sideways with a sideways swipe on a trackpad, or with Shift held down in terminals that pass that on.

## Long content

A plain ``VStack`` inside a scroll view draws all of its rows on every frame, which is fine for a few thousand of them at most. For more, use a ``LazyVStack``, which draws only the rows that show:

```swift
ScrollView {
    LazyVStack(alignment: .leading) {
        ForEach(rows) { row in
            Text(row.name)
        }
    }
}
```

If people will select rows or act on them, use a ``List`` instead, which is built for that. See <doc:ListAndTable>.

## Jumping to a place from code

Wrap the scroll view in a ``ScrollViewReader`` to get a proxy that can scroll to any row by its id:

```swift
struct Chapters: View {
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading) {
                HStack {
                    Button("Top") { proxy.scrollTo(1, anchor: .top) }
                    Button("Middle") {
                        withAnimation { proxy.scrollTo(25, anchor: .center) }
                    }
                    Button("Bottom") { proxy.scrollTo(50, anchor: .bottom) }
                }
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(1...50, id: \.self) { line in
                            Text("Line \(line)")
                        }
                    }
                }
            }
        }
    }
}
```

- The id is the one that `ForEach` uses for the row. Here, that's the number itself.
- The anchor says where the row lands: `.top`, `.center` or `.bottom`. With no anchor, the view moves just far enough to show the row, and doesn't move at all if it's already showing.
- Inside `withAnimation`, the view glides to the row, a line at a time.
- An id that doesn't exist does nothing.

## Keeping the position in state

When you also want to know where the view is, hold a ``ScrollPosition`` in your state. Writing to it scrolls the view. Reading it tells you which row is at the top, even after people scroll for themselves.

```swift
struct Pages: View {
    @State private var position = ScrollPosition(idType: Int.self)

    private var topRow: String {
        position.viewID(type: Int.self).map(String.init) ?? "none"
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("Start") { position.scrollTo(edge: .top) }
                Button("End") { position.scrollTo(edge: .bottom) }
                Button("Line 30") { position.scrollTo(id: 30, anchor: .top) }
            }
            Text("Top line: \(topRow)")
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(1...50, id: \.self) { line in
                        Text("Line \(line)")
                    }
                }
            }
            .scrollPosition($position)
        }
    }
}
```

To only deal with the row's id, bind that directly: `.scrollPosition(id: $topRow)` with `@State private var topRow: Int?`.

## Following new content

For a log or a chat, where new lines arrive at the bottom, anchor the scroll view there. It opens at the end and stays at the end as lines are added. If someone scrolls up to read, it stays where they put it, and follows again once they return to the bottom.

```swift
ScrollView {
    LazyVStack(alignment: .leading) {
        ForEach(rows) { row in
            Text(row.name)
        }
    }
}
.defaultScrollAnchor(.bottom)
```

Content too short to fill the view sits at the bottom too, and grows upwards, like a chat. For a log that starts at the top instead, state only the two roles you want:

```swift
ScrollView {
    LazyVStack(alignment: .leading) {
        ForEach(rows) { row in
            Text(row.name)
        }
    }
}
.defaultScrollAnchor(.bottom, for: .initialOffset)
.defaultScrollAnchor(.bottom, for: .sizeChanges)
```

## Scroll bars

A scroll bar shows up whenever the content overflows, and it takes up one column of the view, so your content has that much less to work with. Unlike on a Mac, it doesn't float over the content or fade away.

To change whether it's there:

```swift
ScrollView { content }
    .scrollIndicators(.hidden)     // never shown, but it still scrolls
```

`.visible` keeps it showing even when nothing overflows, and `.automatic` is the default.

To say how much is hidden rather than show where you are, use text instead of a bar. It works on the vertical axis of a scroll view, and on lists and tables:

```swift
ScrollView { content }
    .scrollIndicatorStyle(.text)   // "35 more lines below"
```

Both of these apply to every scrolling view inside the one you write them on, so writing them once at the top of your app changes them all.

## Advanced

**The look of the bar.** ``View/scrollbarArrows(_:)`` chooses `.none`, `.single` or `.double` end arrows. ``View/scrollbarProportionalThumb(_:)`` chooses between a thumb that shows the visible share, and a thumb one cell long. ``View/scrollbarWidth(_:)`` and ``View/scrollbarSpacing(_:)`` set its width and the gap before it, and ``View/scrollbarClickBehavior(_:)`` with `.jump` makes a click on its track jump to that place.

**Snapping.** ``View/scrollTargetBehavior(_:)`` with `.paging` scrolls a screenful at a time. With `.viewAligned` and ``View/scrollTargetLayout(isEnabled:)`` on the stack, it stops at the edges of rows.

**Reacting to scrolling.** ``View/onScrollGeometryChange(for:of:action:)`` tells you when the offset or content size changes, to dim a header or load more rows, say.

**Staying out of the way.** ``View/safeAreaInset(edge:alignment:spacing:content:)-(VerticalEdge,_,_,_)`` adds a line that stays put, with the rows scrolling above it. ``View/scrollDisabled(_:)`` stops the view scrolling, while its content still works.

**Gliding keys.** ``View/scrollKeyboardAnimation(_:)`` makes Page Up, Page Down, Home and End glide rather than jump.

## See Also

- <doc:ListAndTable>
- <doc:LayoutSystem>
- <doc:MouseAndGestures>
