# Drawing with Canvas

Draw paths, gradients, images, text and views from a closure, at the finest grain the terminal offers.

## Overview

``Canvas`` is SwiftUI's: the same initializer, and a ``GraphicsContext`` spelled as SwiftUI spells it.

```swift
Canvas { context, size in
    let disc = Path(ellipseIn: CGRect(origin: .zero, size: size))
    context.fill(disc, with: .radialGradient(
        Gradient(colors: [.yellow, .red]),
        center: CGPoint(x: size.width / 2, y: size.height / 2),
        startRadius: 0, endRadius: size.width / 2))
    context.stroke(disc, with: .color(.white), lineWidth: 0.5)
    context.draw(Text("Sun"), at: CGPoint(x: size.width / 2, y: size.height / 2))
}
.frame(width: 24, height: 12)
```

A canvas fills what it's offered, as a shape does, and clips to its frame. Reach for one when you're drawing several things at once, or something computed. For a single shape, use the ``Shape`` itself. To animate one, draw it inside a ``TimelineView``.

The initializer's other parameters are SwiftUI's too: `opaque: true` starts every pixel at the palette's background, so nothing behind shows through, and `colorMode: .linear` mixes gradients and blends in linear light rather than the default `.nonLinear` (``ColorRenderingMode``). `rendersAsynchronously` is accepted and changes nothing; the canvas draws on the main actor as the frame does.

## Sizes are a shape's

`size` and every position are in the square units a ``Shape`` uses: a column across, and about two of them down a row (``EnvironmentValues/imageCellAspect``). So a 24 × 12-cell frame is a 24 × 24 canvas, and a circle in it is round. Line widths and offsets are in the same units.

## How fine it draws

Paths and images land on pixels, and what a pixel is depends on the terminal:

- Where the terminal places pictures in its cell grid, a canvas is a picture, in the terminal's own pixels. ``View/terminalGraphics(_:)`` and ``View/gradientGraphics(_:)`` turn this off for a subtree.
- Anywhere else, each cell draws a glyph in two colours: by default a quadrant, two pixels by two, which every font has.

``View/canvasGrain(_:)`` chooses a vocabulary of glyphs instead, for a look or to reach further on a terminal you know has them. It's a TUI addition.

| ``CanvasGrain`` | Pixels a cell | Glyphs |
|---|---|---|
| ``CanvasGrain/automatic`` | the terminal's, or 2 × 2 | a picture, or quadrants |
| ``CanvasGrain/cells`` | 1 × 1 | a colour |
| ``CanvasGrain/halfBlocks`` | 1 × 2 | `▀ ▄`, as a ``Shape`` is rasterized |
| ``CanvasGrain/quadrants`` | 2 × 2 | `▘ ▝ ▖ ▗ ▚ ▞` and so on |
| ``CanvasGrain/sextants`` | 2 × 3 | Symbols for Legacy Computing, Unicode 13 |
| ``CanvasGrain/octants`` | 2 × 4 | its Supplement, Unicode 16: the finest solid grain, and the least widely drawn |
| ``CanvasGrain/braille`` | 2 × 4 | Braille dots: in nearly every font, and best for lines |

A finer grain gives sharper edges, not more colours: a cell still holds two. A cell where a shape's edge passes shows what's behind the canvas through its empty pixels, and pixels at partial strength blend with what's behind them, as a shape's antialiased edge does.

## Text and views are cells

A text and a resolved symbol draw the cells their views draw. A glyph lands on the whole cell its origin rounds to, at its own size and angle whatever the transform scales or turns. Paths and images honour the whole transform.

Each cell is a glyph or pixels, never both at once. Whichever was drawn later takes it: a glyph over pixels takes their colour as its field, and a shape painted over at least half of a glyph's cell removes the glyph. A clip keeps a glyph whole or not at all, by whether it keeps at least half the cell.

A symbol is a view you can draw as often as you like. It's found by its tag, and takes no input:

```swift
Canvas { context, size in
    guard let star = context.resolveSymbol(id: "star") else { return }
    context.draw(star, at: CGPoint(x: size.width / 2, y: size.height / 2))
} symbols: {
    Text("★").foregroundStyle(.yellow).tag("star")
}
```

## State, layers and filters

A context is a value: copy it to draw with a different transform, opacity, blend mode, clip or filter, and both copies draw into the same canvas. `drawLayer` draws into a transparency layer that lands as one drawing, so two overlapping fills inside a half-faded layer don't darken where they overlap.

Blur, shadows, colour matrices, `luminanceToAlpha` and `alphaThreshold` work on pixels, so glyphs pass through them unchanged. The colour filters apply to both.

Not offered, because nothing in a terminal can run them: the shaders (`colorShader`, `distortionShader`, `layerShader`, `Shading.shader`), `withCGContext`, and `projectionTransform`. `FilterOptions.linearColor` isn't offered either. `rendersAsynchronously` is accepted, and the renderer runs on the main actor regardless.

## Reaching the grid

These are TUI additions, for when a path is the wrong tool.

- ``GraphicsContext/pixelGrid`` is how many pixels this canvas has, which varies with the terminal and the grain.
- ``GraphicsContext/setPixel(x:y:to:)`` sets one, past the transform: a plot, a cellular automaton.
- ``GraphicsContext/drawLine(from:to:with:)`` draws a line one sharp pixel wide, where a thin stroke would blur.
- ``GraphicsContext/drawPixels(_:width:height:in:)`` draws a dense bitmap you compute, stretched to a rectangle, without making an ``Image`` of it each frame.
- ``GraphicsContext/setCell(column:row:to:foreground:background:)`` writes a character into a whole cell.

```swift
Canvas { context, _ in
    let grid = context.pixelGrid
    for x in 0..<grid.width {
        let y = grid.height / 2 + Int(sin(Double(x) / 4) * Double(grid.height) / 3)
        context.setPixel(x: x, y: y, to: .green)
    }
}
.canvasGrain(.braille)
```

## See Also

- ``Shape``
- <doc:WorkingWithImages>
- <doc:AnimatingYourOwnView>
