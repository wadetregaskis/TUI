# Modals, Sheets, and Alerts

Present overlays — alerts, modal dialogs, and transient notifications — above
the current screen.

## Overview

TUIkit presents alerts and modals as a **centred overlay that dims the whole
screen and captures keyboard input**, no matter where in the view tree the
modifier is attached. The overlay is hosted at the root, so you can hang it off
any subtree rather than a special full-screen container. <kbd>Esc</kbd>
dismisses the presentation, and says so on the status bar while it is up — it
has to claim the key there, or a page carrying its own `⎋ back` item would eat
it and navigate out from under the dialog. A presented dialog can also be
dragged by its title or border, and is clamped to stay on screen.

## Popovers

A `sheet(isPresented:onDismiss:content:)` centres a panel over the dimmed
screen; a **popover** stays next to the thing it belongs to. It is a bordered
panel anchored to the presenting view, over a page that is *not* dimmed —
the same presentation `.contextMenu` and the `Picker` drop-down use, with your
content instead of menu rows. <kbd>Esc</kbd> closes it, and so does a click
anywhere outside it.

```swift
Button("Details") { showing = true }
    .popover(isPresented: $showing) {
        VStack(alignment: .leading) {
            Text("Ganymede").bold()
            Text("Largest moon in the solar system")
        }
    }
```

`arrowEdge` decides which side it sits on — a terminal draws no arrow, but the
edge still means something: `.bottom` (the default) puts it below the view,
`.top` above, `.leading` / `.trailing` beside. `attachmentAnchor` decides where
along that edge: `.rect(.bounds)` centres it on the view, `.rect(.rect(_:))` on
a rectangle in the view's cells (an `Anchor<CellRect>.Source`, as SwiftUI's
takes an `Anchor<CGRect>.Source`), and `.point(_:)` puts it at a unit point
within it.

## Full-screen covers

`fullScreenCover(isPresented:onDismiss:content:)` replaces the page rather than
floating over it: the content fills the area between the window's top and
bottom bars, nothing shows through, and — unlike a sheet — it cannot be dragged,
because there is nowhere for it to go.

## Sheet heights: detents

By default a sheet is as tall as its content. ``PresentationDetent`` overrides
that, applied to the sheet's **content**:

```swift
.sheet(isPresented: $showing) {
    Settings()
        .presentationDetents([.medium])
}
```

`.medium` is half the available height, `.large` all of it, `.fraction(_:)` a
share of it, and `.height(_:)` an exact number of **rows** (a terminal has no
`CGFloat`). `.custom(_:)` takes a type of your own, a
``CustomPresentationDetent``, whose `height(in:)` answers in rows from the
largest height a detent can be and the environment — or `nil`, to make the
detent unavailable:

```swift
struct BarDetent: CustomPresentationDetent {
    static func height(in context: Context) -> Int? {
        max(5, context.maxDetentValue / 4)
    }
}
```

The height goes to the sheet's own **box**. In SwiftUI a sheet is a card with
its own material, so a detent is always visible as that card; a terminal sheet
has no material of its own — the content *is* the sheet — so the outermost
container in it (``Dialog``, ``Panel``, ``Card``, `.border()`) renders exactly
that tall and encloses the slack as empty interior. Content that can fill the
space fills it as usual: a `List`, a `ScrollView`, anything with a `Spacer`
sees the detent as its available height. Content with no box has nothing to
stretch, so it keeps its own size — a detent cannot make a bare `Text` taller,
and does not try by painting blank rows under it.

A sheet with detents rests on the **bottom edge** of the content area, centred
across it, as a sheet with detents does on a phone: its height is what changes,
and the edge it grows from stays put. Unlike a sheet without detents it is not
dragged by its border — its place is the edge. On a short terminal two detents
can come to the same number of rows (`.medium` and `.height(5)` of a 10-row
content area); they are then one height.

Two more things to know. It must be the content's **outermost** modifier — the
detent is the height the content is rendered *into*, so it has to be readable
before that render happens, which is why it rides the view's type rather than a
preference. (An `if` in the sheet's builder is fine; another presentation
modifier such as ``View/interactiveDismissDisabled(_:)`` is fine either way
round. Anything else you wrap it in is not.)

### The grabber

A sheet with two detents or more opens at the smallest and has a **grabber**: a
rule across its top edge with a handle in the middle — the divider of a
``VSplitView``, between the sheet and the page — inside the detent's height. It
is a focus stop after the sheet's own controls:

| Key | Moves the sheet to |
|---|---|
| ↑ | the next larger detent |
| ↓ | the next smaller detent |
| ↖ ↘ (Home, End) | the smallest, the largest |
| ↩ or Space | the next, round to the smallest after the largest |

