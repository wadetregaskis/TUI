//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore+Reduction.swift
//
//  A file's picture kept at the size it is drawn, not the size it is: decoded
//  at a power-of-two fraction of it for the box it is drawn in, and decoded
//  again when the box needs another (owner, 2026-11-09, PICTURES (b)).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation
import TUIImage

// MARK: - What a View Knows of Its File

/// What a view knows of its file's picture beyond its phase: its size, read
/// from the file's header, and the reduction a task is decoding it at.
///
/// The size is what a picture not yet decoded is laid out as, and what decides
/// how far it can be reduced before it is: a header read, no decode, made once
/// for each version of the file (its cache key). A class changed in place, as
/// ``ImagePixelPin`` is, so neither asks for a frame.
final class FileDecodeState {
    private var key: String?
    private var limit: Int?
    private var size: (width: Int, height: Int)?

    /// The reduction a task started by a change of box is decoding the picture
    /// at, so that a frame wanting the same does not start it again. Set by
    /// the task when it runs, not when it is asked for: a drawing the walk
    /// discards never starts its task, and would leave this saying one runs.
    var loadingReduction: Int?

    /// What the converter reads of each cell under the settings it was last
    /// asked for (``samplesPerCell(characterSet:shapeAware:supersampling:)``).
    private var grid: (characterSet: ASCIICharacterSet, shapeAware: Bool, supersampling: Int?, perCell: (x: Int, y: Int))?

    /// ``ASCIIConverter/samplesPerCell`` for these settings, worked out again
    /// only when they change: a frame asks it of every picture it draws, and a
    /// glyph ramp's levels are sorted out of its whole repertoire to answer.
    func samplesPerCell(
        characterSet: ASCIICharacterSet, shapeAware: Bool, supersampling: Int?
    ) -> (x: Int, y: Int) {
        if let grid, grid.characterSet == characterSet, grid.shapeAware == shapeAware,
            grid.supersampling == supersampling
        {
            return grid.perCell
        }
        let perCell = ASCIIConverter(characterSet: characterSet, shapeAware: shapeAware, supersampling: supersampling)
            .samplesPerCell
        grid = (characterSet, shapeAware, supersampling, perCell)
        return perCell
    }

    /// The picture's size, read with `read` the first time it is asked for
    /// under `key` and `limit` (the file and the pixel limit it was read
    /// under), `nil` where the read failed.
    func size(
        forKey key: String, limit: Int?, read: () -> (width: Int, height: Int)?
    ) -> (width: Int, height: Int)? {
        if self.key != key || self.limit != limit {
            self.key = key
            self.limit = limit
            size = read()
        }
        return size
    }
}

// MARK: - How Far a Picture Is Reduced

