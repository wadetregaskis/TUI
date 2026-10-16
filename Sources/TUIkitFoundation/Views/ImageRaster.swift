//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageRaster.swift
//
//  What an `Image` draws when it is a picture rather than a symbol: a value
//  the bitmap path makes, which the image hands its own options and asks to
//  measure and draw itself.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The picture

/// The picture an ``Image`` draws when it is not a symbol: a value the bitmap
/// path makes — ``Image/init(_:)`` from a file or a URL, the bundle and
/// asset-catalogue initialisers, an ``AsyncImage``'s loaded pixels — which
/// loads, measures and draws itself.
///
/// `Image` is one type with two unrelated contents, as SwiftUI's is, and only
/// the picture needs the decoders, the ASCII converter and the terminal's
/// graphics. Once TUIkit is split into modules, `Image` sits with the views
/// every app uses, and the bitmap path in a module above them that `Image`
/// cannot name. So `Image` holds its picture as this value, made where the
/// bitmap path is, and draws it through ``_ImageRasterHost``: the value carries
/// its implementation, and nothing is injected through the environment or
/// registered anywhere.
///
/// No requirement has a default, deliberately. A default equality would make
/// every picture equal to every other — a memo above serving a stale image —
/// or to none, a memo that never hits; a default measure or draw would draw
/// nothing. Each would fail silently, so each conformer says what it does.
package protocol _ImageRaster: Sendable {
    /// Whether `other` is the same picture: the same kind of value, naming the
    /// same source. Pixels already decoded are not part of it — they are what
    /// the source decodes to — so an image compares equal to itself before
    /// and after its pixels arrive, as it did when `Image` stored them itself.
    func isEqual(to other: any _ImageRaster) -> Bool

    /// The size the picture takes when offered `proposal`, drawn as `options`
    /// say — ``Layoutable/sizeThatFits(proposal:context:)`` for the picture.
    @MainActor
    func sizeThatFits(proposal: ProposedSize, options: _ImageRasterOptions, context: RenderContext) -> ViewSize

    /// The picture, drawn as `options` say in the space `context` offers —
    /// ``Renderable/renderToBuffer(context:)`` for the picture.
    @MainActor
    func renderToBuffer(options: _ImageRasterOptions, context: RenderContext) -> FrameBuffer
}

/// What an image's own modifiers ask of its picture: everything an ``Image``
/// stores beside its content.
package struct _ImageRasterOptions: Equatable, Sendable {
    /// Whether the picture draws as a template, its coverage in the foreground
    /// colour (``Image/renderingMode(_:)``).
    package var isTemplate: Bool

    /// How the picture fills its frame, or `nil` for an image that was not
    /// made resizable (``Image/resizable(capInsets:resizingMode:)``).
    package var resizing: _ImageResizing?

    /// The supersampling factor ``Image/interpolation(_:)`` or
    /// ``Image/antialiased(_:)`` asks for, or `nil` to take the environment's
    /// (``View/imageSupersampling(_:)``).
    package var samplingFactor: Int?
}

// MARK: - The host

/// Draws an image's picture: measures and renders by asking its
/// ``_ImageRaster``, with what the image's own modifiers said.
///
/// The picture draws at this view's identity and keeps its state there, in the
/// slots `_ImageCore`'s `StateIndex` names (0 to 3). The host keeps none of its
/// own, so those slots are the picture's alone, as they were the core's when
/// `Image`'s body drew the core itself.
struct _ImageRasterHost: View, Renderable, Layoutable {
    /// The picture.
    let raster: any _ImageRaster

    /// What the image's own modifiers asked of it.
    let options: _ImageRasterOptions

    var body: Never {
        fatalError("_ImageRasterHost renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        raster.sizeThatFits(proposal: proposal, options: options, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = raster.renderToBuffer(options: options, context: context)
        // Where the picture is, for a screen selection over it, which tints a
        // picture's cells rather than repainting them as text
        // (`HitTestRegion.pictureCorners`). A measure draws nowhere.
        if !context.isMeasuring, !buffer.isEmpty {
            buffer.hitTestRegions += HitTestRegion.pictureCorners(width: buffer.width, height: buffer.height)
        }
        return buffer
    }
}