A mouse drags the rule, and the sheet snaps to the nearest detent as the
pointer moves. Bind `selection:` to see where the reader put it, or to move it
yourself:

```swift
@State private var detent: PresentationDetent = .medium

.sheet(isPresented: $showing) {
    Settings()
        .presentationDetents([.medium, .large], selection: $detent)
}
```

``View/presentationDragIndicator(_:)`` with `.hidden` takes the grabber away —
its rule, its focus stop and its drag together — and the binding is then the
only way the sheet changes height. A sheet with one detent has no grabber,
whatever the indicator says: there is nowhere to drag it.

The wheel over a sheet with a grabber is its content's, as the wheel is
everywhere else in a terminal app, unless the content asks otherwise with
``View/presentationContentInteraction(_:)``:

| Content interaction | The wheel over the sheet |
|---|---|
| `.automatic` | scrolls the content, and never resizes the sheet |
| `.scrolls` | scrolls the content; where it can scroll no further that way — or has nothing to scroll — moves the sheet to the next detent |
| `.resizes` | pulled down, grows the sheet first, and scrolls the content once the sheet is at its largest; pushed up, scrolls the content back first, then shrinks the sheet |

The wheel moves the sheet one detent at a time, at most one every quarter of a
second, so one turn of a wheel or flick of a trackpad does not sweep through
every detent; the ticks in between are spent on the sheet, and do not scroll
the content either. (SwiftUI's `.automatic` on a phone grows a resizable sheet
before its content scrolls; ask for `.resizes` for that order.)

### A live page beside the sheet

A detented sheet whose content says
``View/presentationBackgroundInteraction(_:)`` with `.enabled` leaves the
page behind it live. A terminal cannot draw a live page *under* a sheet —
whatever the sheet hid, Tab and the arrow keys could still reach — so the
sheet docks at the bottom of the content area and the page is laid out in the
rows above it, as the two panes of a ``VSplitView`` are:

```swift
List(notes, selection: $selected) { note in Text(note.title) }
    .sheet(isPresented: $showingDetail) {
        NoteDetail(note: selected)
            .presentationDetents([.height(8), .medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
```

- **The page is shorter.** It is laid out in the rows the sheet leaves, as a
  terminal resize would lay it out: a `GeometryReader` or
  `containerRelativeFrame` sees the shorter height, a list scrolls in it, and
  a lazy stack's rows come and go (`onAppear`, `onDisappear`) as the sheet
  changes height. On a phone the page keeps its height under the sheet.
- **The focus moves between them with Tab.** Presenting moves the focus into
  the sheet, as every sheet does; Tab and Shift-Tab carry it to the page and
  back, and a click on the page focuses what it lands on. The sheet keeps
  nothing hidden: no row of the page is ever under it.
- **Each keeps its own keys.** A `.keyboardShortcut` in the sheet fires while
  the focus is in the sheet, and the page's while it is on the page. A key
  equivalent the sheet does not bind still reaches the page's, but Return and
  Escape — the default and cancel buttons — are the sheet's alone while the
  focus is there. Escape dismisses the sheet only with the focus in it; with
  the focus on the page, Escape is the page's (a `NavigationStack` there goes
  back). An `onKeyEvent` handler is not focus-scoped, in either pane: it
  hears keys wherever the focus is, as it does beside a `.focusSection()`.
- **A modal again, when it must be.** At a detent taller than
  `.enabled(upThrough:)` allows the sheet is a modal: the page is dimmed and
  inert, and the sheet takes the focus — shrunk back, it leaves the focus
  where it is. It is a modal as well where the page would keep fewer than
  three rows or the sheet would have fewer than three, so on a short terminal
  the feature comes to an ordinary sheet; and a sheet without detents, whose
  height only its content knows, stays a modal dialog, as an undetented sheet
  covers the page on a phone.
- **The page's pop-ups open over it.** A page's drop-down, menu or tooltip
  opens over the sheet as it opens over anything else on the page.

The height the page is laid out at is known before the page is drawn — from
the sheet's detent, read as the frame begins — so moving the sheet relayouts
the page once, on the same frame. A `sheet(item:)` that opens is drawn one
frame over the page's bottom rows before the page makes room: its content is
not known until the item is.

## Alerts

Use `alert(_:isPresented:actions:message:)` for a titled alert with an
actions area and an optional message. Bind it to a `Bool` state:

```swift
struct ContentView: View {
    @State private var confirming = false

    var body: some View {
        Button("Delete") { confirming = true }
            .alert("Delete this item?", isPresented: $confirming) {
                Button("Delete", role: .destructive) { deleteItem() }
                Button("Cancel", role: .cancel) { keepItem() }
            } message: {
                Text("This action cannot be undone.")
            }
    }
}
```

