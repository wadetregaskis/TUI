# Mouse and Gestures

Respond to clicks, scrolling, and drags from the mouse or trackpad.

## Overview

The mouse already works. With no setup, buttons activate on a click, scroll bars drag, ``List`` and ``Table`` rows select, and ``ScrollView`` scrolls on the wheel. This page covers what you can add to your own views: gestures, context menus and raw mouse events.

Dragging one view onto another has a page of its own, <doc:DragAndDrop>, and so does copying text from the screen, <doc:SelectingText>.

## Gestures

High-level gesture modifiers cover the common cases. The two taps are a
``TapGesture`` and a ``SpatialTapGesture`` attached with `gesture` — see
SwiftUI Gestures, below, for how they rank against other gestures:

```swift
Text("Click me")
    .onTapGesture {
        // a left-click release on the view
    }

Text("Click me")
    .onTapGesture { cell in
        // the same, given the cell it landed on: cell.x, cell.y in the
        // view's own cells, or the terminal's with coordinateSpace: .global
    }

Text("Double-click me")
    .onTapGesture(count: 2) {
        // fires on the second click of a double-click
    }

content
    .onScrollGesture { direction in
        // direction is .up, .down, .left, or .right
    }

content
    .gesture(
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                // from the press on: drag.location and drag.translation give
                // the current cell and the displacement from drag.startLocation
            }
            .onEnded { drag in
                // the release
            })

content
    .onHover { isHovering in
        // true when the cursor enters the view's region, false when it leaves
    }
```

Horizontal scrolling (`.left` / `.right`) is produced by a trackpad swipe or a
shifted mouse wheel.

## SwiftUI Gestures

SwiftUI's gesture values work here, on the left mouse button. Build one, give it
its callbacks, and attach it with ``View/gesture(_:including:)``:

```swift
Text("Tap or drag")
    .gesture(TapGesture(count: 2).onEnded { open() })
    .gesture(DragGesture().onChanged { drag in move(by: drag.translation) })
```

``TapGesture``, ``SpatialTapGesture``, ``LongPressGesture`` and ``DragGesture``
behave as macOS's do, measured: a tap ends on a release over the view, a long
press is `true` from the press and ends at its minimum duration with the button
still down, and a drag starts at its minimum distance with the press as its
start. Positions are ``CellPoint``s, translations ``CellSize``s, and a drag's
velocity is a ``CellVector`` in cells per second.

A ``GestureState`` holds what a gesture is doing while it runs, and goes back
to its initial value when the gesture is over:

```swift
struct Draggable: View {
    @GestureState private var offset = CellSize(width: 0, height: 0)

    var body: some View {
        Text("Drag me")
            .offset(offset)
            .gesture(DragGesture().updating($offset) { drag, offset, _ in
                offset = drag.translation
            })
    }
}
```

When several gestures are under the pointer, the view's own come first — its
subviews', and a control's own press — and one attached with `gesture` gets the
pointer only if they fail. ``View/highPriorityGesture(_:including:)`` goes
before them and ``View/simultaneousGesture(_:including:)`` beside them, and a
``GestureMask`` turns either side off. A gesture that is still undecided holds
up the ones after it, so a double tap written inside a single tap delays the
single tap until a second click can no longer come.

A control that acts on its click — a `Button`, a `Toggle`, a picker's option,
a tab — is a recognizer too, as a plain-style button is on macOS. Released off
the control, its press fails and acts on nothing. Behind a gesture that has
not decided, it draws pressed at once and acts once that gesture gives up. A
gesture attached to it with `gesture` hears the press once it fails, so a
`DragGesture` on a button reports its end when the press is released off the
button.

A gesture has no keyboard route of its own, on macOS or here. A control keeps
its own — a `Button` attached to a gesture still activates on Return — and a
gesture on a plain view needs a key of the app's, or a terminal without mouse
reporting cannot reach it.

## Context Menus

`contextMenu(menuItems:)` attaches a pop-up of `Button`s to any view, anchored
at the click point:

```swift
Text("Right-click me")
    .contextMenu {
        Button("Duplicate") { duplicate() }
        Button("Delete", role: .destructive) { delete() }
    }
```

Selection, <kbd>Esc</kbd>, or a click outside dismisses it. A right-click that a
view does not handle bubbles to an ancestor menu, the way the wheel does.

