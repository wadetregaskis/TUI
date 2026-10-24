# Scroll indicator flash and bounce: decisions from lane SCROLLB

*Lane SCROLLB, 2026-10-13, shipped decisions B27 (a phase change's velocity
is (0, 0)), B28 (`scrollIndicatorsFlash` flashes) and B31 (a sprung bounce
under `.always`), and the top-row hold's follow-ups from the SCROLLANCHOR
review (recorded in [Scroll anchoring default (SCROLLANCHOR).md](<Scroll anchoring default (SCROLLANCHOR).md>)).
The calls below are the ones the owner's rulings left open. The format is
that of the main decisions file:*

- **A-SCROLLB-n — needs your decision.**
- **B-SCROLLB-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-SCROLLB-n — declined.** With the reason.

## B. Shipped the safe option

### B-SCROLLB-1. A flash peaks one hover step past a focused bar's breath

*`View.scrollIndicatorsFlash(onAppear:)`, `View.scrollIndicatorsFlash(trigger:)`*

The ruling asks for the bar's focus pulse for about half a second, with a
distinct peak within the focus and selection colour rules. A focused bar
already breathes between the accent and its lift (`ScrollbarColors.pulseLift`),
so a flash that only reached the lift would not be told from the breath.

**Shipped:** the thumb and arrows — or the "N more" lines — go from where they
rest to one `Palette.hoveredForeground` step past the breath's far end, the
step the pointer's own lift takes, so the flash stays in the focus identity's
colour and on the palette (no new hue). Where that step has no room (it lands
within the chrome pulse floor of the lift), the peak is the lift itself, which
an unfocused bar's resting grey still rises to. The lines use the same peak,
spent over the surface they sit on, so a bar and its lines flash alike. The
shape is ten 50 ms steps (three 1/60 s ticks each): ½, then full for five,
then down a fifth a step. Drawn still: the breath's runs would replay over it
from their first tick.

**The fuller version** would put the flash peak in the generated row-fill
tables (`Tools/RowFillValues`), checked by the colour rules' verifier at every
depth for every shipped palette, as the focus and selection colours are: half a
day, and only worth it if a palette's flash turns out hard to see.

### B-SCROLLB-2. The bounce is two lines, one in a view under eight lines tall, per end

*`ScrollBounceBehavior.always`, `View.scrollBounceBehavior(_:axes:)`*

The ruling gives `.always` a sprung allowance of one or two lines.

**Shipped:** two lines; one in a view whose content area is under eight lines,
so a push never hides more than a quarter of a small view. The allowance is per
end: an end the app gave an allowance (`.scrollOverscroll`) keeps it, and its
push stays where it was put; an end it gave none springs. A pushed bounce is
held while the steps keep coming and springs back one line a 50 ms frame once
they have been quiet for 250 ms (B27's quiet, `ScrollPhase.quietNanos`), so a
two-line push is gone in two frames.

**The fuller version** would let the app size the bounce — say a
`.scrollOverscroll` spelling for a sprung allowance. No SwiftUI spelling asks
for one; an hour if a port wants it.

### B-SCROLLB-3. An arrow or page key at the end pushes the bounce, as the wheel does

*`ScrollBounceBehavior.always`*

Every user step past an end takes one path (`userScrollFine`): the wheel, a
scroll view's arrow and page keys (and the focus section's scroll fallback),
the scrollbar's arrows. A focused `List`'s or `Table`'s arrow and page keys
move its cursor and never reach it, so they push nothing there. It is what makes a step that only
reaches the edge a graze and the next one a push (§1.3 of `Scroll
anchoring.md`), and an allowance the app asks for has always been pushed by a
key as by the wheel. SwiftUI's keyboard scrolling does not rubber-band on macOS
(unmeasured; the lane's review says so), and nor does a mouse wheel there: its
bounce is a trackpad's.

**Shipped:** the sprung allowance is an allowance like the others, so a key
pushes it too, and it springs back as a wheel's push does. A key at the end
shows the end, briefly, rather than doing nothing.

**The fuller version** pushes the bounce under the wheel only: the step's
source passed down to `userScrollFine` from its callers (the wheel, the key
handlers, the scrollbar's arrows and page track, the "N more" lines), and a
key's step left to graze the sprung end. An hour or two; the two allowances
would then answer different inputs, which is why it was not the default.
