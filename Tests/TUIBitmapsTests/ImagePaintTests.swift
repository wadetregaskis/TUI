//  🖥️ TUI — A Terminal UI framework for Swift
//  ImagePaintTests.swift
//
//  `ImagePaint` and `ShapeStyle.image(_:sourceRect:scale:)`: a region of an
//  image repeated from the top-leading corner of what is filled, a tile its
//  size in points over the cell's, as SwiftUI repeats it (measured on macOS
//  15.8, `Tools/SwiftUIProbes/Image paint/`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
@testable import TUIBitmaps
import TUIImage

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Image paint")
struct ImagePaintTests {
    /// 4 × 4 pixels, a point each: red top-leading, green top-trailing, blue
    /// bottom-leading, white bottom-trailing, each quarter 2 × 2.
    private static let quadrants = RGBAImage(
        width: 4, height: 4,
        pixels: (0..<16).map { index in
            switch (index % 4 < 2, index / 4 < 2) {
            case (true, true): RGBA(r: 255, g: 0, b: 0)
            case (false, true): RGBA(r: 0, g: 255, b: 0)
            case (true, false): RGBA(r: 0, g: 0, b: 255)
            case (false, false): RGBA(r: 255, g: 255, b: 255)
            }
        })

    private static var image: Image {
        Image(.url("tuikit-test://quadrants"), decoded: _DecodedImage(quadrants))
    }

    /// 2 × 2 pixels, all white: a second picture, to tell two paints apart.
    private static var white: Image {
        let pixels = RGBAImage(width: 2, height: 2, pixels: Array(repeating: RGBA(r: 255, g: 255, b: 255), count: 4))
        return Image(.url("tuikit-test://white"), decoded: _DecodedImage(pixels))
    }

    /// A cell one point wide and two tall, so a point of the picture is a
    /// column across and half a row down: the 4-point tile is four columns by
    /// two rows.
    private static let cell = TerminalCellPoints(width: 1, height: 2)

