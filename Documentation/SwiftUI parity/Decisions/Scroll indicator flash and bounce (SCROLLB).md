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
