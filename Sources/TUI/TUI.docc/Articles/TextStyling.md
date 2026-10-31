# Text Styling

Make text bold, faint, italic or underlined, on one `Text` or on everything in a view.

## Overview

Text emphasis can be applied per-``Text``, or **cascaded** to a whole subtree
through the environment, exactly like ``View/foregroundStyle(_:)-(S)``.

## Per-Text

```swift
Text("Bold").bold()
Text("Quiet").dim().italic()
```

## A Whole View at Once

Container-level modifiers apply to every descendant ``Text`` and can be
overridden closer to the content — the nearest modifier wins, per attribute:

```swift
VStack {
    Text("Title")
    Text("Subtitle")
}
.bold()                  // both lines bold
.textCase(.uppercase)    // …and uppercased

// A descendant opts out:
VStack {
    Text("Bold")
    Text("Not bold").bold(false)   // closer wins
}
.bold()
```

Available cascading modifiers: `bold(_:)`, `italic(_:)`, `underline(_:)`,
`strikethrough(_:)`, `fontWeight(_:)` (weight maps to bold / normal / faint on a
terminal), and `textCase(_:)`.

## Semantic Font Styles

``View/font(_:)`` takes a ``Font``, such as `.headline`, `.body`, `.caption` and
the rest of SwiftUI's semantic styles, so source that says *this is a heading*
keeps saying it here:

```swift
VStack(alignment: .leading) {
    Text("Deployment failed").font(.headline)
    Text("3 of 12 replicas unhealthy").font(.body)
    Text("2 minutes ago").font(.caption)
}
```

A terminal has one typeface at one size, so a font selects **intensity**, not
metrics. Eleven SwiftUI styles collapse onto the three tiers a cell grid can
tell apart:

| Styles | Renders |
|--------|---------|
| `largeTitle`, `title`, `title2`, `title3`, `headline` | bold |
| `subheadline`, `body`, `callout` | normal |
| `footnote`, `caption`, `caption2` | faint |

Nothing here changes a glyph or a cell count, so applying a font cannot reflow
the layout around it. The axes that survive the medium are carried for real —
``Font/weight(_:)``, ``Font/bold(_:)`` and ``Font/italic(_:)`` — while the ones
that need a typeface (size, design, width, small caps) are absent rather than
accepted and ignored.

The mapping is the **baseline**, so an explicit attribute anywhere in the
cascade still wins, and each style is addressable as a ``StyleScope/font(_:)``
scope — which is how a theme redefines one wholesale:

```swift
ContentView()
    .style(.font(.headline)) { $0.underline = true }
```

## Inside a Key, with Markdown

A ``Text`` made from a key reads it as inline Markdown, as SwiftUI does:
`**bold**`, `*italic*`, `~~struck~~`, code between backticks, and links. Everything else a
modifier can do to part of a text is reachable too, through Apple's
`^[text](key: value, …)` syntax — useful in a translation, which can style
its words differently from the key, and on Linux, where `AttributedString`
has no Markdown initializer:

```swift
Text("Disk is ^[90% full](foregroundColor: warning, fontWeight: bold)")
Text("^[Deprecated](strikethroughStyle: true, strikethroughColor: red) API")
Text("A ^[spelling](underlineStyle: curly, underlineColor: \"#ff3b30\") mistake")
```

Each key applies its value as the modifier it is named after does:

| Key | Value | Same as |
|---|---|---|
| `foregroundColor` | a colour | `.foregroundStyle(_:)` |
| `backgroundColor` | a colour | an `AttributedString`'s `backgroundColor` |
| `underlineStyle` | `true`, `false` or a pattern | `.underline(_:pattern:color:)` |
| `underlineColor` | a colour | its `color:` (a colour alone draws a solid line) |
| `strikethroughStyle` | `true`, `false` or a pattern | `.strikethrough(_:pattern:color:)` |
| `strikethroughColor` | a colour | its `color:` |
| `font` | `largeTitle` … `caption2` | `.font(_:)` |
| `fontWeight` | `ultraLight` … `black` | `.fontWeight(_:)` |
| `dim` | `true` or `false` | `.dim(_:)` |
| `blink` | `true` | `.blink()` |
| `inverse` | `true` | `.inverted()` |
| `textScale` | `secondary` or `default` | `.textScale(_:)` |

A **colour** is a `Color` name as Swift spells it (`red`, `magenta`, `gray`,
`primary`, `accentColor`, `warning`…), a palette role (`accent`, `info`,
`foregroundTertiary`, or `palette.accent`), or `#rgb` / `#rrggbb`. A
**pattern** is one of `Text.LineStyle.Pattern`'s: `solid`, `dot`, `dash`,
`dashDot`, `dashDotDot`, `double`, `curly`.

The list is Foundation's (JSON5 members): values may be quoted with `"` or
`'`, and must be when they hold a comma or a parenthesis; `true` and `false`
must not be. TUI also takes an unquoted name, which Foundation's own parser
refuses — quote names if the same string is ever handed to
`AttributedString(markdown:)`. The first value of a key holds, and an inner
`^[…](…)` beats an outer one. A key TUI does not know (`inflect`) or a value it
cannot read is passed over, and the text is drawn without it; so is a list
that does not parse. The keys are TUI's own: SwiftUI's `Text` reads none of
them.

## Scoped Styling

``View/style(_:_:)-(_,StyleAttributes)`` targets a subset of views by ``StyleScope`` — including a
semantic colour role, so you can, for example, dim every secondary-coloured text
app-wide without touching primary text:

```swift
RootView()
    .style(.semanticColor(.foregroundSecondary)) { $0.dim = true }
```

Structural **chrome** — a `List`'s `Section` headers and footers — can be
targeted the same way (they are bold + dim by default, and the cascade
overrides that). Outside a list a section's header and footer are drawn as
written, as SwiftUI's are, and take no chrome role:

```swift
List {
    Section("Settings") { /* … */ }
}
.style(.chrome(.sectionHeader)) { $0.textCase = .uppercase }   // UPPERCASE headers
```

**Controls** expose typed conveniences over the scope mechanism. For example, a
button's label text:

```swift
Sidebar().buttonTextStyle { $0.bold = true; $0.foreground = .green }  // all buttons
RootView().buttonTextStyle(.automatic) { $0.foreground = .blue }      // default-style only
```

A load-bearing colour (e.g. a `.destructive` button's error red) stays asserted by
the control's style and is not overridden by a broad cascade entry.

## See Also

- <doc:AppearanceAndColors>
- <doc:ThemingGuide>
- <doc:Localization>