    /// The colours `view` fills each cell of `rows` × `columns` with, a letter
    /// a cell — R, G, B, W, or `.` for none.
    private func fields(_ view: some View, columns: Int = 8, rows: Int = 2, ink: Bool = false) -> [String] {
        let tui = TUIContext()
        let context = Self.context(tui, columns: columns, rows: rows)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context) }
        return letters(buffer, columns: columns, rows: rows, ink: ink)
    }

    /// A context of `columns` × `rows` on `tui`, its cell twice as tall as wide.
    private static func context(_ tui: TUIContext, columns: Int, rows: Int) -> RenderContext {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        return RenderContext(availableWidth: columns, availableHeight: rows, environment: environment, tuiContext: tui)
    }

    /// The colours of `buffer`'s cells — their fields, or their `ink` — a
    /// letter a cell, as ``fields(_:columns:rows:ink:)`` spells them.
    private func letters(_ buffer: FrameBuffer, columns: Int, rows: Int, ink: Bool) -> [String] {
        buffer.lines.prefix(rows).map { line in
            String(
                paintedCells(line).prefix(columns).map { cell in
                    switch ink ? cell.ink : cell.state.backgroundColour {
                    case .rgb(255, 0, 0): "R"
                    case .rgb(0, 255, 0): "G"
                    case .rgb(0, 0, 255): "B"
                    case .rgb(255, 255, 255): "W"
                    case nil: "."
                    default: "?"
                    }
                })
        }
    }

    @Test("A fill repeats the picture from its top-leading corner, a tile its size in points over the cell's")
    func repeatsFromTheCorner() {
        let rectangle = Rectangle().fill(ImagePaint(image: Self.image)).imageCellPoints(Self.cell)
        #expect(fields(rectangle) == ["RRGGRRGG", "BBWWBBWW"])
        // A shape drawn in its own cells repeats it alike.
        let rounded = RoundedRectangle(cornerRadius: 0).fill(.image(Self.image)).imageCellPoints(Self.cell)
        #expect(fields(rounded) == ["RRGGRRGG", "BBWWBBWW"])
    }

    @Test("The scale grows the tile, and the source rectangle chooses the part of the picture repeated")
    func scaleAndSourceRect() {
        let doubled = Rectangle().fill(.image(Self.image, scale: 2)).imageCellPoints(Self.cell)
        #expect(fields(doubled, rows: 4) == ["RRRRGGGG", "RRRRGGGG", "BBBBWWWW", "BBBBWWWW"])
        let trailing = Rectangle()
            .fill(.image(Self.image, sourceRect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
            .imageCellPoints(Self.cell)
        #expect(fields(trailing) == ["GGGGGGGG", "WWWWWWWW"])
    }

    @Test("A rectangle given with in(_:) moves where the tiles start, and its size changes nothing")
    func inMovesTheTileOrigin() {
        let paint = ImagePaint(image: Self.image)
        let anchored = Rectangle().fill(paint.in(CellRect(x: 2, y: 1, width: 8, height: 4))).imageCellPoints(Self.cell)
        #expect(fields(anchored) == ["WWBBWWBB", "GGRRGGRR"])
        let sized = Rectangle().fill(paint.in(CellRect(x: 0, y: 0, width: 40, height: 1))).imageCellPoints(Self.cell)
        #expect(fields(sized) == ["RRGGRRGG", "BBWWBBWW"])
        // A background's tiles move alike, and an origin past any screen draws.
        let background = Text(String(repeating: " ", count: 8))
            .background(paint.in(CellRect(x: 1, y: 0, width: 1, height: 1))).imageCellPoints(Self.cell)
        #expect(fields(background, rows: 1) == ["GRRGGRRG"])
        let far = Rectangle().fill(paint.in(CellRect(x: .min, y: .max, width: 1, height: 1))).imageCellPoints(Self.cell)
        #expect(fields(far).allSatisfy { $0.count == 8 && !$0.contains(".") })
    }

    @Test("Where the cell's size is not known, one tile spans what is filled, across")
    func unknownCellSpansTheFill() {
        let rectangle = Rectangle().fill(.image(Self.image))
        #expect(fields(rectangle, rows: 4) == ["RRRRGGGG", "RRRRGGGG", "BBBBWWWW", "BBBBWWWW"])
    }

    @Test("A background, and the letters of a text, take the picture as a fill does")
    func backgroundAndForeground() {
        let background = Text(String(repeating: " ", count: 8)).background(.image(Self.image))
            .imageCellPoints(Self.cell)
        #expect(fields(background, rows: 1) == ["RRGGRRGG"])
        let letters = Text("########").foregroundStyle(ImagePaint(image: Self.image)).imageCellPoints(Self.cell)
        #expect(fields(letters, rows: 1, ink: true) == ["RRGGRRGG"])
    }

    @Test("A fade draws the picture at its strength")
    func faded() {
        let paint = ImagePaint(image: Self.image).paint(in: EnvironmentValues()).faded(0.5)
        guard case .image(let source) = paint else {
            Issue.record("not an image paint: \(paint)")
            return
        }
        #expect(source.opacity == 0.5)
    }

    @Test("A picture that has not loaded paints nothing")
    func unloadedPaintsNothing() {
        let image = Image(.file("/nonexistent/tuikit-image-paint.png"))
        #expect(fields(Rectangle().fill(.image(image))) == ["........", "........"])
    }

    @Test("Two image paints drawn at one view each paint, and a still screen asks for no further frame")
    func twoPaintsAtOneView() {
        // Each pair draws at one identity: a style and the background around
        // it, or two backgrounds with a padding between. Their pictures loaded
        // into one set of state boxes, so each found the other's the last one
        // loaded and wrote the phase back — and a write asks for a frame.
        let letters = Text("########").foregroundStyle(.image(Self.image)).background(.image(Self.white))
            .imageCellPoints(Self.cell)
        let backgrounds = Text("      ").background(.image(Self.image)).padding(.horizontal, 1)
            .background(.image(Self.white)).imageCellPoints(Self.cell)
        let cases: [(view: AnyView, ink: String?, field: String)] = [
            (AnyView(letters), "RRGGRRGG", "WWWWWWWW"), (AnyView(backgrounds), nil, "WRRGGRRW"),
        ]
        for (view, ink, field) in cases {
            let tui = TUIContext()
            let context = Self.context(tui, columns: 8, rows: 1)
            // Drawn a frame at a time, as the loop draws: the cache's pass
            // boundary first, which applies the state writes the frame before
            // made, counted as the subtrees they clear (`TabViewIdleRenderTests`).
            func frame() -> (buffer: FrameBuffer, drained: Int) {
                let before = tui.renderCache.stats.subtreeClears
                tui.renderCache.beginRenderPass()
                let drained = tui.renderCache.stats.subtreeClears - before
                tui.stateStorage.beginRenderPass()
                defer { tui.stateStorage.endRenderPass() }
                return (ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context) }, drained)
            }
            _ = frame()
            _ = frame()
            let (third, wrote) = frame()
            let (_, wroteNext) = frame()
            #expect(wrote == 0 && wroteNext == 0, "the second and third frames wrote state: \(wrote), \(wroteNext)")
            if let ink { #expect(self.letters(third, columns: 8, rows: 1, ink: true) == [ink]) }
            #expect(self.letters(third, columns: 8, rows: 1, ink: false) == [field])
        }
    }

    @Test("The pixels a paint holds are the same from frame to frame, so the paint compares equal")
    func pixelsKeptAcrossFrames() {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 8, availableHeight: 2, environment: environment, tuiContext: tui)
        func materialized() -> Paint {
            tui.stateStorage.beginRenderPass()
            defer { tui.stateStorage.endRenderPass() }
            return ImagePaint(image: Self.image).paint(in: environment).materializingImages(
                in: context, owner: Self.self)
        }
        let first = materialized()
        let second = materialized()
        #expect(first == second)
        guard case .image(let source) = first else {
            Issue.record("not an image paint")
            return
        }
        #expect(source.pixels?.width == 4)
    }
}
