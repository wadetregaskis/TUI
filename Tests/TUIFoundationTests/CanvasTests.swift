//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasTests.swift
//
//  What a `Canvas` and its `GraphicsContext` draw, read back from the pixels and
//  the cells: not that the renderer ran, but what landed where.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

private let red = Color.rgb(255, 0, 0)
private let blue = Color.rgb(0, 0, 255)
private let white = Color.rgb(255, 255, 255)
private let opaqueRed = CanvasRGBA(red: 255, green: 0, blue: 0, alpha: 255)
private let opaqueBlue = CanvasRGBA(red: 0, green: 0, blue: 255, alpha: 255)

@MainActor
@Suite("Canvas: what it draws")
struct CanvasTests {

    // MARK: The view

    @Test("The renderer gets a shape's square units, and the canvas fills what it is offered")
    func sizeInUnits() {
        var seen: CGSize?
        let canvas = Canvas { _, size in seen = size }
        let buffer = canvasDrawn(canvas, columns: 12, rows: 6)
        #expect(seen == CGSize(width: 12, height: 12), "a row is two units")
        #expect(buffer.width == 12 && buffer.lines.count == 6)
    }

    @Test("The renderer is not run for a measure pass")
    func measuringDrawsNothing() {
        var runs = 0
        let canvas = Canvas { _, _ in runs += 1 }
        var context = makeRenderContext(width: 4, height: 2)
        context.isMeasuring = true
        _ = renderToBuffer(canvas, context: context)
        #expect(runs == 0)
    }

    @Test("A canvas left empty states no colour and leaves its cells to what is behind")
    func emptyCanvas() {
        let buffer = canvasDrawn(Canvas { _, _ in })
        #expect(buffer.lines.map(\.stripped) == ["    ", "    "])
        #expect(!buffer.opacityRegions.isEmpty, "each cell is handed back")
    }

