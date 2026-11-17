# Sliders, selections and search

*Slider ticks and bounds read from the documentation, a wrong-typed write
through a selection's projection, when search scopes show, and where the
focus starts beside a search field. Ids: B33, B-PARITYMISC-1, B38,
SEARCH-FOCUS, STEPPER-WIDTH.*

## In short

Slider ticks, a neutral value, enabled bounds and thumb visibility follow
SwiftUI's documentation (macOS 26, unmeasured): a `╵` under the track at each
tick. A wrong-typed write through an `AnyHashable` projection is reported and
dropped. Search scopes show while the search is under way. A `Stepper`
reserves the width of its widest value (STEPPER-WIDTH, 2026-10-24). How
gauges and progress bars take a tint, gradients included, is recorded in the
commit of 2026-10-26 (`6813bad99`) and `Gradients where a colour is accepted.md`.

## For a future reader

- **B33-SUBCELL shipped 2026-10-27**: a fill-style slider's edge at its
  neutral value to a fraction of a cell (below, under B33).

## The record

### B33. Slider ticks, neutral value, enabled bounds and thumb visibility, read from the documentation

*`SliderTick`, `SliderTickBuilder`, `SliderTickContent`,
`SliderTickContentForEach`, `TupleSliderTickContent`, the three `Slider`
initialisers with `neutralValue:`/`enabledBounds:`/`ticks:`/`tick:`,
`View.sliderThumbVisibility(_:)`*

All macOS 26, so none of it was measured; what shipped follows SwiftUI's
documentation, and each reading below is a guess at the look:

- **Ticks:** a `╵` on the row under the track at each tick's value, at the
  column the knob takes for that value. Labels go on the row under that,
  centred on their marks; a label that would touch the one before it is left
  out rather than overlap. The rows exist only when there are ticks (or
  labels), and the row's other contents stay on the track's row.
- **`neutralValue:`:** the fill runs from the neutral value to the knob, on
  whichever side. For the knob and dot styles this is exact. For the fill
  styles (`.block`, `.bar`, the custom ones), the track is put together from
  whole cells of renders at the neutral value and at the value, so the edge at
  the neutral value is a whole cell. A neutral value draws the track as cells,
  never as a picture.
- **`enabledBounds:`:** every input stops at the bounds, and a value the app
  writes outside them is brought inside, as `bounds` already does. The track
  beyond them is drawn in a disabled slider's colours.
- **`currentValueLabel:`:** SwiftUI says not every style shows it. TUI's
  slider draws a numeric read-out, so a label given here replaces it.
- **`sliderThumbVisibility(.hidden)`:** the knob's cell shows the fill's end.
  On the `.marker` track, which has no fill, nothing then shows the value.

**Fuller versions:** sub-cell edges at the neutral value for the fill styles
(the ramps only grow rightward, so a leftward edge needs mirrored glyphs most
fonts lack); and a measured look once a macOS 26 machine is available.