An overload without the `message:` closure presents an actions-only alert. Both
accept optional `borderStyle`, `borderColor`, and `titleColor` arguments for
terminal-specific styling.

Choosing **any** action dismisses the alert, as in SwiftUI — the action closure
does not flip `isPresented` itself. <kbd>Esc</kbd> *is* the `.cancel`-role
button: it runs that action if there is one (a disabled one is skipped) and
closes the alert either way, which is why `Cancel` above has something to do.
An alert with no cancel role simply closes, and no other action is conscripted
into the job.

Each action is a separate focusable control: <kbd>Tab</kbd> moves between them
in drawn order and <kbd>Return</kbd> activates the focused one.

## Confirmation Dialogs

`confirmationDialog(_:isPresented:titleVisibility:actions:message:)` is the same
host with its buttons **stacked vertically** — an action sheet — and the
`.cancel` role sorted to the bottom. `titleVisibility: .hidden` suppresses the
title.

```swift
Button("Delete item…") { confirming = true }
    .confirmationDialog("Delete this item?", isPresented: $confirming) {
        Button("Delete", role: .destructive) { choice = "deleted" }
        Button("Cancel", role: .cancel) { choice = "cancelled" }
    } message: {
        Text("This action cannot be undone.")
    }
```

Dismissal works exactly as it does for an alert, Escape included.

## Modals and Sheets

`modal(isPresented:onDismiss:content:)` presents arbitrary content with the
same centred, screen-dimming treatment.
`sheet(isPresented:onDismiss:content:)` is a SwiftUI-compatible alias that
forwards to `modal`:

```swift
struct ContentView: View {
    @State private var showingDetails = false

    var body: some View {
        Button("Show details") { showingDetails = true }
            .sheet(isPresented: $showingDetails) {
                DetailView()
            }
    }
}
```

The optional `onDismiss:` closure runs on the presented → dismissed
transition, whatever cleared the binding — a Close button, a key press, or a
programmatic change.

### Insisting on an answer

``View/interactiveDismissDisabled(_:)`` takes away the reader's own ways out.
SwiftUI's gesture is a downward swipe; a terminal's are **Escape** and a click
outside, so those are what it suppresses — Escape stops being offered on the
status bar at all, rather than being offered and doing nothing.

```swift
.sheet(isPresented: $editing) {
    Editor()
        .interactiveDismissDisabled(hasUnsavedChanges)
}
```

Everything programmatic still closes it: a `Done` button flipping the binding,
`@Environment(\.dismiss)`, or the app clearing it once whatever the sheet was
insisting on is done. Alerts and confirmation dialogs are unaffected — Escape
there chooses the `.cancel` button, which is an answer rather than a dismissal.

As in SwiftUI, there is also an item-driven overload,
`sheet(item:onDismiss:content:)`: a non-`nil` `Identifiable` value presents
the sheet, built from the unwrapped item, and clearing the binding dismisses
it:

```swift
@State private var editing: Row?

List(rows, selection: $selection) { ... }
    .sheet(item: $editing) { row in
        EditView(row)
    }
```

The item's **id is the sheet content's identity**, which is the whole reason to
reach for this form: move the selection to another row while the sheet is up and
the editor is a *different view* — its `@State` back at its initial values, its
`onAppear`/`task` firing again — rather than the same editor handed a new row to
describe, still holding the previous row's half-typed draft. The same is true of
`fullScreenCover(item:onDismiss:content:)` and
`popover(item:attachmentAnchor:arrowEdge:content:)`.

There is also an always-on `modal { … }` overload (bound to a constant `true`)
for content that should always be presented while its host is on screen.

> Note: `popover(isPresented:attachmentAnchor:arrowEdge:content:)` and
> `fullScreenCover(isPresented:onDismiss:content:)` are both available, as is
> `presentationDetents(_:)` — see the sections above. A pop-up of *choices*
> anchored to a control is still better spelled ``Menu`` or
> `contextMenu(menuItems:)`; `.popover` is for arbitrary content.

## Notifications

Notifications are toast-style messages that appear briefly and then fade,
**without** dimming or blocking the background. Add a host where they should be
drawn with `notificationHost(width:)`, then post from anywhere — they are
delivered out of band, not declared in the view tree:

```swift
// Install the host once, near the root:
ContentView()
    .notificationHost()

// Post from anywhere, including non-view code:
NotificationService.current.post("Saved!", duration: 2.0)
```

Because the host is independent of the view that posts, a notification survives
navigation between screens.

## Topics

### Presentation

- ``PresentationDetent``
- ``PopoverAttachmentAnchor``

### Notifications

- ``NotificationService``
