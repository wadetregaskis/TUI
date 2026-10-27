# Sliders, selections and search

*Slider ticks and bounds read from the documentation, a wrong-typed write
through a selection's projection, and when search scopes show. Ids: B33,
B-PARITYMISC-1, B38, STEPPER-WIDTH.*

## In short

Slider ticks, a neutral value, enabled bounds and thumb visibility follow
SwiftUI's documentation (macOS 26, unmeasured): a `╵` under the track at each
tick. A wrong-typed write through an `AnyHashable` projection is reported and
dropped. Search scopes show while the search is under way. A `Stepper`
reserves the width of its widest value (STEPPER-WIDTH, 2026-10-24). How
gauges and progress bars take a tint, gradients included, is recorded in the
commit of 2026-10-26 (`6813bad99`) and `Gradients where a colour is accepted.md`.

## For a future reader

- **B33-SUBCELL is owed**: a fill-style slider's edge at its neutral value to a
  fraction of a cell, after a PTY check shows clean edges (settled 2026-10-18).

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
