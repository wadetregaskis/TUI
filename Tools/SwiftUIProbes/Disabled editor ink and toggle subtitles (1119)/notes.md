# Disabled editor ink and toggle subtitles (1119)

2026-11-19. Two questions the owner asked be measured before deciding TUI's
behaviour: does `.disabled(true)` fade a `TextEditor`'s text, and what colour
does a `Toggle`'s subtitle take under a stated `.foregroundStyle`? No TUI
behaviour was changed; this records SwiftUI's answer and TUI's, for the owner.

**Ran:** macOS 15.8.3 (24H241), Xcode 26.3's `swiftc` (Swift 6.2.4), the macOS
26.2 SDK, Aqua, drawn at 3x off-screen (`ink.swift`, `ink.out`). The output was
the same byte for byte on a second run.

**Method.** Each sample is drawn twice with the same layout: the real one and a
blank one (the editor's text empty, the toggle's label views at opacity 0). Only
pixels that differ belong to the text, so chrome and a grouped form's section
background drop out. Per text line the probe prints the core pixel: the one
farthest from the blank render's pixel under it, in 8-bit sRGB. The calibration
swatches match Apple's published light-mode values (`.red` #FF3B30, `.blue`
#007AFF, `.secondary` #808080, `.tertiary` #BDBDBD), so the numbers are sRGB as
stated.

## 1. A disabled TextEditor

| Sample | Enabled | Disabled |
|---|---|---|
| `TextEditor(text:)`, default ink | #000000 | #000000 |
| `TextEditor(text:)` `.foregroundStyle(.red)` | #FF3B30 | #FF3B30 |
| `TextEditor(text: Binding<AttributedString>, selection:)`, red run | not run | not run |
| *for comparison:* `TextField`, default ink | #262626 | #A7A7A7 |
| *for comparison:* `TextField` `.foregroundStyle(.red)` | #FF3B30 | #FF847D |
| *for comparison:* `Text(AttributedString)`, red run | #FF3B2F | #FF3B2F |

**SwiftUI (measured, macOS 15.8.3):** `.disabled(true)` leaves a TextEditor's
text exactly as it was. The default ink and a stated red draw the same pixels
(the same count, 2047 and 2079), and the `NSTextView`'s `textColor` and its
storage's foreground attribute are unchanged (`textColor` catalog colour, and
sRGB 1.000 0.231 0.188). The modifier is in force all the same: a hit test at the
editor's centre reaches the `PlatformTextView` when enabled and the hosting view
when disabled, so a click no longer reaches the text. (The text view still says
`isEditable=true` and still takes `makeFirstResponder` when asked from code.) A
`TextField` does fade: grey to #A7A7A7, red to #FF847D, a lighter red, not a grey.
A `Text` does not fade at all.

**The attributed editor is unmeasured on 15.** Its initialiser is macOS 26 API.
The probe compiles it against the 26.2 SDK behind `if #available(macOS 26, *)`,
but this Mac runs 15.8.3, so that branch printed "unavailable before macOS 26,
not run". Nothing here says what macOS 26 does with a run's own colour.
*Hypothesis:* the plain editor is the same `NSTextView` path, and it changes no
colour, so a run's colour probably stays too. Rerun `ink.swift` on macOS 26 to
settle it. The branch is already there.

**TUI (source at 77894861f):** a disabled editor draws its plain text in the
palette's tertiary tier, a stated `.foregroundStyle` included, and a run's own
`foregroundColor` keeps its full colour:

- `Sources/TUITextInput/Views/TextEditor+Rows.swift`, `RowStyling.init(palette:isDisabled:background:stated:)`:
  `let ink = (isDisabled ? palette.foregroundTertiary : stated ?? palette.foreground)`.
- the same file, `styledRow`: `styled?.foreground ?? textForeground`, so a
  run's colour wins over the tertiary ink.
- `Sources/TUITextInput/Rendering/TextFieldContentRenderer.swift`,
  `fadedTextInput(if:text:context:)`: adds faint only where colour cannot say
  "disabled" (no colour, differentiate-without-colour, or tertiary rounding to
  the enabled colour at the terminal's depth).
- The doc comment on `TextEditor` (`Sources/TUITextInput/Views/TextEditor.swift`)
  says it draws "as a disabled TextField draws its own".

So in TUI one disabled attributed editor is half faded: unstyled runs go
tertiary, coloured runs stay at full strength. SwiftUI on 15 fades neither.

## 2. A Toggle's subtitle under a stated foregroundStyle

`Toggle(isOn: .constant(false)) { Text("Title"); Text("Subtitle") }`. macOS
draws the second view as a subtitle: a smaller line under the title (9 pt of
ink rows against the title's 12).

| Where, style | No style: title / subtitle | `.foregroundStyle(.red)` | `.foregroundStyle(.red, .blue)` |
|---|---|---|---|
| bare, `.checkbox` | #272727 / #808080 | #FF3B2F / #FF3B2F | #FF3B2F / #FF3B2F |
| bare, `.switch` | #272727 / #808080 | #FF3B2F / #FF3B2F | #FF3B2F / #FF3B2F |
| `Form` `.grouped`, `.checkbox` | #252525 / #797979 over #F2F2F2 | #FF3B2F / #FF3B2F | #FF3B2F / #FF3B2F |
| `Form` `.grouped`, `.switch` | #252525 / #797979 over #F2F2F2 | #FF3B2F / #FF3B2F | #FF3B2F / #FF3B2F |

**SwiftUI (measured, macOS 15.8.3):** with no style the subtitle is `.secondary`
(#808080 over white, #797979 over the grouped section's #F2F2F2). With a stated
style, the subtitle takes that style's primary level, full strength, the same
pixel as the title. It is not a secondary level of red (#FF9C97) and, under
`(.red, .blue)`, not blue: blue never appears. The answer is the same in all
four places.

For comparison, apart from any control (`VStack`, `.foregroundStyle(.red, .blue)`):
a `Text` under `Text`'s own `foregroundStyle(.secondary) -> Text` draws #FF9C96
(red at the secondary level, not blue); a `Text` under `View`'s
`foregroundStyle(.secondary)` draws #0079FF (blue); a `Rectangle` filled
`.secondary` draws #007AFF (blue). So the two-level style works where it is
asked for, and the toggle simply does not ask for `.secondary` once a style is
stated.

**TUI (source at 77894861f):** an enabled toggle's subtitle is always
`palette.foregroundSecondary`. That replaces any stated style, keeping only its
shadows. A disabled toggle's subtitle keeps the inherited dimmed colour:

- `Sources/TUIFoundation/Views/_ToggleCore.swift`, `composeLabelBuffer(indicator:labelContext:isDisabled:palette:)`:
  `subtitleContext.environment.foregroundStyle.keepingShadows(on: .color(palette.foregroundSecondary))`, set when `!isDisabled`.

So under `.foregroundStyle(.red)` TUI draws a red title over a grey subtitle,
where SwiftUI draws both red. Under `(.red, .blue)` TUI draws grey, where
SwiftUI draws red.

## A side finding, not acted on

Under `.foregroundStyle(.red, .blue)`, SwiftUI's `Text.foregroundStyle(.secondary)`
(the overload that returns `Text`) draws a secondary red (#FF9C96), while
`View.foregroundStyle(.secondary)` draws blue. TUI's `Text` has only a `Color`
overload (`Sources/TUIFoundation/Views/Text.swift`), so `Text("x").foregroundStyle(.secondary)`
goes through `View`'s and presumably draws the stated secondary (blue). That is
not checked in TUI here.