Not every terminal will give you the right button: iTerm2 keeps it for its own
menu by default, so TUI also accepts <kbd>Ctrl</kbd>-click, and
<kbd>Shift</kbd>+<kbd>F10</kbd> opens the menu of whatever is focused.
A <kbd>Ctrl</kbd>-click is the secondary click: it never starts a text
selection, a scroll view's background passes it on to a menu around it — and
takes it as its click, focusing the scroll view, only where nothing else
does, and only if it is released inside the scroll view — and on a list's or
table's row text under `.textSelection(.enabled)` it
opens the row's menu, as a right-click there does. Where the row has none, the row takes
it as it takes one on its blank cells. A control that acts on a left press — a
button, a field, a toggle — takes it as its own click, menu or no menu: a
<kbd>Ctrl</kbd>-click on a button in a table's row presses the button, where a
right-click there opens the row's menu.

`onMenuOpen(_:)` reports the opening — of a `contextMenu` or of a ``Menu`` — to
any view above it, however the menu was opened. It exists for a specific
problem: when the app shows what was last chosen from a menu, choosing the same
item again changes nothing on screen and so reads as nothing having happened.
Clearing the display as the menu opens fixes that, and there is no other moment
to hang it on. TUI-specific; SwiftUI's menus are system-drawn, and their open
moment is not the app's to observe.

## Press-and-Hold

Pop-up menus — ``Menu``, a `.menu`-style ``Picker``, a `TextField`'s suggestion
list, and `contextMenu` — track the pointer while the button is held, the way a
Mac menu does: press to open, drag to move the highlight, release over an item
to choose it. Releasing anywhere else — the page behind, the menu's own frame, a
divider — dismisses without choosing. Once the menu is up, a press that starts on
one item and lifts on another chooses the one it *lifted* on: the press is not a
commitment.

Click-then-click works too; both gestures drive the same highlight. The two are
told apart by whether the pointer moved: a release that never left the cell it
was pressed on completes a **click**, and leaves the menu up to be picked from at
leisure. It also chooses nothing — not even when it lands squarely on an item.
The cell an opening click comes back up on is usually chrome (the trigger, or for
a `contextMenu`, anchored where you clicked, the menu's own top border), but a
drop-down with more options than fit below its control is placed *over* the
control, exactly as on a Mac, and then that cell is an item nobody aimed at.
Without both halves of the rule a quick click would open and shut the menu in one
gesture, leaving whatever happened to be under the pointer as the new value.

A pointer-opened menu deliberately starts with **nothing** highlighted, so a
release straight after the press cannot choose an item you never pointed at. The
first <kbd>↓</kbd> lands on the first item and the first <kbd>↑</kbd> on the
last.

## Raw Events

For full control, handle the raw event and return whether you consumed it.
Returning `false` lets the event keep propagating to views behind yours:

```swift
content
    .onMouseEvent { event in
        switch event.button {
        case .left where event.phase == .pressed:
            // handle a left press at event.x, event.y
            return true
        default:
            return false
        }
    }
```

Events come from the terminal's mouse reports, in the modern SGR encoding or the
legacy X10 one, and reach you as `MouseEvent` values. Each view that wants the mouse registers a hit-test region for its on-screen
rectangle; the dispatcher routes an incoming report to the front-most region
that contains the point. See <doc:RenderCycle> for where mouse dispatch sits in
the frame.

`event.x` / `event.y` are **local to the view**: `(0, 0)` is its own top-left
cell, not the screen's. That holds when the view has been scrolled partly off
the top of an enclosing `ScrollView` too — the rows above the fold are hidden,
not renumbered, so the same cell keeps the same coordinates however the page is
scrolled. Only the rows still on screen can be clicked, and each reports where
it sits in the view.

## Choosing What the Mouse Reports

An app gets clicks, scrolling and drags unless it says otherwise. To change that for the whole app, use the `mouseSupport(_:)` scene modifier:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .mouseSupport(.scrollOnly)
    }
}
```

The view modifier of the same name changes it while the app runs, for instance to hand the mouse back to the terminal for a moment.

``MouseSupport`` has four presets:

| Preset | What it enables |
|--------|-----------------|
| `.disabled` | No mouse reporting. The terminal keeps the mouse for its own text selection and links |
| `.scrollOnly` | Wheel / trackpad scrolling only |
| `.standard` | Clicks, scrolling, and drag tracking (the default) |
| `.full` | Everything, including every movement of the cursor |

A view that uses `onHover` asks for cursor movement by itself, so hover doesn't need `.full`.

## Topics

### Mouse Types

- ``MouseSupport``
- ``ScrollDirection``
- ``MouseEvent``
- ``MouseButton``
- ``MousePhase``

## See Also

- <doc:DragAndDrop>
- <doc:SelectingText>
- <doc:KeyboardShortcuts>
- <doc:FocusSystem>
