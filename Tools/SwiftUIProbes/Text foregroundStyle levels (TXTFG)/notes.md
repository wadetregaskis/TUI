# Text foregroundStyle levels (TXTFG)

2026-11-19. What a `Text`'s own `foregroundStyle(_:) -> Text` draws when it is
given a content level (`.secondary` and the rest) or a style that is neither a
colour nor a level, under each kind of style stated above it; and which of two
of a text's own styles wins. It extends the comparison stack of the 1119 probe
(`Disabled editor ink and toggle subtitles (1119)`, on the review-fixes branch
until that lands), which found a text's `.secondary` drawing a secondary red
under `.foregroundStyle(.red, .blue)`.

**Ran:** macOS 15.8.3, Xcode 26.3's `swiftc` (Swift 6.2.4), the macOS 26.2 SDK,
Aqua, drawn at 3x off-screen (`levels.swift`, `levels.out`).

**Method.** The 1119 probe's: each sample is drawn twice with the same layout,
real and with every text at opacity 0; per line of text the probe prints the
core pixel, the one farthest from the blank render's pixel under it, in 8-bit
sRGB. The calibration swatches match Apple's light-mode values.

## 1. A text's own level resolves against the style above, and only its primary

| Above the stack | `.primary` | `.secondary` | `.tertiary` | `.quaternary` | interpolated `.secondary` | `.tint` | `.foreground` |
|---|---|---|---|---|---|---|---|
| no style | #272727 | #808080 | #BDBDBD | #E6E6E6 | #808080 | #0079FF | #272727 |
| `.red` | #FF3B2F | #FF9C96 | #FFCDCA | #FFDBD9 | #FF9C96 | #0079FF | #FF3B2F |
| `(.red, .blue)` | #FF3B2F | #FF9C96 | #FFCDCA | #FFDBD9 | #FF9C96 | #0079FF | #FF3B2F |
| `(.red, .blue, .green)` | #FF3B2F | #FF9C96 | #FFCDCA | #FFDBD9 | #FF9C96 | #0079FF | #FF3B2F |
| `View.foregroundStyle(.secondary)` | #272727 | #808080 | #BDBDBD | #E6E6E6 | #808080 | #0079FF | #808080 |
| `View.foregroundStyle(.red.secondary)` | #FF9C96 | #FFCDCA | #FFE5E4 | #FFEDEB | #FFCDCA | #0079FF | #FF9C96 |
| `.tint(.green)` | #272727 | #808080 | #BDBDBD | #E6E6E6 | #808080 | #28CD3F | #272727 |

