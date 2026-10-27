# Content levels, foreground styles and legibility weight

*The content levels (`.secondary` to `.quinary`) and the two- and three-style
`foregroundStyle`, and `\.legibilityWeight`. Ids: B22, B2.*

## In short

With no foreground style above, the levels are the palette's; under one, they
are that style at decreasing strength, composited at the cell (at 16 colours
the faintest vanish: A-EFFECTS-1, in the pixel effects story).
`\.legibilityWeight` is settable, and under `.bold` every site that draws
text steps its weight once (2026-10-13).

## The record

### B22. The content levels, and the two- and three-style `foregroundStyle`

*`HierarchicalShapeStyle`, `HierarchicalShapeStyleModifier`,
`View.foregroundStyle(_:_:)`, `View.foregroundStyle(_:_:_:)`*

The compatibility doc declined all four on two grounds. Neither held up:

- **Ambiguity.** A `.secondary` on `ShapeStyle` beside `Color.secondary` does
  not make `.foregroundStyle(.secondary)` ambiguous, because the `Color`
  overload is the disfavoured one. That is how SwiftUI is built too.
- **"A glyph has one layer."** True for a symbol, but the second and third
  styles are also what `.secondary` and `.tertiary` resolve to below the
  modifier, and a terminal honours that fully.

**What shipped.** With no foreground style above, the levels are the palette's
tiers, so `.foregroundStyle(.secondary)` paints what `Color.secondary` did.
`.quinary` is the quaternary tier at half strength. Under a `foregroundStyle`,
the levels are that style at macOS's label alphas (1, 0.5, 0.26, 0.1, 0.05),
composited at the cell. The two- and three-style forms name the second and
third levels outright; the levels past a named one are it faded by the same
ratios. A single-style `foregroundStyle` below clears the named levels, so
`.secondary` derives from the nearer primary.

**What moves for an app.** One case changes:
`.foregroundStyle(.secondary)` on a non-`Text` view, below an explicit
`foregroundStyle`. That is now the outer style at half strength, where it was
the palette's secondary tier, which is SwiftUI's behaviour.
`Text("a").foregroundStyle(.secondary)` is unchanged, because it still takes
`Text`'s `Color` overload (§3's remaining refusal).

**Enhancements to consider:**

- The 0.5 / 0.26 / 0.1 / 0.05 strengths are macOS's light-appearance label
  alphas. At 0.1 and 0.05 a faded glyph's colour is nearly the surface's, which
  the rendered contrast floor may lift. That is fine for a tint, but it is
  worth a live look in the 16- and 256-colour modes.
- A fuller version would carry the levels per palette (a palette naming its
  own faded tiers for an arbitrary foreground). That is a palette-protocol
  change, so I left it for you.

**Decided 2026-10-05** (you asked for my recommendation on 2026-10-04): the
cheap one, a live look at the faint tiers in 16 and 256 colours, owed; the
per-palette tiers are skipped for now.

**Looked at 2026-10-19** (lane EFFECTS; `FaintLevelsAuditTests`, the ink read
back out of the emitted SGR over each shipped palette's page): at 16 colours,
on every palette, `.secondary` is `.primary`'s colour and `.tertiary` to
`.quinary` are the page's own — invisible. At 256 most levels stay apart, but
`.quinary` is the page on five palettes and `.quaternary` too on three, and
some neighbours share a colour. The rendered contrast floor does not reach
content text. Nothing changed: a vanishing level is your call,
[A-EFFECTS-1](<../Shapes, effects and animation/Pixel effects: transforms, masks, drawingGroup, blend modes and meshes.md#a-effects-1-the-faint-content-levels-vanish-at-16-colours-and-the-faintest-at-256>).

### B2. `\.legibilityWeight` is settable, and every text-drawing site steps its weight

SwiftUI's is settable. Under `.bold`, every piece of system text is drawn
one weight heavier. That was measured on a SwiftUI build: light→regular,
regular→bold, and bold stays bold. In SwiftUI that includes control labels.

TUI draws many labels without going through `Text`, so honouring it in
`Text` alone would be a partial honour, which is the shape Rule 2 forbids.

**The fuller version** is one "heavier by one step" rule applied at every
text-drawing site:

- faint→normal, normal→bold;
- `Text`, button and control labels, field contents, list chrome.

Alternatively, apply it once at the subtree's buffer, the way
`SGRColorRewrite` applies a colour effect. The rewrite is cheaper to get
complete, but it would also embolden non-text glyphs (borders, bars). That
is a reason to prefer the per-site rule.

**Owner, 2026-10-12 (second message):** yes, make it writable. Lane owed (the helper, the A/B); both done, below.

**Shipped 2026-10-13, the per-site rule.** `\.legibilityWeight` is settable,
`nil` by default. One helper, `LegibilityWeight?.applied(bold:faint:)`, steps a
weight a tier up under `.bold` — faint → plain, plain → bold, bold stays — and
every site that draws text uses it: `Text` (after a secondary scale's step down,
before redaction's dim), and each control that draws its own text rather than a
`Text` — a field's contents, prompt and caret cell (`TextField`, `SecureField`,
the vertical field, `TextEditor`), a button style's string label, a picker's
closed label, the stepper's and slider's read-outs, both date pickers, a tab's
title and badge, a navigation crumb, a list row's badge, a table's cells and its
reorder preview, the status bar's labels and help, a tooltip, a notification, a
spinner's label, the 256-colour grid's numbers. A site whose lines are all text
wraps them in `ANSIRenderer.applyPersistentBold` (with `AnimatedCellRun.drawnBold`
for frames the run loop paints itself); one that mixes text with chrome passes
the weight to the text's own run. Borders, caps, arrows, indicators, swatches,
images and rules are not text and are never stepped, which is why the per-site
rule was chosen over a rewrite of a subtree's buffer. A faint that means
something other than a weight (disabled, `.dimmed()`, `.invalidated`) is not
stepped. Tests: `LegibilityWeightTests`, `LegibilityWeightControlTests`,
`LegibilityWeightChromeTests`. Cost where no weight is set: one environment
read per `Text` and per control that draws its own text. The A/B ran at the landing (2026-10-13, the base before it against the commit, with the machine not
quiet, so indicative): neutral, the largest change controls +0.7% cold and several
scenarios 0.3 to 0.9% faster; the stripped binary grew 16,544 B.

**Asked 2026-10-12 (answered above, and shipped): confirm that it should become writable.** You asked
whether this was already decided. Not in so many words: on 2026-10-04 you
said it did not seem hard to support, asked whether the built-in views should
switch to drawing through `Text`, and wanted an experiment and a benchmark
before deciding; on 2026-10-05 I answered that they need not switch (a shared
"one weight heavier" helper at each drawing site costs one environment read
per control) and that I would A/B it. Neither the helper nor the A/B was
built. If you confirm, the lane is 4–6 commits, about 1–1.5 days (estimate):
the setter, keeping `nil` the default; the helper (faint→normal,
normal→bold, bold stays bold); `Text`; the controls and chrome by family (58
`ANSIRenderer.colorize(` calls in 28 files, plus the sites that build a style
without it); tests under `.bold`; and the A/B on the quiet machine. Some
terminals draw bold as a brighter colour (Terminal compatibility survey.md), which the
heavier weight inherits.
