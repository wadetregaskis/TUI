# TextRenderer design study, O16 (2026-10-28)

*The owner's TEXT-EFFECTS ruling (2026-10-28): build SwiftUI's `TextRenderer`,
`Text.Layout` and `customAttribute`, on the subset of `GraphicsContext` that
text needs, plus a TUI extension to swap a glyph's character; `Canvas` later
on the same context; example effects in the Example app (wave, dissolve,
typewriter, rainbow). This study turns that into a build plan. It also
answers the owner's two earlier wishes (2026-10-27, low priority): animating
the other text effects — bold, italic, underline — along a text by character
or word, and an extensible text animation API with fun example effects.*

## 1. What SwiftUI has (Xcode 26.3 SDK, symbol graph)

```swift
protocol TextRenderer: Animatable {
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext)
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize   // default: text.sizeThatFits(proposal)
    var displayPadding: EdgeInsets { get }                                     // default: .zero
}
struct TextProxy { func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize }
extension View { func textRenderer<T: TextRenderer>(_ renderer: T) -> some View }

protocol TextAttribute: Hashable {}
extension Text { func customAttribute<T: TextAttribute>(_ value: T) -> Text }

extension Text {
    struct Layout: RandomAccessCollection, Equatable {        // of Line
        var isTruncated: Bool
        struct Line: RandomAccessCollection, Equatable {     // of Run
            var origin: CGPoint
            var typographicBounds: TypographicBounds
        }
        struct Run: RandomAccessCollection, Equatable {      // of RunSlice (one glyph each)
            subscript<T: TextAttribute>(key: T.Type) -> T? { get }
            var layoutDirection: LayoutDirection
            var typographicBounds: TypographicBounds
            var characterIndices: [CharacterIndex]
            subscript(bounds: Range<Int>) -> RunSlice
        }
        struct RunSlice: RandomAccessCollection, Equatable { // of RunSlice
            var run: Run; var indices: Range<Int>
            init(run: Run, indices: Range<Int>)
            subscript<T: TextAttribute>(key: T.Type) -> T? { get }
            var typographicBounds: TypographicBounds
            var characterIndices: [CharacterIndex]
        }
        @frozen struct TypographicBounds: Equatable {
            var origin: CGPoint; var width, ascent, descent, leading: CGFloat
            init(); var rect: CGRect { get }
        }
        @frozen struct CharacterIndex: Strideable, Hashable
        @frozen struct DrawingOptions: OptionSet { static var disablesSubpixelQuantization }
    }
    struct LayoutKey: PreferenceKey {                         // [AnchoredLayout]
        struct AnchoredLayout: Equatable { var origin: Anchor<CGPoint>; var layout: Text.Layout }
    }
}

extension GraphicsContext {
    func draw(_ line: Text.Layout.Line, options: Text.Layout.DrawingOptions = .init())
    func draw(_ run: Text.Layout.Run, options: Text.Layout.DrawingOptions = .init())
    func draw(_ slice: Text.Layout.RunSlice, options: Text.Layout.DrawingOptions = .init())
}
```

`GraphicsContext` itself is large: state (`opacity`, `blendMode`, `transform`,
`translateBy`/`scaleBy`/`rotate`, `clip`, `clipToLayer`), filters
(`addFilter` with `shadow`, `colorMultiply`, `saturation`, `brightness`,
`hueRotation`, `grayscale`, `contrast`, `colorInvert`, `blur`, shaders …),
`Shading`, `fill`/`stroke` of paths, images, resolved text and symbols,
`drawLayer`, `withCGContext`.

The canonical effects in Apple's own material are all of one shape: walk
lines → runs → slices, and for each slice set `opacity`, a `translateBy`, a
filter or a shading from the slice's index and an animatable time, then
`draw(slice)`. A custom attribute (`Text("x").customAttribute(Emphasis())`)
marks the spans an effect applies to; the renderer reads `run[Emphasis.self]`
and draws everything else plainly.

## 2. How each part maps onto cells

TUI's geometry is already CGFloat in **cells** wherever SwiftUI's API is
CGFloat (`Shape.path(in: CGRect)`, `StrokeStyle`), one point a cell across
and a row down. The text renderer keeps that rule.

