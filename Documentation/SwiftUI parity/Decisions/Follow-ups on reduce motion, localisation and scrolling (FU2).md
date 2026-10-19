# Completing the SwiftUI API: decisions from lane FU2

*Lane FU2 followed up landed lanes: reduce motion as spatial motion (owner
decision A-D3M-1), A14's lookup order (owner decision, 2026-10-05), the scroll
lane's third review and the misc2 lane's second. This file holds the judgement
calls the work reached that those decisions did not already settle, in the
format of [`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):*

- **A-FU2-n — needs your decision.** Nothing has shipped for these.
- **B-FU2-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-FU2-n — declined.** With the reason.

## B. Shipped the safe option

### B-FU2-1. A language TUIkit does not ship is read only as far as the first it does

*`LocalizationService` (A14)*

**Shipped:** the languages a key is looked up in are the environment's list up
to and including the first language TUIkit ships (`currentLanguage`), then
English: `LANG=pt_BR` reads `pt`, then `en`; `LANGUAGE=pt:es` reads `pt`, `es`,
`en`; `LANGUAGE=fi:pt` with no shipped language reads `fi`, `pt`, `en`. A
language chosen with `setLanguage(_:)`, or stored by it, is read alone before
English. `currentLanguage` stays one of TUIkit's seven, so its public type does
not change, and the app's `Localizable` is read in the user's own language
first — for TUIkit's words only where TUIkit has none of them.

**The fuller version** is Foundation's own matching: a bundle's
`preferredLocalizations` against the whole of the user's list, per table, so an
app shipping `pt` under a `de:pt` user still reads German for the keys it has in
German and Portuguese for the rest only where German has none. A public way to
choose a language TUIkit does not ship (`setLanguage` takes a `Language`) would
come with it. About half a day; nothing in the tree needs it yet.

### B-FU2-2. A two-axis pager's container leaves out a horizontal bar only when it is `.visible`

*`containerRelativeFrame` inside `ScrollView([.horizontal, .vertical])` under a
scroll target behaviour (scroll lane review 3, item 2)*

**Shipped:** the container takes the horizontal bar's row off where the bar is
known before anything is measured — `.visible`, which is always drawn — so a
container-sized page is the page `.paging` steps. Under `.automatic` the bar
comes with overflow, which is decided by measuring the content after its
container is published, so such a pager's container-sized pages are a row
taller than the step and drift by it at each stop; the container's doc and the
compatibility doc say so, and how to avoid it.

**The fuller version** decides the automatic bar first: measure the content's
width at the unreserved container (a second measure for a two-axis pager, the
only view that pays), or take the bar from the frame before (no measure, one
frame of drift when the bar first appears). About two hours with tests.

**Done 2026-10-19 (lane SCROLL), the first way.** A view under a scroll target
behaviour that scrolls across, with an `.automatic` horizontal bar, measures
its content's width at the whole viewport before it publishes the container
(`_ScrollViewCore.horizontalBarDecidedFirst`), in a measure generation keyed
by the container's height, as the text-style pager's overflow probe is; wider,
and the bar's row comes off the container and the bar rounds start with it.
So a two-axis pager's container-sized pages are the step, and a horizontal
pager's container-sized cards end above the bar instead of under it. Content
that fits the whole width and overflows only once a vertical bar takes its
column is left to the rounds, as before. The frame before was not used: a
frame would then depend on its history, which the memo verifiers and the
selfcheck compare against a fresh render. Views with no behaviour keep the
old container (decisions SCROLL B-SCROLL-2).

## C. Declined

### C-FU2-1. Reduce motion does not hold still an app's own animations

*`EnvironmentValues.accessibilityReduceMotion` (A-D3M-1)*

Reduce motion holds still the movement TUIkit's own modifiers make — an
animated offset, position, padding or fixed frame, a visual effect's offset, a
drag preview's lift and fly-back. An `Animatable` view of the app's own, a
keyframe animator's tracks and a custom `Layout`'s data animate as before:
TUIkit cannot tell which of an app's numbers are positions, and SwiftUI leaves
them to the app too, which reads `\.accessibilityReduceMotion`.