extension _ImageCore {
    /// The box holding this view's ``FileDecodeState``.
    func fileDecodeState(context: RenderContext) -> StateBox<FileDecodeState>? {
        context.stateStorage?.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: Self.fileDecodeStateIndex),
            default: FileDecodeState())
    }

    /// The size of this view's file's picture, whole, read from its header
    /// (``PlatformImageLoader/pictureSize(atPath:maxPixelCount:)``) — `nil` for
    /// a URL, an image that came decoded, a file that cannot be read, or one
    /// past the pixel limit, which its load will say.
    func headerSize(context: RenderContext) -> (width: Int, height: Int)? {
        guard decoded == nil, case .file(let path) = source, let key = CachedPicture.key(of: source),
            let state = fileDecodeState(context: context)
        else { return nil }
        let limit = context.environment.imageMaxPixelCount
        return state.value.size(forKey: key, limit: limit) {
            try? PlatformImageLoader().pictureSize(atPath: path, maxPixelCount: limit)
        }
    }

    /// The reduction this view's file's picture of `size` pixels is decoded
    /// at to be drawn into `space`, and the size, or 1 and `nil` where it is
    /// decoded whole: a URL, an image that came decoded, a file whose size
    /// cannot be read.
    ///
    /// `phase` is the view's, and `lastSource` what it was loaded from: a
    /// phase left from another source says nothing about this one's size.
    func reducedLoad(
        phase: ImageLoadingPhase, lastSource: ImageSource?, space: (width: Int, height: Int), zoom: Double,
        context: RenderContext
    ) -> (reduction: Int, size: (width: Int, height: Int)?) {
        guard decoded == nil, case .file = source else { return (1, nil) }
        let current = lastSource == nil || lastSource == source ? phase : .loading
        // A load that failed has nothing to size until its source changes.
        if case .failure = current { return (1, nil) }
        guard let size = current.pictureSize ?? headerSize(context: context) else { return (1, nil) }
        let reduction = reduction(
            ofPicture: size, in: space, zoom: zoom, environment: context.environment,
            state: fileDecodeState(context: context)?.value)
        return (reduction, size)
    }

    /// How far a picture of `size` pixels, drawn into `space` cells at
    /// `zoom`, can be reduced and still have every pixel its drawing reads:
    /// a power of two (``PlatformImageLoader/reduction(of:covering:)``), 1
    /// where it is drawn as large as it is.
    ///
    /// What a drawing reads is the cells the whole picture covers — its
    /// natural box, which a space too small cuts, or the box it is fitted or
    /// filled to — times what each cell reads: the converter's own sample
    /// grid (``ASCIIConverter/samplesPerCell``), which follows the character
    /// set, shape matching and supersampling, so a picture is never drawn from
    /// fewer pixels than the glyphs it becomes can show. Where the terminal
    /// may be sent the picture itself (Kitty, iTerm2, Sixel), a cell reads its
    /// size in the terminal's pixels instead where that is more: the same
    /// rule, a picture's pixels sized to the pixel box it is drawn in, as the
    /// transmission already sizes what it sends (``pixelSize(of:fitting:)``).
    ///
    /// Never reduced: an image in slices, whose caps are cut in its own
    /// pixels, and anything but a file.
    func reduction(
        ofPicture size: (width: Int, height: Int), in space: (width: Int, height: Int), zoom: Double,
        environment: EnvironmentValues, state: FileDecodeState? = nil
    ) -> Int {
        guard decoded == nil, case .file = source, effectiveResizing(in: environment)?.slices != true else { return 1 }
        let cells = wholeCells(ofPixels: size, in: space, zoom: zoom, environment: environment)
        let characterSet = environment.imageCharacterSet
        let shapeAware = environment.imageShapeAware
        let supersampling = environment.imageSupersampling
        var perCell =
            state?.samplesPerCell(characterSet: characterSet, shapeAware: shapeAware, supersampling: supersampling)
            ?? ASCIIConverter(characterSet: characterSet, shapeAware: shapeAware, supersampling: supersampling)
            .samplesPerCell
        if !isTemplate, KittyGraphics.isSupported, environment.terminalGraphics, environment.terminalImageStore != nil {
            let cell = environment.imageCellPixels
            perCell = (max(perCell.x, cell.width), max(perCell.y, cell.height))
        }
        let neededWidth: Int = cells.width * perCell.x
        let neededHeight: Int = cells.height * perCell.y
        return PlatformImageLoader.reduction(of: size, covering: (neededWidth, neededHeight))
    }

    /// The cells a picture of `size` pixels is drawn across whole in `space`
    /// at `zoom`: ``drawing(_:laidOutAs:in:zoom:environment:)``'s box, before
    /// any cut — its natural box zoomed, or the box it fits or fills.
    func wholeCells(
        ofPixels size: (width: Int, height: Int), in space: (width: Int, height: Int), zoom: Double,
        environment: EnvironmentValues
    ) -> (width: Int, height: Int) {
        if let natural = naturalBox(ofPixels: size, in: environment) {
            return (Self.zoomed(natural.width, zoom), Self.zoomed(natural.height, zoom))
        }
        return Self.cellBox(
            imageWidth: size.width, imageHeight: size.height, maxWidth: space.width, maxHeight: space.height,
            stretches: effectiveResizing(in: environment) != nil, contentMode: environment.imageContentMode,
            aspectRatio: environment.imageAspectRatio, cellAspect: environment.imageCellAspect)
    }
}