| SwiftUI | In TUI |
|---|---|
| `Text.Layout` | The text's wrapped lines as `_TextCore` lays them out today (the same wrap, truncation and alignment), built only when a renderer is in force. `isTruncated` is whether the truncation mode cut it. |
| `Line` | One wrapped line: `origin` its leading cell's column and row (y the row's top: TUI has no baseline, so the line's origin is its top-left cell), its runs in visual order. |
| `Run` | A span of one style and one set of custom attributes: what TUI's styled runs already are, split further where a `customAttribute` starts or ends. `layoutDirection` is `.leftToRight` (TUI lays out left to right until right-to-left text lands). |
| `RunSlice` / glyph | One **grapheme cluster**, the unit that occupies cells: a slice's width is 1 or 2 cells (`cells not characters`). Indices are slice indices within the run, as SwiftUI's are glyph indices. |
| `CharacterIndex` | The grapheme's offset in the text's characters (SwiftUI: UTF-16 offset in the attributed string; TUI: Character offset — documented deviation, since TUI's text is indexed by Character everywhere). |
| `TypographicBounds` | `origin` the cell's top-left, `width` its cells, **`ascent` 1, `descent` 0, `leading` 0**: a cell is a row high, all above the line's top-to-bottom. `rect` is then exactly the cells covered. The parity map called these "no honest value"; whole cells are an honest value, and a renderer that centres something on `rect.midY` gets the row's middle. |
| `DrawingOptions` | Accepted and ignored: there is no subpixel quantization to disable. |
| `textRenderer(_:)` | An environment value read by `Text` when it draws (one nil check where none is set, as the strike sweep's is). Every `Text` below takes it, as in SwiftUI; a nested one replaces it. |
| `customAttribute(_:)` | Stored on the `Text`'s runs (concatenation keeps it, as SwiftUI's does); one per type per span. |
| `sizeThatFits(proposal:text:)` | Over `ProposedSize`/`ViewSize` in cells (TUI's spelling of `ProposedViewSize`/`CGSize`, parity map §2.2); the default asks the proxy, which measures the text as it measures now. |
| `displayPadding` | Cells the renderer may draw beyond the text's frame on each edge, rounded out. See §4. |
| `Text.LayoutKey` | Phase 3: published as a preference with `Anchor<CGPoint>` (TUI has `Anchor`), so a parent can read a text's layout. |

## 3. The `GraphicsContext` subset

A new public `GraphicsContext` struct in TUIFoundation (the `Text` module),
drawing into a cell canvas the size of the text's frame plus its padding. It
is the start of the context `Canvas` will use (owner: "Canvas later on the
same context"), so its shape follows SwiftUI's where it exists at all.

**Built in phase 1 (what the example effects and the common recipes use):**

- `opacity` — composes as `View.opacity` does: each drawn cell's colours
  faded toward what is under it (the opacity pipeline, encoded sRGB; a glyph
  over nothing draws at every alpha, so a dissolve fades by colour and the
  glyph goes at 0).
- `translateBy(x:y:)` and `transform` (translation part) — **rounded to whole
  cells** at the draw. A wave's `sin(i) * 0.6` lifts a glyph by 1 row at the
  crest and none elsewhere; a renderer wanting a smoother wave chooses a
  larger amplitude. `scaleBy` and `rotate` are accepted, and a draw under a
  scale or rotation places the glyph at the transformed cell of its origin
  without resizing or turning it (a glyph cannot scale or rotate), which is
  stated in each one's documentation as the deviation.
- `blendMode` — the existing per-cell blend pipeline (W5).
- `addFilter(_:)` for the colour filters TUI already has as colour effects:
  `colorMultiply`, `saturation`, `brightness`, `contrast`, `hueRotation`,
  `grayscale`, `colorInvert`; `shadow(color:radius:x:y:)` as the whole-cell
  shadow (O6); `blur`, `projectionTransform`, `luminanceToAlpha`,
  `alphaThreshold` and the shader filters are not provided (a cell has
  nothing to blur and no shader runs on a terminal) and are left out of the
  API rather than stubbed (INERT-APIS).
- `draw(_ line:)`, `draw(_ run:)`, `draw(_ slice:)` with `options:`.
- `Shading` for a slice's ink: `.color(…)`, `.style(_:)` (any `ShapeStyle`,
  gradients included, sampled per cell as gradients already are),
  `.foreground`, `.palette(_:)`. A draw takes the context's current
  foreground shading, `.foreground` (the text's own) unless set.
- `drawLayer(content:)` and `clipToLayer` — a nested context whose result is
  composited as a group (needed for "fade this run as one").
- `clip(to: Path)` with the path rasterised to whole cells (the shapes'
  existing rasteriser), a cell kept where its centre is inside.

**TUI's extension (phase 1), the part SwiftUI cannot do:**

```swift
extension GraphicsContext {
    /// Draws `slice` with its characters replaced by `character`, in its style
    /// and at its place — the terminal's way to change a glyph's shape: a
    /// dissolve through ever-smaller glyphs (█ ▓ ▒ ░ ·), a typewriter's
    /// cursor, a scramble.
    func draw(_ slice: Text.Layout.RunSlice, as character: Character, options: …)

    /// The cell attributes the next draws use instead of the run's own:
    /// bold, italic, underline (and its pattern), strikethrough, dim, blink,
    /// inverse. `nil` fields keep the run's.
    var textAttributes: TextCellAttributes
}
```

The second is what makes "animate bold, italic, underline along a text, by
character or by word, either direction" one small renderer: set
`ctx.textAttributes.underline = .single` for the slices the sweep has reached
and draw. The strike sweep shipped on 2026-10-27 is exactly such a renderer,
and is rewritten on top of this as the first in-tree user (no behaviour
change; one implementation instead of two).

**Phase 2 (with `Canvas`):** `fill`/`stroke` of paths with shadings, images
(`draw(_ image:)` through the picture path), resolved text and symbols,
`withCGContext` (Apple platforms only, rasterised to the picture path).

## 4. Where it draws: the frame, and beyond it

A wave lifts glyphs a row above the text's frame; a renderer that draws
outside its frame draws over its neighbours in SwiftUI, unclipped (and
`displayPadding` only sizes a rasterising layer). TUI keeps the frame's
cells as the text's own, and treats what is drawn outside them as a
floating layer, composited at the root — the mechanism `.offset(x:y:)`
already uses for a view drawn away from its frame. So a renderer draws
anywhere, the layout is unchanged (the renderer's `sizeThatFits` is what
layout sees), and nothing outside the frame is cut. `displayPadding` is
accepted for parity and used only to size the canvas up front.

## 5. Time: how an effect animates

`TextRenderer` is `Animatable`, so an effect animates in two ways, both as in
SwiftUI:

1. **Between values under an animation:** a renderer whose `animatableData`
   is a progress, changed `withAnimation`, is interpolated frame by frame by
   the animation store (`animatedValue(of:owner:context:)`, the mechanism the
   strike sweep uses), keyed by the text's identity.
2. **Continuously:** a `TimelineView(.animation)` whose body sets the
   renderer's elapsed time (Apple's own wave sample is written this way).
   TUI's `TimelineView` exists; the frames are 1/60 s multiples.

A text under a renderer whose value does not change draws once and is
memoised as any text is (the renderer's value is part of the memo key, as a
value read from the environment). A renderer must be a value type; its
stored properties are hashed with the existing value-hashing plans.

## 6. Cost

- **No renderer:** one environment read and a nil check per `Text` draw — the
  same pattern as the strike sweep, which measured indistinguishable.
- **With a renderer:** building the layout (lines → runs → slices) from the
  wrapped lines already computed, then one cell write per drawn slice. For a
  title of 30 graphemes that is well under the cost of the text's own wrap.
  The A/B owed: `kitchensink` and `controls` (no renderer: must be within
  noise) and a new Stress scenario, `texteffects`, with four renderers
  animating continuously, to set a baseline.

## 7. Example effects (the Example app, a "Text Effects" section on the Text Styles page)

- **Wave** ("Mexican wave"): capitals travel through the text — a slice is
  lifted a row and uppercased (`draw(_:as:)`) where `sin(index·k − t)` is past
  a threshold; back and forth with a triangle wave.
- **Dissolve:** from the end, each grapheme steps through `█ ▓ ▒ ░ ·` and
  then nothing (`draw(_:as:)`, then not drawn), then the next.
- **Typewriter:** slices up to `progress · count` drawn, a `▏` cursor after
  the last, blinking.
- **Rainbow:** each slice's shading a hue from its column and time
  (`Shading.color` from `Color.hsl`).
- **Sweeps** (the owner's 10-27 wish): bold, underline and italic swept along
  the text by character or by word, left-to-right or right-to-left, from one
  `AttributeSweep(attribute:unit:direction:progress:)` renderer in the
  Example — not framework API, since it is ten lines over the context, which
  is the point of the extension.

## 8. Phases and estimates

1. **Layout + context + renderer (2 days):** `Text.Layout` and its types,
   `TextAttribute`/`customAttribute`, `TextRenderer`/`TextProxy`/`textRenderer`,
   the phase-1 `GraphicsContext` with the two TUI extensions, the
   out-of-frame layer; the strike sweep rewritten on it; tests per type
   (geometry of lines/runs/slices for wrapped, truncated, wide and combining
   text; each context operation's cells; animation interpolation; memo).
2. **Examples + Stress scenario + A/B (1 day):** the five effects, a
   ScreenClips review scene, the `texteffects` scenario, the A/B.
3. **`Text.LayoutKey` (½ day)**, then `Canvas` and the phase-2 context as
   their own project (the D3 note), on the owner's word.

## 9. Decisions taken here (minor, per the owner's "decide minor questions yourself")

- Geometry in cells, CGFloat, as the shapes are; translation rounded to whole
  cells at the draw.
- A slice is a grapheme cluster.
- `TypographicBounds` of a cell: ascent 1, descent 0, leading 0.
- `CharacterIndex` counts Characters, not UTF-16 units (deviation, recorded).
- Out-of-frame drawing floats as `.offset` does, never clipped.
- Filters and operations a cell cannot do are left out, not stubbed.

## 10. Open for the owner

None blocking. One flag: **`scaleBy` and `rotate`** place a glyph at its
transformed position without changing its size or angle. The alternative is
to leave both out of the context until `Canvas` (where a path can scale and
turn). Leaving them in lets SwiftUI renderers that scale a little (a "pop"
effect) compile and roughly work; leaving them out makes such code fail to
compile. The study takes the former; say if you prefer the latter.