(Swatches: `.red.secondary` #FF9C97, `.red.tertiary` #FFCECB, `.red.quaternary`
#FFDCDA; `.secondary` #808080, `.tertiary` #BDBDBD, `.quaternary` #E6E6E6;
`.secondary.secondary` #808080.)

**SwiftUI (measured, macOS 15.8.3):**

- A text's own level is the style above it at that level, at macOS's label
  strengths: under `.red` the levels are `.red.secondary`, `.red.tertiary` and
  `.red.quaternary` to within a unit. With no style it is the plain level
  (#808080 …).
- A level that `foregroundStyle(_:_:)` or `(_:_:_:)` names plays no part: under
  `(.red, .blue)` and `(.red, .blue, .green)` every level is a level of red.
  (A `View`'s `.foregroundStyle(.secondary)` draws the named blue: the 1119
  probe's comparison rows.)
- The same holds for a text joined into another (`Text + Text`).
- Under a `View`'s `.foregroundStyle(.secondary)` a text's own levels are as with
  no style, `.primary` included (#272727): the style above is itself a level,
  and a text's own level replaces it rather than compounding
  (`.secondary.secondary` is #808080 too). Under a concrete `.red.secondary`
  the levels are levels of that colour (#FFCDCA is red at about a quarter).
- `.tint` and `.foreground` resolve where the text is drawn: the tint in force,
  the style in force.

## 2. Two of a text's own styles: the first written wins

| Text | Under `.foregroundStyle(.red)` and `.tint(.green)` |
|---|---|
| `.foregroundStyle(.red).foregroundStyle(.blue)` | #FF3B2F, red |
| `.foregroundStyle(.secondary).foregroundStyle(.blue)` | #7FBBFF, blue at the secondary level |
| `.foregroundStyle(.blue).foregroundStyle(.secondary)` | #0079FF, blue |
| `.foregroundStyle(.tint).foregroundStyle(.blue)` | #28CD3F, the tint |
| `.foregroundStyle(.blue).foregroundStyle(.tint)` | #0079FF, blue |

**SwiftUI (measured):** the style written first, nearest the text, wins, as a
view modifier nearer the view does; a level written first is a level of the
style written after it (#7FBBFF is `.blue.secondary`'s swatch, #7FBCFF).

## 3. Every other modifier of one kind: the first written wins

`stacked.swift` (`stacked.out`, same machine, 2026-11-19) draws `Text(s).a.b`,
`Text(s).a` and `Text(s).b` alone and says which of the two single ones the
stacked one's pixels equal.

- **The first wins** for `foregroundColor` and `foregroundStyle` in any mix
  (a gradient included, and on a `Text + Text`), `font` (`font(nil)` too: it
  is a statement), `fontWeight` (`nil` too), `bold`, `italic`, `underline`
  (its pattern and colour with it), `strikethrough`, `textScale`,
  `monospaced`, `fontDesign`, `fontWidth`, `kerning` and `tracking`; and for
  the `View` modifiers `lineLimit` and `truncationMode`, the nearer
  environment value. (`baselineOffset` drew alike both ways in this frame and
  says nothing.)
- **A bold and a weight:** a `bold` applies to the weight below it.
  `bold().fontWeight(.ultraLight)` is ultralight and
  `bold().fontWeight(.regular)` bold; `bold(false).fontWeight(.heavy)` is
  regular and `bold(false).fontWeight(.ultraLight)` ultralight; a weight first
  wins outright (`fontWeight(.ultraLight).bold()` is ultralight).
- **`fontWeight(nil)` is the font's own weight:** it wins over a weight or a
  bold written after it, and over a view's `.fontWeight(.heavy)` or `.bold()`
  above it, but `.font(.body.bold())` keeps it bold, and a `bold()` before it
  still makes it bold.
- **A level written first is a level of the style written after it,** exactly:
  `.foregroundStyle(.secondary).foregroundStyle(.blue)` draws the pixels of
  `Color.blue.secondary`, `.tertiary` of `.blue.tertiary`, and with `.tint`
  under `.tint(.green)` those of `Color.green.secondary`; with a gradient,
  those of the gradient's `.secondary`.
- **`customAttribute` keeps the last:** a renderer reads the attribute written
  last, and a whole concatenation's over a fragment's own.
- A text's own `bold()` under a view's `.fontWeight(.ultraLight)` is
  ultralight: the view's weight, the bold applying to it.

## 4. A text's own level or bold against a view's level or weight

`nested.swift` (`nested.out`, same machine, 2026-11-19, lane TXTFG-NEST): the
levels by `levels.swift`'s method, the weights by `stacked.swift`'s.

| Above the stack | `.primary` | `.secondary` | `.tertiary` | `.foreground` |
|---|---|---|---|---|
| `View.foregroundStyle(.secondary)` | #272727 | #808080 | #BDBDBD | #808080 |
| `View.foregroundStyle(.tertiary)` | #272727 | #808080 | #BDBDBD | #BDBDBD |
| `.secondary` under `.red` | #FF9C96 | #FFCDCA | #FFE5E4 | #FF9C96 |
| `.secondary` under `(.red, .blue)` | #0079FF | #7FBBFF | #BFDCFF | #0079FF |
| `.red` under `.secondary` | #FF3B2F | #FF9C96 | #FFCDCA | #FF3B2F |

**SwiftUI (measured):**

- A text's own level under a view's level **of no style** replaces it: the
  plain levels, `.primary` included, as `.secondary.secondary` is `.secondary`.
- Under a view's level **of a colour** it is a level of that level: below
  `.red`, a view's `.secondary` makes the text's `.primary` the secondary red
  and its `.secondary` red at a quarter, as `.red.secondary` above does
  (section 1); below `(.red, .blue)` the view's `.secondary` is the named blue
  and the text's levels are levels of blue.
- A **view's** level under a view's level is not the same: `VStack { Text }
  .foregroundStyle(.primary)` under `.secondary` under `.red` is red #FF3B2F,
  and its `.secondary` #FF9C96, levels of the red, not of the secondary red;
  and a view's `.foregroundStyle(.foreground)` draws the default #272727 under
  a view's `.secondary`, whatever is above.
- A text's own `bold()` keeps the view's weight for **every weight but
  `.regular`**: ultralight, thin, light, medium, semibold and heavy all draw as
  the view's weight alone; under `.regular` it is bold. `bold(false)` under
  `.ultraLight` is ultralight. A Markdown `**` and a `Text + Text` of bold
  fragments are the same as `bold()`.
- Between two view modifiers the weight wins either way:
  `VStack { Text }.bold().fontWeight(.ultraLight)` and `.fontWeight(.ultraLight)
  .bold()` are both ultralight.
- A view's `.font(.caption)` nearer than its `.fontWeight(.ultraLight)` sets the
  weight aside: a text's `bold()` there is a bold caption. A view's
  `.bold(false)` does not stop a text's own `bold()`.

## 5. The variants of section 4's three unmatched answers

`variants.swift` (`variants.out`, same machine, 2026-11-20, lane TXTFG-NEST2): the weights by `stacked.swift`'s
method, the levels by `levels.swift`'s.

**A bold and a weight.** "First" and "last" are the compared pair each line names.

| Sample | SwiftUI draws |
|---|---|
| `{ bold() }` under a view's `.medium`, `.semibold`, `.heavy` | the view's weight |
| `{ bold() }` under a view's `.regular` | bold |
| `{ bold(false) }`, `**…**`, `bold() + bold()` under `.medium` | medium |
| `VStack { Text }.bold().fontWeight(.medium)`, `.fontWeight(.medium).bold()` | medium |
| `{ fontWeight(.regular).bold() }` under `.medium` | regular (the text's own weight) |
| `{ bold() }` under `.medium` under `.regular` / under `.heavy` | medium |
| `{ bold() }` under `.regular` under `.medium` | bold |
| `{ bold() }` under `.medium` under a view's `.bold()` | **bold** |
| `{ bold() }` under a view's `.bold()` under `.medium` | medium |
| `{ bold() }` under `.medium` under `.bold(false)`; `{ bold(false) }` under `.medium` under `.bold()` | medium |
| `{ bold() }` under `.ultraLight` under a view's `.bold()` | **bold** (not ultralight) |
| `{ bold() }` under a view's `.bold()` under `.ultraLight` | ultralight |
| `{ bold() }` under `.heavy` under a view's `.bold()` | bold |
| `{ bold() }` under `.medium` under `.bold()` under `.ultraLight` | **ultralight** |
| `bold().fontWeight(.medium)`, `bold(false).fontWeight(.medium)` | medium |
| `bold().fontWeight(.semibold)` | semibold |

So a text's own `bold()` is what the nearest view `.bold()` came to against the weight in force where that bold was
stated: bold with no weight there (or regular, or heavy), that weight where it is light or medium, whatever weight is
nearer the text. With no view `.bold()`, it applies to the nearest weight, which every weight but `.regular` keeps.
Without a bold of the text's own, the nearest weight wins over a view's `.bold()` on either side of it.

**A view's level under a view's level.** The inner view's level replaces the outer one, a level of the style that
outer level was a level of:

| Outer | inner `.primary` | `.secondary` | `.tertiary` | `.quaternary` | `.foreground` |
|---|---|---|---|---|---|
| `.secondary`, `.tertiary`, `.quaternary` | #272727 | #808080 | #BDBDBD | #E6E6E6 | #272727 |
| `.red` | #FF3B2F | #FF9C96 | #FFCDCA | #FFDBD9 | #272727 |
| `.secondary` or `.tertiary` under `.red` | #FF3B2F | #FF9C96 | #FFCDCA | #FFDBD9 | #272727 |
| `.red.secondary` | #FF3B2F | #FF9C96 | #FFCDCA | #FFDBD9 | #272727 |
| `(.red, .blue)`, and `.secondary` under it | #FF3B2F | #0079FF | #0079FF | #0079FF | #272727 |
| `(.red, .blue, .green)`, and `.secondary` under it | #FF3B2F | #0079FF | #28CD3F | #28CD3F | #272727 |

A shape's level does the same: `Rectangle().fill(.primary)` under `.secondary` under `.red` is red (#FF3B30) and
`.fill(.secondary)` there the secondary red (#FF9C97). Under a `foregroundStyle(_:_:)` a level past the last one named
is that one at full strength (`.tertiary` under `(.red, .blue)` is blue, #0079FF), under a level or not.

**A view's `.foreground`.** `VStack { Text }.foregroundStyle(.foreground)` is the default foreground, #272727, under
`.red`, `.secondary`, `.secondary` under `.red`, `(.red, .blue)`, `foregroundColor(.red)` and `.tint(.green)` alike;
inside it a text's own `.secondary` and a view's `.secondary` are the plain secondary, #808080, and a shape's levels
the plain levels. It is no style at all: the style above stops there.

## TUI

**Before (main at cbbcbbfc3):** `Text` had only `foregroundStyle(_: Color) -> Text`,
which won the leading dot, so `.secondary` there was `Color.secondary`, the
palette's fixed tier, whatever was stated above (recorded by 89c231878 on the
review-fixes branch). Any other style went through `View`'s modifier and
returned `some View`.

**After (lane TXTFG):** `Text` has SwiftUI's generic
`foregroundStyle<S: ShapeStyle>(_:) -> Text` (`Sources/TUIFoundation/Views/Text+ForegroundStyle.swift`).
Section 1 matches: a level resolves where the text is drawn against the style
that text would otherwise draw in (a stated colour, a cascade's, the
environment's), not a named level; with none it is the palette's tier; a joined
text's level likewise. `.tint` and `.foreground` resolve where the text is drawn.
Not matched by lane TXTFG: under `View.foregroundStyle(.secondary)` TUI's
environment holds the style already resolved to a colour, so a text's own
`.secondary` there was that colour at half strength, a paler grey than
SwiftUI's #808080.

**After lane TXTFG-NEST (2026-11-19):** section 4's text rows match. A view's
level of no style is marked in the environment beside the colour it resolved
to (then `EnvironmentValues.bareLevelForegroundStyle`, now the `isBare` of
`EnvironmentValues.foregroundLevel`, read through `levelPrimaryForegroundStyle`
in `SemanticShapeStyles.swift`), and a text's own
level under it is the palette's tier, as with no style; under a level of a
colour, or of `foregroundStyle(_:_:)`'s named level, it is a level of that, as
before. Pinned by `TextForegroundStyleTests` (`levelUnderABareLevel`,
`levelUnderALevelOfAColour`). Not matched, and not taken on: a view's level
under a view's level still fades the inner level from the outer one (SwiftUI
takes it from the style the outer level is of; matched by lane TXTFG-NEST2,
below), and a view's `.foregroundStyle(.foreground)` is the style in force
where SwiftUI's is the default foreground.

Section 2 was not matched by lane TXTFG: TUI kept the **last** style a text
stated, so `.foregroundStyle(.red).foregroundStyle(.blue)` was blue and
`.foregroundStyle(.secondary).foregroundStyle(.blue)` plain blue.

**After lane TXTFG-ORDER (2026-11-19):** sections 2 and 3 match. A `Text`'s own
modifiers keep the first of two statements of one kind
(`Sources/TUIFoundation/Views/Text+StatementOrder.swift`; pinned by
`Tests/TUIFoundationTests/TextModifierOrderTests.swift` and
`TextForegroundStyleTests`): the foreground style, `font`, `fontWeight`,
`bold`, `italic`, `underline`, `strikethrough`, `textScale`, `lineLimit`,
`truncationMode`, and TUI's own `dim`. A level written first is a level of the
colour, tint or gradient written after it; a bold before a weight applies to it
as above; `fontWeight(nil)` is the font's own weight, over a weight or bold
after it or above it; `customAttribute` keeps the last. `monospaced`,
`fontDesign` and `monospacedDigit` change nothing in a terminal, and TUI's
`Text` has no `fontWidth`, `kerning`, `tracking` or `baselineOffset`.

Not matched by lane TXTFG-ORDER: a text's own `bold()` under a view's
`.fontWeight(.ultraLight)` drew bold and faint, where SwiftUI's is ultralight
(TUI's faint is not only a weight: `.dim()`, a caption's tier).

**After lane TXTFG-NEST (2026-11-19), bold:** section 4's light weights match.
A light weight's faint is marked as one in the style cascade
(`StyleAttributes.dimIsLightWeight`, carried with the faint attribute), and a
text under it is not bold unless its own weight says so: its own `bold()`, a
Markdown `**`, a bold fragment, and a view's `bold()` on either side of the
weight all draw faint (`Text.swift`, `applyingCascadedEmphasis` and
`concatenatedLines`). A caption's or `.dim()`'s faint still takes a bold.
Pinned by `TextModifierOrderTests.boldUnderALightWeight`. Not matched: under a
view's `.fontWeight(.medium)` SwiftUI keeps a text's `bold()` medium, which TUI
drew bold (matched by lane TXTFG-NEST2, below); and a `.font(.caption)` nearer
than a view's light weight sets the weight aside in SwiftUI (a bold caption)
where TUI keeps the weight (faint).

**After lane TXTFG-NEST2 (2026-11-20), bold:** section 5's bolds match. Medium is marked in the style cascade as a
weight a bold leaves as it is, as the light weights were (`StyleAttributes.weightIgnoresBold`), and drawn normal as
TUI draws medium (a terminal has bold, normal and faint, and medium is far nearer regular than bold); and the cascade
records what its nearest view `.bold()` came to against the weight above it (`StyleAttributes.viewBold`), which
decides a text's own bold (`StyleAttributes.emphasis(ownBold:)`, read by `applyingCascadedEmphasis` and by a
fragment's own bold in `concatenatedLines`). A text's own `bold().fontWeight(.medium)` is medium
(`Text+StatementOrder.swift`). A font's tier and weight are weights, not a view's bold. Pinned by
`TextModifierOrderTests` (`boldUnderAMediumWeight`, `viewBoldBeyondTheWeight`). Under a light weight with a view's
`.bold()` farther out, a text's own bold is now bold, not faint, as SwiftUI's is.

**After lane TXTFG-NEST2 (2026-11-20), view levels:** section 5's view levels match. A content level a view publishes
leaves a mark with what it is a level of (`EnvironmentValues.foregroundLevel`, a `ForegroundLevelMark`: the paint it
published, its base, whether it is bare), and a view's level, or a shape's, below it is a level of that base
(`levelBaseForegroundStyle`, read by `HierarchicalShapeStyle.paint(in:)`): the palette's tiers under a level of none,
red under a level of red or under `.red.secondary` (a `LevelOfAStyle`). A level no longer clears the levels
`foregroundStyle(_:_:)` named, so a `.secondary` under `.secondary` under `(.red, .blue)` is still the named blue. A
text's own level reads the same mark as before. Pinned by `SemanticShapeStyleTests.levelUnderALevel`. Not matched,
and not taken on: under `foregroundStyle(_:_:)` a level past the last one named is that one at full strength in
SwiftUI (`.tertiary` under `(.red, .blue)` is blue, #0079FF), where TUI fades it (blue at half), under a level or
not.
