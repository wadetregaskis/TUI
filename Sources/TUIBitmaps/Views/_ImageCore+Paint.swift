//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore+Paint.swift
//
//  A picture's pixels for an `ImagePaint`: loaded as the image itself loads
//  them, at the paint's own identity, and converted once.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIImage

/// Named property indices for a paint's picture, at the identity the paint
/// draws it under — a child of whatever draws with the paint, so none of its
/// own state is shared.
private enum PaintStateIndex {
    /// The loading phase (`ImageLoadingPhase`), as `_ImageCore` keeps it.
    static let phase = 0
    /// The last source loaded, for change detection (`ImageSource?`).
    static let lastSource = 1
    /// The pixels as last converted (`PaintPixelsHolder`).
    static let pixels = 2
}

/// A paint's pixels as last converted, and what they were converted from.
///
/// A class held in a state box and changed in place, so keeping it asks for
/// no frame: a box's write invalidates its view.
private final class PaintPixelsHolder {
    var source: ImageSource?
    /// The object the pixels were drawn out of (``_DecodedImage/owner``),
    /// KEPT, as `_ImageCore`'s owner box keeps it: its address names the
    /// picture in `source`, and a freed address can come straight back for a
    /// different picture. Holding only the address, these pixels outlived the
    /// object, and a new picture at the old address matched both fields and
    /// was handed the old pixels. Kept, no other picture can take the address
    /// while the pixels stand for it.
    var owner: AnyObject?
    /// Which pixels they were converted from: a picture the cache keeps is
    /// named by its decode, so they stand for it after the cache has let it
    /// go, and an edited file loaded again under the same path is another.
    var convertedFrom: DecodedPixels?
    var pixels: ImagePaintPixels?

    /// The pixels, where they were converted from `from` for `source` and
    /// `owner`.
    func pixels(from: DecodedPixels, source: ImageSource, owner: AnyObject?) -> ImagePaintPixels? {
        guard convertedFrom == from, self.source == source, self.owner === owner else { return nil }
        return pixels
    }
}

extension _ImageCore {
    /// This picture's pixels for an ``ImagePaint`` drawn in `context`, or
    /// `nil` while they load.
    ///
    /// Loaded as ``Image`` loads its own — on a task, the load cancelled when
    /// nothing draws with the paint any more — with the state at `context`'s
    /// identity, and converted to ``ImagePaintPixels`` once, the same object
    /// handed back every frame until the picture changes, so the paint holding
    /// them compares equal from frame to frame.
    @MainActor
    func paintPixels(context: RenderContext) -> ImagePaintPixels? {
        guard let stateStorage = context.stateStorage, let lifecycle = context.environment.lifecycle else {
            return decoded.map { Self.paintPixels($0.pixels, pointSize: $0.pointSize(of: $0.pixels)) }
        }
        let identity = context.identity
        let phaseBox: StateBox<ImageLoadingPhase> = stateStorage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: PaintStateIndex.phase),
            default: decoded?.phase ?? .loading)
        stateStorage.markActive(identity)
        let lastSourceBox: StateBox<ImageSource?> = stateStorage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: PaintStateIndex.lastSource), default: nil)
        let holder: StateBox<PaintPixelsHolder> = stateStorage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: PaintStateIndex.pixels),
            default: PaintPixelsHolder())
        let kept = holder.value
        let owner = decoded?.owner
        let cache = context.environment.resolvedURLImageCache
        let token = "image-paint-\(identity.path)"
        // The load's lifecycle is a render's side effect, as the image's own
        // is: a measure only reads what has loaded.
        if !context.isMeasuring {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            // A picture the cache let go of before the paint converted it,
            // which nothing else holds: loaded again, as a view that has
            // appeared loads nothing more. Without this the paint drew nothing
            // from then on (hunt H-96, IMAGE-6). Loading, not the picture let
            // go, while it loads: otherwise each frame until it lands would
            // find it let go again, and start the load over.
            if decoded == nil, case .cached(let picture) = phaseBox.value,
                kept.pixels(from: DecodedPixels(decode: picture.decode), source: source, owner: owner) == nil,
                picture.pixels(in: cache) == nil
            {
                phaseBox.value = .loading
                lifecycle.resetAppearance(token: token)
            }
            manageLoadLifecycle(
                lifecycle: lifecycle, token: token, phaseBox: phaseBox,
                lastSourceBox: lastSourceBox,
                load: Self.LoadSettings(
                    maxPixelCount: context.environment.imageMaxPixelCount,
                    urlTimeout: context.environment.imageURLTimeout,
                    urlCache: cache,
                    synchronousDecodeLimit: context.environment.imageSynchronousDecodeLimit),
                imageStore: nil, loads: decoded == nil)
        }
        // What the holder converted is looked for first: a picture the cache
        // keeps is read back from it only to convert, so the paint goes on
        // drawing it after the cache has let it go.
        let image: RGBAImage
        let from: DecodedPixels
        switch phaseBox.value {
        case .success(let held):
            image = held
            from = DecodedPixels(held)
        case .reduced(let picture):
            image = picture.image
            from = DecodedPixels(picture.image)
        case .cached(let picture):
            from = DecodedPixels(decode: picture.decode)
            if let pixels = kept.pixels(from: from, source: source, owner: owner) { return pixels }
            guard let held = picture.pixels(in: cache) else { return nil }
            image = held
        case .loading, .failure: return nil
        }
        if let pixels = kept.pixels(from: from, source: source, owner: owner) { return pixels }
        let pixels = Self.paintPixels(
            image, pointSize: decoded?.pointSize(of: image) ?? (Double(image.width), Double(image.height)))
        kept.source = source
        kept.owner = owner
        kept.convertedFrom = from
        kept.pixels = pixels
        return pixels
    }

    /// `image` as a paint samples it, its size in points `pointSize`.
    private static func paintPixels(
        _ image: RGBAImage, pointSize: (width: Double, height: Double)
    ) -> ImagePaintPixels {
        var rgba: [UInt8] = []
        rgba.reserveCapacity(image.pixels.count * 4)
        for pixel in image.pixels {
            rgba.append(pixel.r)
            rgba.append(pixel.g)
            rgba.append(pixel.b)
            rgba.append(pixel.a)
        }
        return ImagePaintPixels(
            width: image.width, height: image.height, rgba: rgba, pointWidth: pointSize.width,
            pointHeight: pointSize.height)
    }
}
