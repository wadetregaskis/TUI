//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore+CachedPixels.swift
//
//  A picture the image cache keeps (`ImageLoadingPhase.cached`): its pixels
//  held while the view is drawn, read back from the cache after, and what the
//  view last drew of it while it loads again.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIImage

// MARK: - Pixel Pin

/// The pixels of a picture the image cache keeps (``ImageLoadingPhase/cached(_:)``),
/// held by the view while it is drawn, and let go when it disappears.
///
/// So a picture on screen is never at the cache's mercy — a page of more
/// pictures than the cache holds draws every one of them, each frame, as it
/// did when the view's phase held them — while a row scrolled out of a long
/// list keeps a handle, not its pixels: those are the cache's, bounded in
/// bytes, and read back when the row is drawn again. A class changed in place,
/// so neither holding nor letting go asks for a frame.
final class ImagePixelPin {
    private(set) var decode: ImageDecodeID?
    private(set) var image: RGBAImage?

    /// The pixels of `picture`, while held for it.
    func pixels(of picture: CachedPicture) -> RGBAImage? {
        decode === picture.decode ? image : nil
    }

    func hold(_ image: RGBAImage, of picture: CachedPicture) {
        decode = picture.decode
        self.image = image
    }

    /// Holds what a load landed with, if the cache keeps it: from here, not
    /// from the frame that first draws it. By that frame the cache may have
    /// filed another load's decode over this one, or evicted it, and a view
    /// that has appeared does not load again.
    func hold(_ load: _ImageCore.FinishedLoad) {
        if case .cached(let picture) = load.phase, let pixels = load.pixels { hold(pixels, of: picture) }
    }

    func release() {
        decode = nil
        image = nil
    }
}

// MARK: - Drawing a Cached Picture

extension _ImageCore {
    /// What a load comes back with.
    struct FinishedLoad: Sendable {
        /// The phase to publish.
        let phase: ImageLoadingPhase
        /// The pixels it decoded, or `nil` if it failed, for the view to hold
        /// until it has drawn them when `phase` leaves them to the cache.
        var pixels: RGBAImage?
    }

    /// The box holding this view's ``ImagePixelPin``.
    func pixelPin(context: RenderContext) -> StateBox<ImagePixelPin> {
        context.stateStorage!.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: Self.pinStateIndex),
            default: ImagePixelPin())
    }

    /// `phase` as the render draws it, and what keys its conversion where
    /// that is not the loaded buffer: a picture the cache keeps is drawn as
    /// one loaded — its pixels held by the view, or read back from the cache
    /// and held from now on, while the view is drawn — and keyed by the decode
    /// the cache filed it as. `nil` once the cache has let it go while the
    /// view was not drawn.
    func drawablePhase(
        _ phase: ImageLoadingPhase, pin: ImagePixelPin, context: RenderContext
    ) -> (ImageLoadingPhase, DecodedPixels?)? {
        guard case .cached(let picture) = phase else { return (phase, nil) }
        guard
            let image = pin.pixels(of: picture) ?? decoded?.landedPixels(of: picture)
                ?? picture.pixels(in: context.environment.resolvedURLImageCache)
        else { return nil }
        if !context.isMeasuring {
            pin.hold(image, of: picture)
            decoded?.letGoOfLandedPixels()
        }
        return (.success(image), DecodedPixels(decode: picture.decode))
    }

    /// Whether `phase` has no pixels to draw: still loading, or a picture the
    /// cache has let go of.
    static func needsPixels(_ phase: ImageLoadingPhase, cache: URLImageCache?) -> Bool {
        switch phase {
        case .loading: true
        case .cached(let picture): picture.pixels(in: cache) == nil
        case .success, .failure: false
        }
    }

    /// What this view last drew of `picture` as glyphs, when it still fits a
    /// `width` × `height` box: drawn while the picture reloads after the
    /// cache let it go, so a row that comes back shows what it showed rather
    /// than its placeholder. `nil` for a picture last drawn otherwise — sent to
    /// the terminal, which let it go when the row disappeared — or not at all.
    func lastDrawing(
        of phase: ImageLoadingPhase, width: Int, height: Int, context: RenderContext
    ) -> FrameBuffer? {
        guard case .cached(let picture) = phase else { return nil }
        let box: StateBox<ImageRenderCache?>? = context.stateStorage?.existingStorage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: Self.renderCacheStateIndex))
        guard let box, let drawn = box.value, drawn.source == source,
            drawn.decodedPixels == DecodedPixels(decode: picture.decode), drawn.width <= width, drawn.height <= height
        else { return nil }
        let colorMode = context.environment.imageColorMode.resolved(with: context.environment.palette)
        return Self.buffer(for: drawn.art, monoColours: ImageMonoColours(for: colorMode, in: context.environment))
    }
}
