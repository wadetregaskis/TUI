//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasImageTests.swift
//
//  Pictures drawn on a `Canvas`: through the module seam from TUIFoundation's
//  context to this module's decoded pixels, read back from the cells.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUIApp
@testable import TUIBitmaps
@testable import TUIFoundation
import TUIImage
@testable import TUITestSupport

@MainActor
@Suite("Canvas: drawing images")
struct CanvasImageTests {
    /// Two pixels by two: red and green above, blue and white below.
    private static let quadrants = RGBAImage(
        width: 2, height: 2,
        pixels: [
            RGBA(r: 255, g: 0, b: 0), RGBA(r: 0, g: 255, b: 0),
            RGBA(r: 0, g: 0, b: 255), RGBA(r: 255, g: 255, b: 255),
        ])

    private static var picture: Image {
        Image(.url("tuikit-test://canvas-quadrants"), decoded: _DecodedImage(quadrants))
    }

    /// `canvas` at the cell grain, as a letter a cell: the field's colour.
    private func fields(_ canvas: some View, columns: Int, rows: Int) -> [String] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2
        let context = RenderContext(availableWidth: columns, availableHeight: rows, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(canvas.canvasGrain(.cells), context: context) }
        return buffer.lines.map { line in
            String(
                paintedCells(line).map { cell in
                    switch cell.state.backgroundColour {
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

    @Test("An image fills the rectangle it is drawn in, stretched to it")
    func stretched() {
        let canvas = Canvas { context, _ in
            context.draw(Self.picture.interpolation(.none), in: CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        #expect(fields(canvas, columns: 6, rows: 2) == ["RRGG..", "BBWW.."])
    }

    @Test("A transform turns an image, as it could not turn a glyph")
    func rotated() {
        let canvas = Canvas { context, _ in
            context.translateBy(x: 2, y: 2)
            context.rotate(by: .degrees(180))
            context.draw(Self.picture.interpolation(.none), in: CGRect(x: -2, y: -2, width: 4, height: 4))
        }
        #expect(fields(canvas, columns: 4, rows: 2) == ["WWBB", "GGRR"])
    }

    @Test("A resolved image knows its size, and is drawn at it by its anchor")
    func atItsOwnSize() {
        var size = CGSize.zero
        let canvas = Canvas { context, _ in
            let resolved = context.resolve(Self.picture.interpolation(.none))
            size = resolved.size
            context.draw(resolved, at: CGPoint(x: 1, y: 0), anchor: .topLeading)
        }
        _ = fields(canvas, columns: 4, rows: 2)
        #expect(size.width > 0 && size.height > 0)
    }

    @Test("A template image draws its shape in the shading")
    func template() {
        let canvas = Canvas { context, _ in
            var resolved = context.resolve(Self.picture.renderingMode(.template))
            resolved.shading = .color(.rgb(0, 0, 255))
            context.draw(resolved, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        #expect(fields(canvas, columns: 2, rows: 1) == ["BB"])
    }

    @Test("A tiled image repeats from its origin")
    func tiled() {
        let canvas = Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .tiledImage(Self.picture.interpolation(.none), sourceRect: CGRect(x: 0, y: 0, width: 1, height: 0.5)))
        }
        let drawn = fields(canvas, columns: 4, rows: 1)
        #expect(drawn[0].contains("R") || drawn[0].contains("G"), "\(drawn)")
    }

    @Test("An image paint as a style is its pixels")
    func imagePaintStyle() {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .style(ImagePaint.image(Self.picture)))
        }
        #expect(fields(canvas, columns: 2, rows: 1)[0].allSatisfy { $0 != "." })
    }
}
