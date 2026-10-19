//  🖥️ TUIkit — Terminal UI Kit for Swift
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
@testable import TUIkitBitmaps
import TUIkitImage

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

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

    /// A cell one point wide and two tall, so a point of the picture is a
    /// column across and half a row down: the 4-point tile is four columns by
    /// two rows.
    private static let cell = TerminalCellPoints(width: 1, height: 2)

    /// The colours `view` fills each cell of `rows` × `columns` with, a letter
    /// a cell — R, G, B, W, or `.` for none.
    private func fields(_ view: some View, columns: Int = 8, rows: Int = 2, ink: Bool = false) -> [String] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        let context = RenderContext(
            availableWidth: columns, availableHeight: rows, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context) }
        return buffer.lines.prefix(rows).map { line in
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

    @Test("The pixels a paint holds are the same from frame to frame, so the paint compares equal")
    func pixelsKeptAcrossFrames() {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 8, availableHeight: 2, environment: environment, tuiContext: tui)
        func materialized() -> Paint {
            tui.stateStorage.beginRenderPass()
            defer { tui.stateStorage.endRenderPass() }
            return ImagePaint(image: Self.image).paint(in: environment).materializingImages(in: context)
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
