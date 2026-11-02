//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasViews.swift
//
//  How a `GraphicsContext`, which is nonisolated as SwiftUI's is, reaches the
//  views it draws, which only the main actor may touch.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIStyling
import TUIView

/// What a context asks of the views around it: to measure and draw a text, a
/// symbol or an image, which only the main actor may.
///
/// SwiftUI's context is nonisolated and its renderer closure may be, so a call
/// from one has no isolation to offer. A frame is always drawn on the main
/// actor, however: `MainActor.assumeIsolated` states that, and this class, being
/// isolated and so `Sendable`, is what may cross into it.
@MainActor
final class CanvasViews {
    private let context: RenderContext
    private let unitsPerRow: CGFloat
    /// The canvas's symbols: the members of its `symbols` content.
    private let symbols: [Subview]
    /// How many images have been asked for: each keeps its loading state at
    /// its own place among them.
    private var imageCount = 0

    /// - Parameters:
    ///   - context: The view's render context.
    ///   - unitsPerRow: How many of the context's units a row is tall.
    ///   - symbols: The canvas's symbols.
    init(context: RenderContext, unitsPerRow: CGFloat, symbols: [Subview] = []) {
        self.context = context
        self.unitsPerRow = unitsPerRow
        self.symbols = symbols
    }

    // MARK: Symbols

    /// The context a symbol is measured and drawn in: its keyboard and focus
    /// channels throwaways, as SwiftUI's symbols take no events.
    func symbolSize(at index: Int) -> ViewSize {
        measureChild(symbols[index], proposal: .unspecified, context: context.isolatedForBackground())
    }

    func symbolCells(at index: Int, width: Int, height: Int) -> FrameBuffer {
        renderChild(symbols[index], width: width, height: height, context: context.isolatedForBackground())
    }

    // MARK: Images

    /// The context the next image asked for keeps its loading state at, by its
    /// place among the images a frame asks for.
    func nextImageContext() -> RenderContext {
        imageCount += 1
        return context.withChildIdentity(erasedType: CanvasViews.self, key: "canvas-image-\(imageCount)")
    }

    /// `image`'s pixels, once they have loaded, and its size in the context's
    /// units. A symbol's size is the cells it draws in.
    func prepare(_ image: Image) -> (pixels: ImagePaintPixels?, size: CGSize) {
        let imageContext = nextImageContext()
        guard case .raster(let raster) = image.content else {
            let size = measureChild(image, proposal: .unspecified, context: imageContext)
            return (nil, CGSize(width: CGFloat(size.width), height: CGFloat(size.height) * unitsPerRow))
        }
        guard let pixels = raster.paintPixels(context: imageContext) else { return (nil, .zero) }
        return (pixels, Self.unitSize(of: pixels, environment: context.environment, unitsPerRow: unitsPerRow))
    }

    /// A picture's natural size, in the context's units.
    nonisolated static func unitSize(
        of pixels: ImagePaintPixels, environment: EnvironmentValues, unitsPerRow: CGFloat
    ) -> CGSize {
        let columns: Double
        let rows: Double
        if let points = environment.imageCellPoints {
            columns = pixels.pointWidth / points.width
            rows = pixels.pointHeight / points.height
        } else {
            let cell = environment.imageCellPixels
            columns = Double(pixels.width) / Double(cell.width)
            rows = Double(pixels.height) / Double(cell.height)
        }
        return CGSize(width: CGFloat(columns), height: CGFloat(rows) * unitsPerRow)
    }

    /// A symbol image as the cells it draws in.
    func cells(of image: Image, width: Int, height: Int) -> FrameBuffer {
        renderChild(image, width: max(1, width), height: max(1, height), context: nextImageContext())
    }

    // MARK: Text

    /// `text`'s size in cells, offered `width` by `height`: `nil` is its own.
    func size(of text: Text, width: Int?, height: Int?) -> ViewSize {
        measureChild(text, proposal: ProposedSize(width: width, height: height), context: textContext())
    }

    /// `text` as the cells it draws in, in `shading` where it has one.
    func cells(of text: Text, shading: GraphicsContext.Shading?, width: Int?, height: Int?) -> FrameBuffer {
        var drawingContext = textContext()
        if let shading {
            switch shading.kind {
            case .color(let color): drawingContext.environment.foregroundStyle = .color(color)
            case .paint(let paint): drawingContext.environment.foregroundStyle = paint
            default: break
            }
        }
        let size = measureChild(text, proposal: ProposedSize(width: width, height: height), context: drawingContext)
        return renderChild(text, width: width ?? size.width, height: height ?? size.height, context: drawingContext)
    }

    /// The context text is measured and drawn in, a step of its own.
    private func textContext() -> RenderContext {
        context.withChildIdentity(erasedType: CanvasViews.self, key: "canvas-text")
    }
}
