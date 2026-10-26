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
    var owner: ObjectIdentifier?
    var pixels: ImagePaintPixels?
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
            default: decoded.map { .success($0.pixels) } ?? .loading)
        stateStorage.markActive(identity)
        let lastSourceBox: StateBox<ImageSource?> = stateStorage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: PaintStateIndex.lastSource), default: nil)
        // The load's lifecycle is a render's side effect, as the image's own
        // is: a measure only reads what has loaded.
        if !context.isMeasuring {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            manageLoadLifecycle(
                lifecycle: lifecycle, token: "image-paint-\(identity.path)", phaseBox: phaseBox,
                lastSourceBox: lastSourceBox,
                load: Self.LoadSettings(
                    maxPixelCount: context.environment.imageMaxPixelCount,
                    urlTimeout: context.environment.imageURLTimeout,
                    urlCache: context.environment.resolvedURLImageCache),
                imageStore: nil, loads: decoded == nil)
        }
        guard case .success(let image) = phaseBox.value else { return nil }
        let holder: StateBox<PaintPixelsHolder> = stateStorage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: PaintStateIndex.pixels),
            default: PaintPixelsHolder())
        let owner = decoded?.owner.map(ObjectIdentifier.init)
        let kept = holder.value
        if let pixels = kept.pixels, kept.source == source, kept.owner == owner { return pixels }
        let pixels = Self.paintPixels(
            image, pointSize: decoded?.pointSize(of: image) ?? (Double(image.width), Double(image.height)))
        kept.source = source
        kept.owner = owner
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
