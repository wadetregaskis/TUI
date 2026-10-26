//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+Raster.swift
//
//  An `Image` of a picture loaded from a file or a URL: its initialisers, and
//  the picture it holds, which `_ImageCore` loads, converts and draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension Image {
    /// Creates an image from the given source.
    ///
    /// - Parameter source: The image source (file or URL).
    public init(_ source: ImageSource) {
        self.init(source, decoded: nil)
    }

    /// An image of `source` whose pixels are already decoded, so it draws
    /// them rather than loading the source again: an ``AsyncImage``'s success
    /// phase, an asset-catalogue picture drawn at another scale than 1, an
    /// AppKit image. `source` still names the picture, to a memo that compares
    /// images; `decoded` is what it decodes to.
    package init(_ source: ImageSource, decoded: _DecodedImage?) {
        self.init(raster: _SourcedImageRaster(source: source, decoded: decoded))
    }
}

/// The picture of an ``Image`` made from a source, drawn by `_ImageCore`.
struct _SourcedImageRaster: _ImageRaster {
    /// Where the picture loads from, and what names it.
    let source: ImageSource

    /// The source's pixels when they are already decoded, so nothing is
    /// loaded — see ``Image/init(_:decoded:)``. Not part of equality: it is
    /// what the source decodes to.
    let decoded: _DecodedImage?

    func isEqual(to other: any _ImageRaster) -> Bool {
        guard let other = other as? Self else { return false }
        return source == other.source
    }

    @MainActor
    func sizeThatFits(proposal: ProposedSize, options: _ImageRasterOptions, context: RenderContext) -> ViewSize {
        let core = self.core(options)
        guard let samplingFactor = options.samplingFactor else {
            return core.sizeThatFits(proposal: proposal, context: context)
        }
        return Self.sampled(core, by: samplingFactor).sizeThatFits(proposal: proposal, context: context)
    }

    @MainActor
    func renderToBuffer(options: _ImageRasterOptions, context: RenderContext) -> FrameBuffer {
        let core = self.core(options)
        guard let samplingFactor = options.samplingFactor else {
            return core.renderToBuffer(context: context)
        }
        return Self.sampled(core, by: samplingFactor).renderToBuffer(context: context)
    }

    @MainActor
    func paintPixels(context: RenderContext) -> ImagePaintPixels? {
        _ImageCore(source: source, decoded: decoded).paintPixels(context: context)
    }

    /// The core that draws this picture as `options` say.
    @MainActor
    private func core(_ options: _ImageRasterOptions) -> _ImageCore {
        _ImageCore(source: source, decoded: decoded, isTemplate: options.isTemplate, resizing: options.resizing)
    }

    /// `core` under the image's own supersampling factor: the environment
    /// modifier `Image`'s body wrapped the core in when it drew the core
    /// itself. So the factor reaches the core as it did, at the core's own
    /// identity, and the modifier's cache bookkeeping still sees it change.
    @MainActor
    private static func sampled(_ core: _ImageCore, by factor: Int) -> EnvironmentModifier<_ImageCore, Int?> {
        EnvironmentModifier(content: core, keyPath: \.imageSupersampling, value: factor)
    }
}
