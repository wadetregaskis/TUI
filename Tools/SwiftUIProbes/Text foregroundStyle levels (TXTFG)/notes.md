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
Not matched: under `View.foregroundStyle(.secondary)` TUI's environment holds
the style already resolved to a colour, so a text's own `.secondary` there is
that colour at half strength, a paler grey than SwiftUI's #808080.

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

Not matched: a text's own `bold()` under a view's `.fontWeight(.ultraLight)`
draws bold and faint, where SwiftUI's is ultralight (TUI's faint is not only a
weight: `.dim()`, a caption's tier); this is a text against what is above it,
not an order on one text, and is left as it was.