// MARK: - Decoding at a Size

extension _ImageCore {
    /// The file at `path` loaded at `settings.reduction` of its size, through
    /// the cache, which keeps each reduction under its own key
    /// (``CachedPicture/key(of:reducedBy:)``).
    ///
    /// - Throws: `ImageLoadError` if the file cannot be read, decoded, or is
    ///   past the pixel limit.
    nonisolated static func decodeFile(path: String, settings: LoadSettings) throws -> FinishedLoad {
        let source = ImageSource.file(path)
        guard settings.reduction > 1 else {
            let image = try PlatformImageLoader().loadImage(
                from: path, cache: settings.urlCache, maxPixelCount: settings.maxPixelCount)
            return FinishedLoad(phase: .loaded(image, from: source, cache: settings.urlCache), pixels: image)
        }
        // A picture the cache holds at this size, whose size the view read from
        // the header within the limit: no decode.
        if let size = settings.pictureSize, let key = CachedPicture.key(of: source, reducedBy: settings.reduction),
            let held = settings.urlCache?.get(key)
        {
            return FinishedLoad(
                phase: .loaded(held, from: source, cache: settings.urlCache, size: size, reduction: settings.reduction),
                pixels: held)
        }
        let picture = try PlatformImageLoader().loadImage(
            from: path, maxPixelCount: settings.maxPixelCount, reducedBy: settings.reduction)
        if let cache = settings.urlCache, let key = CachedPicture.key(of: source, reducedBy: settings.reduction) {
            cache.set(key, image: picture.image)
        }
        let size = (width: picture.width, height: picture.height)
        return FinishedLoad(
            phase: .loaded(
                picture.image, from: source, cache: settings.urlCache, size: size, reduction: settings.reduction),
            pixels: picture.image)
    }

    /// Loads the picture again at `settings.reduction`, its box needing
    /// another size than the one it holds: from the cache, or decoded on this
    /// frame for a small file, or in a task for a larger one, the view drawing
    /// what it holds — scaled — until it lands.
    ///
    /// Both ways: a picture drawn larger needs more pixels than it holds, and
    /// one drawn smaller keeps fewer than it holds. Only across a power of
    /// two (``PlatformImageLoader/reduction(of:covering:)``), and the cache
    /// keeps each size it has decoded, so a box moving back and forth across
    /// one finds its pixels there.
    func reloadAtNewSize(
        settings: LoadSettings, phaseBox: StateBox<ImageLoadingPhase>, state: FileDecodeState,
        lifecycle: LifecycleManager, token: String, pin: ImagePixelPin?
    ) {
        guard case .file(let path) = source, state.loadingReduction != settings.reduction else { return }
        if let landed = Self.cachedPhase(
            of: source, cache: settings.urlCache, maxPixelCount: settings.maxPixelCount,
            reduction: settings.reduction, size: settings.pictureSize)
            ?? Self.smallFilePhase(path: path, settings: settings)
        {
            lifecycle.cancelTask(token: token)
            state.loadingReduction = nil
            phaseBox.value = landed
            return
        }
        let source = self.source
        let reduction = settings.reduction
        lifecycle.startTask(token: token, priority: .userInitiated) {
            await MainActor.run { state.loadingReduction = reduction }
            guard let loaded = await Self.loadPhase(source: source, settings: settings) else { return }
            await MainActor.run {
                // As the first load's: a cancellation that arrives during the
                // hop is honoured here, last, before the write.
                guard !Task.isCancelled else { return }
                state.loadingReduction = nil
                pin?.hold(loaded)
                phaseBox.value = loaded.phase
            }
        }
    }
}