**Sub-cell edges shipped (lane SUBCELL, 2026-10-27; B33-SUBCELL, option 2,
settled 2026-10-18).** The fill's start is a step within a cell for a style
that can draw it: a ramp from the left of a full block over a solid track, in
plain opaque colours. That is `.blockFine`, and a custom style like it. The
cell is drawn as its complement, with no mirrored glyph needed: the ramp glyph
covers the cell's empty left part, in the track's colour, over the fill's
colour as the cell's field (`TrackRenderer.MirroredEdge`). Above the neutral
value that is the cell the neutral value falls in. Below it, it is the
value's cell, and the end at the neutral value keeps the ramp's own step. Any
other style keeps the whole-cell start. The PTY check the ruling asked for
(`Tools/TerminalProbes/mirrored_ramp_card.py`, the survey's "A fill that
starts within a cell") found clean edges on iTerm2 and Ghostty. On Apple
Terminal the edge matches the ramp TUI already draws: the glyph falls short of
the line height, in mirror image. The tests are `TrackNeutralEdgeTests`.

### B-PARITYMISC-1. A wrong-typed write through an AnyHashable projection is reported and dropped

*`Binding.init(_:)` where `Value == AnyHashable`*

SwiftUI force-casts the written value to the base binding's type, so writing
a value of another type traps (measured 2026-10-18; `AnyHashable(Int8(7))`
into a projection of a `Binding<Int>`).

**Shipped:** the write goes through `SoftTrap`: a debug build stops there, as
SwiftUI's trap would, and a release build drops it and reports it once, the
base keeping its value (Deliberate deviations S7). It is the framework's
standing answer to a programming error with a safe fallback.

**The fuller version** would be SwiftUI's trap, exactly: one line (`as!`), and
the price is a crash in someone's terminal for a mistake a debug build already
stops at. Not recommended.

### B38. Search scopes show while the search is under way, by a terminal's reading of "presented" and "cancelled"

*`View.searchScopes(_:scopes:)`, `View.searchScopes(_:activation:_:)`,
`SearchScopeActivation`*

SwiftUI shows the scope bar "when SwiftUI presents search" (macOS) or "when
someone enters text" (iOS), and hides it "when someone cancels the search".
On macOS the search field lives in a toolbar and is presented by clicking it.
Here it is always on screen at the top of the searchable subtree.

**Shipped:** presented is the field holding the focus, as `isSearching` already
was; cancelled is `dismissSearch` (or `isPresented = false`), or leaving the
field with nothing typed. So under `.onSearchPresentation` and `.automatic`
(macOS's default) the scopes show while the field has the focus or the query
is not empty; under `.onTextEntry`, while the query is not empty. Under both
they stay while the focus is in them, or Tab from the field would hide the
picker it was heading for.

**The alternative** is to show the scopes whenever the field is on screen,
since a terminal's field is never hidden. That reads well for a dedicated
search page but makes `.onTextEntry` meaningless, so it would have to be a
TUI-only activation rather than a reading of SwiftUI's.

### SEARCH-FOCUS. A search field is not where the focus starts (2026-11-15)

*`View.searchable(text:placement:prompt:)` and its siblings, `AutomaticFocusDeclining`*

The focus manager gave the first focus to the first control drawn, and a
search field is drawn above the content, so every searchable page opened with
the keys in its field: the arrows, Return and an app's `onKeyPress` chords
typed into it until Tab took the focus out (tuitree's M3 feedback, item 3).

**Measured** with SwiftUI on macOS 15.8.3 (`Tools/SwiftUIProbes/Search field
focus and Escape/`, a `WindowGroup` whose `NavigationStack` content is
`.searchable`, its field in the toolbar): a window whose content is a `List`
or a `Table` opens with that view the first responder; one whose content has
nothing focusable opens with the window itself first responder, no view
focused. Never the search field.

**Shipped:** the search field declines the focus the manager chooses by
itself while anything else can take it — the first registrant's, and the
first-focusable fallback at a frame's end — so the content's first control
takes it, as on macOS. ⌃F (Find) puts the keys in the field, as ⌘F does
there; `.searchFocused`, `.defaultFocus`, `isPresented:`, Tab and a neighbour
leaving still focus it.

**Not matched:** where the content has nothing to focus, macOS opens with no
view focused, and the person clicks the field. A terminal has no pointer to
count on, and a page of results with the keys going nowhere is a page that
does nothing until ⌃F or Tab, so the field takes the focus there, as every
searchable did before. A SwiftUI program behaves no differently for it: only
the keys that would have done nothing reach the field.

**Owner's ruling (2026-11-17):** approved, together with Escape handing the
keyboard to the content (where macOS focuses no view). Both are recorded in
`Deliberate deviations from SwiftUI.md`.

**A document opened after launch** (2026-11-15, tuitree's M4 feedback, item
1): a `DocumentGroup` draws a document opened through `openDocument(at:)` or
Open… in its window in place of the last one, under a new identity, so every
control of the last one leaves the screen in the frame that draws it. The
focused one's focus went to its neighbour (`FocusManager.recoveryTarget(after:)`),
found where it stood among last frame's controls: with none of them left, that
is the top of the new content, its search field. On macOS each document is a
window of its own, which opens as any window does, on its `List` or `Table`.
So `DocumentWindow` now tells the focus manager when a document replaces the
last one (`FocusManager.chooseFocusAfresh()`), and the end of that frame
chooses a dropped focus as for a window's first content — the content's
`.defaultFocus`, else its first control that takes the focus by itself — and
not by the neighbour walk. A focus outside the content (none, today) is left
alone, as is any later frame's.

**Escape** (the same probe, the same day): in macOS's search field, with text
or empty, Escape empties it, ends the search (`isSearching` false) and takes
the focus out of it, to no view. TUI's field did nothing with it. It now ends
the search as `dismissSearch` does: the field empties and the keyboard goes
to the content, past the scopes, rather than to nothing.