    @Test("A fill at the cell grain paints the cells it covers, and only those")
    func fillInCells() {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: size.height)), with: .color(red))
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.cells))
        let cells = paintedCells(buffer.lines[0])
        #expect(cells.map(\.state.backgroundColour) == [.rgb(255, 0, 0), .rgb(255, 0, 0), nil, nil])
        #expect(buffer.lines.map(\.stripped) == ["    ", "    "])
    }

    @Test("At half blocks a canvas draws what the same shape draws, glyph for glyph")
    func halfBlocksMatchTheShape() {
        let canvas = Canvas { context, size in
            context.fill(Circle().path(in: CGRect(origin: .zero, size: size)), with: .color(red))
        }
        let viaCanvas = canvasDrawn(canvas.canvasGrain(.halfBlocks), columns: 12, rows: 6)
        let viaShape = canvasDrawn(Circle().fill(red), columns: 12, rows: 6)
        #expect(viaCanvas.lines.map(\.stripped) == viaShape.lines.map(\.stripped))
    }

    @Test("A disc in a frame twice as wide as tall is round")
    func discIsRound() {
        let drawn = canvasSurface(columns: 8, rows: 4) { context, size in
            context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(red))
        }
        let (rows, raster) = (canvasLetters(drawn), drawn.raster)
        #expect(raster.width == 16 && raster.height == 8)
        // Measured through its centre, it is as many units wide as tall: 16
        // pixels of half a unit, 8 of one.
        #expect(rows[3].filter { $0 != "." }.count == 16)
        let down = (0..<raster.height).filter { raster[8, $0].alpha > 0 }.count
        #expect(down == 8)
    }

    // MARK: Grains

    @Test("A quarter of a cell is a quadrant glyph, in ink, with no field")
    func quadrantGlyph() {
        let canvas = Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 0.5, height: 1)), with: .color(red))
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.quadrants), columns: 1, rows: 1)
        let cell = paintedCells(buffer.lines[0])[0]
        #expect(cell.glyph == "▘")
        #expect(cell.ink == .rgb(255, 0, 0))
        #expect(cell.state.backgroundColour == nil)
    }

    @Test("Two colours in a cell are its ink and its field, whichever pixels hold them")
    func twoColours() {
        let canvas = Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 0.5, height: 2)), with: .color(red))
            context.fill(Path(CGRect(x: 0.5, y: 0, width: 0.5, height: 2)), with: .color(blue))
        }
        let cell = paintedCells(canvasDrawn(canvas.canvasGrain(.quadrants), columns: 1, rows: 1).lines[0])[0]
        #expect(cell.glyph == "▐", "the last pixel is the ink")
        #expect(cell.ink == .rgb(0, 0, 255))
        #expect(cell.state.backgroundColour == .rgb(255, 0, 0))
    }

    @Test("Every grain's masks are the Unicode blocks' own, where the standard library knows their names")
    func grainTablesAreUnicode() {
        func expectNamed(_ character: Character, _ prefix: String, _ cells: [Int]) {
            guard let scalar = character.unicodeScalars.first, let name = scalar.properties.name else { return }
            // Only a name that spells its cells is checked: a mask an earlier
            // block already drew has a name of its own.
            guard name.hasPrefix(prefix) else { return }
            let named = name.dropFirst(prefix.count).compactMap { Int(String($0)) }
            #expect(named == cells, "\(name)")
        }
        for mask in 1..<63 {
            let cells = (0..<6).filter { mask & (1 << $0) != 0 }.map { $0 + 1 }
            expectNamed(CanvasGrain.sextants.glyph(mask: mask), "BLOCK SEXTANT-", cells)
        }
        for mask in 1..<255 {
            let cells = (0..<8).filter { mask & (1 << $0) != 0 }.map { $0 + 1 }
            expectNamed(CanvasGrain.octants.glyph(mask: mask), "BLOCK OCTANT-", cells)
        }
        #expect(CanvasGrain.sextants.glyph(mask: 21) == "▌")
        #expect(CanvasGrain.octants.glyph(mask: 0x0F) == "▀")
        #expect(CanvasGrain.octants.glyph(mask: 0xFA) == "▟")
        #expect(CanvasGrain.octants.glyph(mask: 4).unicodeScalars.first?.value == 0x1CD00)
    }

    @Test("Each grain's glyphs take one cell, and every octant mask has a glyph of its own")
    func glyphsAreOneCellWide() {
        var seen = Set<Character>()
        for mask in 0..<256 {
            let glyph = CanvasGrain.octants.glyph(mask: mask)
            #expect(glyph.terminalWidth == 1 || mask == 0, "mask \(mask)")
            seen.insert(glyph)
        }
        #expect(seen.count == 256)
        #expect(CanvasGrain.sextants.glyph(mask: 1).terminalWidth == 1)
        #expect(CanvasGrain.braille.glyph(mask: 0xFF) == "⣿")
    }

    @Test("Braille's dots are numbered down, not across")
    func brailleLayout() {
        // The second pixel of the top row is the right column's first dot, 4.
        #expect(CanvasGrain.braille.glyph(mask: 0b10) == "⠈")
        // The third pixel, the left column's second row, is dot 2.
        #expect(CanvasGrain.braille.glyph(mask: 0b100) == "⠂")
        // The bottom row is dots 7 and 8.
        #expect(CanvasGrain.braille.glyph(mask: 0b1100_0000) == "⣀")
    }

    @Test("On a terminal with no colour a pixel is there or not, and states nothing")
    func monochrome() {
        let canvas = Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 0.5, height: 1)), with: .color(red))
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.quadrants), columns: 1, rows: 1, depth: .noColor)
        #expect(buffer.lines[0].stripped == "▘")
        #expect(!buffer.lines[0].contains("\u{1B}[38") && !buffer.lines[0].contains("\u{1B}[48"))
    }

    // MARK: Transforms

    @Test("A translation moves what is filled, by units")
    func translate() {
        let drawn = canvasSurface(columns: 2, rows: 1) { context, _ in
            context.translateBy(x: 1, y: 1)
            context.fill(Path(CGRect(x: 0, y: 0, width: 0.5, height: 1)), with: .color(red))
        }
        #expect(canvasLetters(drawn) == ["....", "..R."].map { String($0) })
    }

    @Test("A rotation turns a path, where it could not turn a glyph")
    func rotate() {
        let drawn = canvasSurface(columns: 2, rows: 2) { context, _ in
            // A bar from the centre rightwards, turned a quarter to point down.
            context.translateBy(x: 1, y: 2)
            context.rotate(by: .degrees(90))
            context.fill(Path(CGRect(x: 0, y: -0.5, width: 2, height: 1)), with: .color(red))
        }
        let raster = drawn.raster
        #expect(raster[1, 3] == opaqueRed || raster[2, 3] == opaqueRed, "below the centre")
        #expect(raster[3, 1].alpha == 0, "not to its right")
    }

    @Test("A scale scales a stroke's width as well as its path")
    func scaleStroke() {
        let drawn = canvasSurface(columns: 4, rows: 2) { context, size in
            context.scaleBy(x: 2, y: 2)
            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: 0.75)); $0.addLine(to: CGPoint(x: size.width / 2, y: 0.75)) },
                with: .color(red), lineWidth: 0.5)
        }
        // 0.5 scaled is one unit, and a pixel here is one unit down: the line,
        // centred on 1.5 units, is exactly the second row of pixels.
        #expect(canvasLetters(drawn).filter { $0.contains("R") }.count == 1)
    }

    // MARK: Strokes and shadings

    @Test("A stroke paints the line and leaves the rest")
    func stroke() {
        let drawn = canvasSurface(columns: 4, rows: 2) { context, size in
            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: 1)); $0.addLine(to: CGPoint(x: size.width, y: 1)) },
                with: .color(red), lineWidth: 2)
        }
        #expect(canvasLetters(drawn) == ["RRRRRRRR", "RRRRRRRR", "........", "........"], "two units deep, centred on one")
    }

    @Test("A linear gradient runs between its points, in the context's coordinates")
    func linearGradient() {
        let drawn = canvasSurface(columns: 16, rows: 1) { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(Gradient(colors: [red, blue]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
        }
        let raster = drawn.raster
        #expect(raster[0, 0].red > 240 && raster[0, 0].blue < 15)
        #expect(raster[31, 0].blue > 240 && raster[31, 0].red < 15)
        #expect(abs(Int(raster[16, 0].red) - Int(raster[16, 0].blue)) < 30, "half way")
    }

    @Test("Mirror and repeat carry a ramp past its ends")
    func gradientOptions() {
        func ramp(_ options: GraphicsContext.GradientOptions) -> CanvasRaster {
            canvasSurface(columns: 8, rows: 1) { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [red, blue]), startPoint: .zero, endPoint: CGPoint(x: size.width / 2, y: 0), options: options))
            }.raster
        }
        #expect(ramp([])[15, 0].blue > 240, "held at its last stop")
        #expect(ramp(.repeat)[15, 0].blue > 200 && ramp(.repeat)[8, 0].red > 200, "starts again")
        #expect(ramp(.mirror)[15, 0].red > 200, "back to where it began")
    }

    @Test("A radial gradient measures in units, so its rings are round")
    func radialGradient() {
        let drawn = canvasSurface(columns: 8, rows: 4) { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [red, blue]), center: CGPoint(x: 4, y: 4), startRadius: 0, endRadius: 4))
        }
        let raster = drawn.raster
        #expect(raster[8, 4].red > 200, "the centre")
        // Three units right and three down of the centre are alike, though one
        // is six pixels across and the other three down.
        #expect(abs(Int(raster[14, 4].blue) - Int(raster[8, 7].blue)) < 40)
    }

    @Test("A conic gradient goes round clockwise from its angle")
    func conicGradient() {
        let drawn = canvasSurface(columns: 8, rows: 4) { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .conicGradient(Gradient(colors: [red, blue]), center: CGPoint(x: 4, y: 4)))
        }
        let raster = drawn.raster
        // Right of the centre is the start; a quarter round is below it.
        #expect(raster[15, 4].red > 200)
        #expect(raster[8, 7].blue > 40 && raster[8, 7].red > 100)
        #expect(raster[1, 4].blue > 100, "half way round")
    }

    @Test("The foreground shading is the view's foreground style")
    func foregroundShading() {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .foreground)
        }
        let cell = paintedCells(canvasDrawn(canvas.foregroundStyle(red)).lines[0])[0]
        #expect(cell.state.backgroundColour == .rgb(255, 0, 0))
    }

    @Test("A style's unit points are in the box of the path it paints")
    func styleShading() {
        let drawn = canvasSurface(columns: 8, rows: 1) { context, _ in
            context.fill(
                Path(CGRect(x: 2, y: 0, width: 4, height: 2)),
                with: .style(LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)))
        }
        let raster = drawn.raster
        #expect(raster[4, 0].red > 200, "red at the path's own left edge, not the canvas's")
        #expect(raster[11, 0].blue > 200, "blue at its right")
        #expect(raster[1, 0].alpha == 0, "nothing outside it")
    }

    // MARK: Clipping

    @Test("A clip keeps what falls inside it, and the inverse what falls outside")
    func clip() {
        let full = Path(CGRect(x: 0, y: 0, width: 4, height: 4))
        let left = Path(CGRect(x: 0, y: 0, width: 2, height: 4))
        let kept = canvasSurface { context, _ in
            context.clip(to: left)
            context.fill(full, with: .color(red))
        }
        #expect(canvasLetters(kept)[0] == "RRRR....")
        let cut = canvasSurface { context, _ in
            context.clip(to: left, options: .inverse)
            context.fill(full, with: .color(red))
        }
        #expect(canvasLetters(cut)[0] == "....RRRR")
    }

    @Test("Clips intersect, and a copy's clip is its own")
    func clipIsState() {
        let full = Path(CGRect(x: 0, y: 0, width: 4, height: 4))
        let drawn = canvasSurface { context, _ in
            var inner = context
            inner.clip(to: Path(CGRect(x: 0, y: 0, width: 2, height: 4)))
            inner.clip(to: Path(CGRect(x: 1, y: 0, width: 2, height: 4)))
            inner.fill(full, with: .color(red))
            context.fill(Path(CGRect(x: 3, y: 0, width: 1, height: 4)), with: .color(blue))
        }
        #expect(canvasLetters(drawn)[0] == "..RR..BB")
    }

    @Test("The clip's bounding rectangle is in the context's own coordinates")
    func clipBounds() {
        _ = canvasSurface { context, _ in
            #expect(context.clipBoundingRect == CGRect(x: 0, y: 0, width: 4, height: 4))
            context.clip(to: Path(CGRect(x: 1, y: 2, width: 2, height: 2)))
            #expect(context.clipBoundingRect == CGRect(x: 1, y: 2, width: 2, height: 2))
            context.translateBy(x: 1, y: 0)
            #expect(context.clipBoundingRect == CGRect(x: 0, y: 2, width: 2, height: 2))
        }
    }

    @Test("A layer can clip by what it draws")
    func clipToLayer() {
        let drawn = canvasSurface { context, _ in
            context.clipToLayer { layer in
                layer.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 4)), with: .color(blue))
            }
            context.fill(Path(CGRect(x: 0, y: 0, width: 4, height: 4)), with: .color(red))
        }
        #expect(canvasLetters(drawn)[0] == "RR......", "the layer's own colour is not drawn")
    }

    // MARK: Opacity, blending and layers

    @Test("Opacity fades a fill, and the cell states the alpha for the compositor")
    func opacity() {
        let drawn = canvasSurface(columns: 1, rows: 1) { context, _ in
            context.opacity = 0.5
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 2)), with: .color(red))
        }
        #expect(drawn.raster[0, 0] == CanvasRGBA(red: 255, green: 0, blue: 0, alpha: 128))
        #expect(drawn.pixelCells(monochrome: false)[0, 0].field?.alpha == 128)
    }

    @Test("An opaque colour over another replaces it; a translucent one mixes")
    func sourceOver() {
        let drawn = canvasSurface(columns: 1, rows: 1) { context, _ in
            let whole = Path(CGRect(x: 0, y: 0, width: 1, height: 2))
            context.fill(whole, with: .color(red))
            context.opacity = 0.5
            context.fill(whole, with: .color(blue))
        }
        let pixel = drawn.raster[0, 0]
        #expect(pixel.alpha == 255 && abs(Int(pixel.red) - 127) < 3 && abs(Int(pixel.blue) - 128) < 3)
    }

    @Test("Blend modes mix by the one table a view blends by, and the Porter-Duff ones weigh alpha")
    func blendModes() {
        func over(_ mode: GraphicsContext.BlendMode, source: Color = .rgb(128, 128, 128)) -> CanvasRGBA {
            canvasSurface(columns: 1, rows: 1) { context, _ in
                let whole = Path(CGRect(x: 0, y: 0, width: 1, height: 2))
                context.fill(whole, with: .color(red))
                context.blendMode = mode
                context.fill(whole, with: .color(source))
            }.raster[0, 0]
        }
        #expect(over(.multiply).red == 128 && over(.multiply).green == 0, "red times grey")
        #expect(over(.screen).red == 255 && over(.screen).green == 128)
        #expect(over(.difference).red == 127)
        #expect(over(.destinationOver) == opaqueRed, "what is there stays on top")
        #expect(over(.destinationOut).alpha == 0, "erased")
        #expect(over(.clear).alpha == 0)
        #expect(over(.copy) == CanvasRGBA(red: 128, green: 128, blue: 128, alpha: 255))
        #expect(over(.plusLighter, source: .rgb(0, 0, 255)) == CanvasRGBA(red: 255, green: 0, blue: 255, alpha: 255))
    }

    @Test("A Porter-Duff mode changes nothing outside the shape it draws")
    func porterDuffIsBoundedByTheShape() {
        let drawn = canvasSurface(columns: 2, rows: 1) { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 2)), with: .color(red))
            context.blendMode = .clear
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 2)), with: .color(blue))
        }
        #expect(canvasLetters(drawn)[0] == "..RR")
    }

    @Test("A layer lands as one drawing: its overlap is not twice as strong")
    func layerIsAGroup() {
        let drawn = canvasSurface(columns: 3, rows: 1) { context, _ in
            context.opacity = 0.5
            context.drawLayer { layer in
                layer.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 2)), with: .color(red))
                layer.fill(Path(CGRect(x: 1, y: 0, width: 2, height: 2)), with: .color(red))
            }
        }
        let raster = drawn.raster
        #expect(raster[0, 0].alpha == 128, "alone")
        #expect(raster[2, 0].alpha == 128, "the overlap")
    }

    @Test("Without a layer the same two fills do compound")
    func noLayerCompounds() {
        let drawn = canvasSurface(columns: 3, rows: 1) { context, _ in
            context.opacity = 0.5
            context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 2)), with: .color(red))
            context.fill(Path(CGRect(x: 1, y: 0, width: 2, height: 2)), with: .color(red))
        }
        #expect(drawn.raster[2, 0].alpha > 180)
    }

    @Test("An opaque canvas starts from its backdrop; a linear one mixes in linear light")
    func opaqueAndLinear() {
        let backdrop = CanvasRGBA(red: 10, green: 20, blue: 30, alpha: 255)
        #expect(canvasSurface(opaque: backdrop) { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .color(red))
        }.raster[7, 3] == backdrop)
        func grey(linear: Bool) -> UInt8 {
            canvasSurface(columns: 1, rows: 1, opaque: CanvasRGBA(red: 0, green: 0, blue: 0, alpha: 255), linear: linear) { context, _ in
                context.opacity = 0.5
                context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 2)), with: .color(white))
            }.raster[0, 0].red
        }
        #expect(abs(Int(grey(linear: false)) - 128) <= 1)
        #expect(abs(Int(grey(linear: true)) - 188) <= 1, "half the light is sRGB 188")
    }

    // MARK: Filters

    @Test("A colour filter colours what is drawn, in order")
    func colourFilter() {
        let drawn = canvasSurface(columns: 1, rows: 1) { context, _ in
            context.addFilter(.colorMultiply(.rgb(255, 0, 0)))
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 2)), with: .color(white))
        }
        #expect(drawn.raster[0, 0] == opaqueRed)
    }

    @Test("A blur spreads a drawing past its edge, and fades it")
    func blur() {
        let drawn = canvasSurface(columns: 12, rows: 1, grain: .halfBlocks) { context, _ in
            context.addFilter(.blur(radius: 1))
            context.fill(Path(CGRect(x: 3, y: 0, width: 2, height: 2)), with: .color(red))
        }
        let raster = drawn.raster
        #expect(raster[2, 0].alpha > 0, "past the edge")
        #expect(raster[3, 0].alpha < 255)
        #expect(raster[9, 0].alpha == 0, "not far past it")
    }

    @Test("A shadow lands offset beneath what cast it")
    func shadow() {
        let drawn = canvasSurface(columns: 4, rows: 2, grain: .halfBlocks) { context, _ in
            context.addFilter(.shadow(color: blue, radius: 0, x: 1, y: 1))
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .color(red))
        }
        #expect(canvasLetters(drawn)[0] == "R...")
        #expect(canvasLetters(drawn)[1] == ".B..")
    }

    @Test("A shadow alone leaves out what cast it")
    func shadowOnly() {
        let drawn = canvasSurface(columns: 4, rows: 2, grain: .halfBlocks) { context, _ in
            context.addFilter(.shadow(color: blue, radius: 0, x: 1, y: 1, options: .shadowOnly))
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .color(red))
        }
        #expect(canvasLetters(drawn)[0] == "....")
        #expect(canvasLetters(drawn)[1] == ".B..")
    }

    @Test("Luminance becomes alpha, and a threshold cuts by it")
    func alphaFilters() {
        let luminous = canvasSurface(columns: 1, rows: 1) { context, _ in
            context.addFilter(.luminanceToAlpha)
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 2)), with: .color(white))
        }
        #expect(luminous.raster[0, 0] == CanvasRGBA(red: 0, green: 0, blue: 0, alpha: 255))
        let cut = canvasSurface(columns: 2, rows: 1) { context, _ in
            context.addFilter(.alphaThreshold(min: 0.75, color: blue))
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 2)), with: .color(red))
            context.fill(Path(CGRect(x: 1, y: 0, width: 1, height: 2)), with: .color(red.opacity(0.5)))
        }
        #expect(canvasLetters(cut)[0] == "BB..")
    }

    @Test("A colour matrix computes each channel from all four")
    func colourMatrix() {
        var swap = ColorMatrix()
        (swap.r1, swap.r3, swap.b1, swap.b3) = (0, 1, 1, 0)
        let drawn = canvasSurface(columns: 1, rows: 1) { context, _ in
            context.addFilter(.colorMatrix(swap))
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 2)), with: .color(red))
        }
        #expect(drawn.raster[0, 0] == opaqueBlue)
    }
}
