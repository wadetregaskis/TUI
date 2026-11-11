//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation
import TUIImage

// MARK: - State Indices

/// Named property indices for `_ImageCore` state storage.
private enum StateIndex {
    /// Stores the loading phase (`ImageLoadingPhase`).
    static let phase = 0

    /// Stores the last loaded source for change detection (`ImageSource`).
    static let lastSource = 1

    /// Stores the most recent ASCII conversion output and its parameters,
    /// so the next render at the same size + settings reuses the cached
    /// glyph buffer instead of re-running `ASCIIConverter.convert`.
    static let renderCache = 2

    /// Keeps the object a decoded image was drawn out of (`_DecodedImage?`) —
    /// see ``_DecodedImage/owner``.
    static let decodedOwner = 3

    /// The picture's box and the frame it was first drawn in at that size
    /// (``PictureSettle``), for its resend at the box's exact size once it holds
    /// still.
    static let settle = 4

    /// The pixels of a picture the cache keeps, held while the view is drawn
    /// (``ImagePixelPin``).
    static let pin = 5

    /// A playing picture's frames and what has been made of them
    /// (``ImageAnimationPlayback``).
    static let animation = 6

    /// What a measure decoded of a picture no render pass has loaded yet
    /// (``MeasuredPicture``).
    static let measured = 7

    /// A file's picture's size from its header, and the reduction a task is
    /// decoding it at (``FileDecodeState``).
    static let fileDecodeState = 8
}

extension _ImageCore {
    /// ``StateIndex/settle``, for `PictureSettle` in its own file.
    static let settleStateIndex = StateIndex.settle
    /// ``StateIndex/renderCache`` and ``StateIndex/pin``, for the cached
    /// pixels' drawing in its own file.
    static let renderCacheStateIndex = StateIndex.renderCache
    static let pinStateIndex = StateIndex.pin
    static let measuredStateIndex = StateIndex.measured
    /// ``StateIndex/animation``, for the playing picture in its own file.
    static let animationStateIndex = StateIndex.animation
    /// ``StateIndex/fileDecodeState``, for the reduced decode in its own file.
    static let fileDecodeStateIndex = StateIndex.fileDecodeState
}

// MARK: - Image Core

/// Private rendering implementation for ``Image``.
///
/// Handles async image loading, caching, and placeholder display.
/// The raw `RGBAImage` is cached in state; ASCII conversion happens
/// on every render pass so that environment changes (character set,
/// color mode, dithering) take effect immediately.
struct _ImageCore: View, Renderable, Layoutable {
    /// The image source.
    let source: ImageSource

    /// The source's pixels when they are already decoded, so nothing is
    /// loaded — see ``Image/init(_:decoded:)``.
    var decoded: _DecodedImage?

    /// Whether the image draws as a template: its pixels' coverage in the
    /// foreground colour (``Image/renderingMode(_:)``).
    var isTemplate = false

    /// How the image fills its frame when it is resizable — see
    /// ``Image/resizable(capInsets:resizingMode:)``.
    var resizing: _ImageResizing?

    var body: Never {
        fatalError("_ImageCore renders via Renderable")
    }

    // MARK: - Layoutable

    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        let environment = context.environment
        // Already finite, positive and bounded: the environment's setter is
        // the one place that rule lives. Any positive zoom is honoured; the
        // rendered size is floored at one cell (see `zoomed`), so even a
        // 1/512 zoom shrinks gracefully to a single cell instead of vanishing.
        let zoom = environment.imageZoom

        // Reading the phase box is a pure lookup (no mutation that matters
        // during a measure pass).
        // Only the picture's size in pixels: a picture the cache keeps is laid
        // out without its pixels.
        let loaded: (width: Int, height: Int)? = environment.stateStorage.flatMap { stateStorage in
            let phaseKey = StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.phase)
            let phaseBox: StateBox<ImageLoadingPhase> = stateStorage.storage(
                for: phaseKey, default: decoded?.phase ?? .loading)
            // Still loading, a picture the cache holds is the one the render
            // pass about to follow will draw (``cachedPhase(of:cache:maxPixelCount:)``).
            var phase = phaseBox.value
            // A source changed since the view last drew: the box still holds the
            // OLD picture's phase, which that render pass resets
            // (``manageLoadLifecycle``) before it draws. Measured as the reset
            // phase, so the new picture is laid out at its own size, not the old
            // one's: a viewer stepping from photo to photo drew each new one in
            // the last one's box for a frame, and then snapped it to its own
            // (the Images clip, 2026-10-29).
            let lastSource: StateBox<ImageSource?> = stateStorage.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.lastSource),
                default: nil)
            if let last = lastSource.value, last != source {
                phase = decoded?.phase ?? .loading
            }
            // A picture the cache holds, or a small file the render pass will
            // decode on this frame (``smallFilePhase(path:settings:)``):
            // measured at its own size, not the placeholder's, so its first
            // frame is laid out as every later one. A file's size is read from
            // its header, nothing decoded (``measuredSize(context:)``): the
            // render decodes it for the box this measure answers.
            if case .loading = phase {
                return measuredSize(context: context).flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
            }
            guard let size = phase.pictureSize else { return nil }
            guard size.width > 0, size.height > 0 else { return nil }
            return size
        }

        // Its own size, whatever it is offered, where it has one — and before
        // the box below, whose viewport read would keep a memo above from
        // storing a size that does not depend on it.
        if let loaded, let natural = naturalBox(ofPixels: loaded, in: environment) {
            return .fixed(Self.zoomed(natural.width, zoom), Self.zoomed(natural.height, zoom))
        }

        // The box the image scales to fit: the visible viewport (when requested and
        // available) or the size the layout proposes. `.viewport` is what lets an
        // image fill the visible area at zoom 1 and overflow (scroll) only once
        // zoomed in, even though a ScrollView measures content against an unbounded
        // canvas.
        //
        // Under a scroll view that scrolls HORIZONTALLY, an axis offered as the
        // probe's budget — thousands of cells, which an image aspect-fitted to
        // and was drawn the size of a wall — is the viewport's instead
        // (``viewportCap(_:offer:)``).
        let fitWidth: Int
        let fitHeight: Int
        if environment.imageFitTarget == .viewport, let viewport = environment.scrollViewportSize {
            fitWidth = viewport.width
            fitHeight = viewport.height
        } else {
            let proposedWidth = proposal.width ?? context.availableWidth
            let proposedHeight = proposal.height ?? context.availableHeight
            let cap = Self.viewportCap(environment, offer: (proposedWidth, proposedHeight))
            fitWidth = cap.width ?? proposedWidth
            fitHeight = cap.height ?? proposedHeight
        }

        // Once the image has loaded, report the SAME aspect-fitted size the renderer
        // produces (height follows from width × aspect ratio), then apply zoom.
        if let loaded {
            let fitted = Self.cellBox(
                imageWidth: loaded.width, imageHeight: loaded.height,
                maxWidth: fitWidth, maxHeight: fitHeight,
                stretches: effectiveResizing(in: environment) != nil,
                contentMode: environment.imageContentMode,
                aspectRatio: environment.imageAspectRatio,
                cellAspect: environment.imageCellAspect)
            return .fixed(Self.zoomed(fitted.width, zoom), Self.zoomed(fitted.height, zoom))
        }

        // Before it loads, the aspect ratio is unknown — reserve a bounded
        // placeholder box (the terminal's cell aspect) rather than the full
        // offered height, so an unbounded offer can't balloon to thousands of
        // lines.
        let cellAspect = environment.imageCellAspect > 0 ? environment.imageCellAspect : 2.0
        let placeholderHeight = min(fitHeight, max(1, Int(Double(fitWidth) / cellAspect)))
        return .fixed(Self.zoomed(fitWidth, zoom), Self.zoomed(placeholderHeight, zoom))
    }

    /// The viewport's extent on each axis the offer does not bound, under a
    /// scroll view that scrolls horizontally — or `nil`, the offer standing.
    ///
    /// SwiftUI sizes a resizable image offered nothing at its natural pixel
    /// size, and a terminal has no size in cells to give it: pixels are not
    /// cells, and how many make one depends on the font. A scroll view that
    /// scrolls horizontally asks its content how big it would be if nothing
    /// stopped it — the probe's budget across, and down — so on an axis
    /// offered that, the image fits what the person can see instead, as
    /// ``ImageFitTarget/viewport`` fits it explicitly.
    ///
    /// Only an unbounded axis: a `.frame(width: 300)` offers a real 300 and is
    /// 300 wide however narrow the viewport, while the height it leaves open
    /// is the viewport's. And only while measuring, which is the only time the
    /// budget is offered: the render is handed the size the measure answered,
    /// so the two agree without the render reading the viewport. A vertical
    /// scroll view bounds the width, so there the image is width driven and
    /// scrolls at full size, as it always has.
    ///
    /// Reads the viewport only when an axis is unbounded: the read is volatile,
    /// and keeps any memo above from storing the image's size.
    private static func viewportCap(_ environment: EnvironmentValues, offer: (width: Int, height: Int))
        -> (width: Int?, height: Int?)
    {
        guard environment.asksWholeContentWidth else { return (nil, nil) }
        let unboundedWidth = isNaturalExtentBudget(offer.width)
        let unboundedHeight = isNaturalExtentBudget(offer.height)
        guard unboundedWidth || unboundedHeight, let viewport = environment.scrollViewportSize else {
            return (nil, nil)
        }
        return (unboundedWidth ? viewport.width : nil, unboundedHeight ? viewport.height : nil)
    }

    /// Multiplies a cell dimension by the zoom factor (rounded, floored at 1).
    static func zoomed(_ value: Int, _ factor: Double) -> Int {
        factor == 1 ? value : max(1, Int((Double(value) * factor).rounded()))
    }

    // MARK: - Renderable

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let stateStorage = context.stateStorage!
        let lifecycle = context.environment.lifecycle!
        let identity = context.identity

        let (width, height) = (context.availableWidth, context.availableHeight)

        guard width > 0, height > 0 else { return FrameBuffer() }

        // Read environment values
        let placeholderText = context.environment.imagePlaceholderText
        let spinner = context.environment.imagePlaceholderSpinner
        let maxPixelCount = context.environment.imageMaxPixelCount
        let urlTimeout = context.environment.imageURLTimeout

        // Retrieve or create persistent phase state
        let phaseKey = StateStorage.StateKey(identity: identity, propertyIndex: StateIndex.phase)
        let phaseBox: StateBox<ImageLoadingPhase> = stateStorage.storage(
            for: phaseKey, default: decoded?.phase ?? .loading)
        stateStorage.markActive(identity)
        let pin = pixelPin(context: context)
        // What a measure decoded: drawn by a view only ever measured (a tab's
        // label), and handed to the render pass's load otherwise.
        let measured = context.isMeasuring ? nil : takeMeasuredPhase(context: context)

        // Track the last loaded source to detect changes
        let sourceKey = StateStorage.StateKey(identity: identity, propertyIndex: StateIndex.lastSource)
        let lastSourceBox: StateBox<ImageSource?> = stateStorage.storage(for: sourceKey, default: nil)

        // Build a unique token for this image source
        let token = "image-\(identity.path)"

        // The image renders into the fit box scaled by zoom — mirroring
        // `sizeThatFits`, so what's measured is what's drawn. For a `.viewport`
        // fit the base is the (unzoomed) published viewport, so zooming OUT
        // shrinks the image below the viewport (and zooming IN grows it past it);
        // otherwise the laid-out available size already reflects the zoom.
        // `zoomed` floors at one cell, so even a 1/512 zoom stays renderable.
        // Sanitised by the environment's setter; see `sizeThatFits`.
        let zoom = context.environment.imageZoom
        let renderWidth: Int
        let renderHeight: Int
        if context.environment.imageFitTarget == .viewport,
            let viewport = context.environment.scrollViewportSize {
            renderWidth = Self.zoomed(viewport.width, zoom)
            renderHeight = Self.zoomed(viewport.height, zoom)
        } else {
            renderWidth = width
            renderHeight = height
        }
        // A file's picture is decoded for this box, at a power-of-two fraction
        // of its size where it is drawn smaller than it is
        // (``reduction(ofPicture:in:zoom:environment:)``).
        let reduced = reducedLoad(
            phase: phaseBox.value, lastSource: lastSourceBox.value, space: (renderWidth, renderHeight), zoom: zoom,
            context: context)

        // Lifecycle and phase mutations are RENDER-pass side effects. An
        // ancestor that measures by rendering (a Card's container measure, a
        // multi-line Table cell probe) runs this body with `isMeasuring` set —
        // it must not reset a loaded image back to `.loading` on a source
        // change, start a load for a measured-but-never-shown branch (a
        // ViewThatFits rejected candidate), or register appear/disappear
        // handlers for it. The measure pass still reads the current phase below
        // so what's measured is what's drawn.
        if !context.isMeasuring {
            // Declared as a side effect, as `LifecycleModifier` declares its
            // own: the appearance record is per-frame presence, and a
            // memoized row serving its cached cells skips this body — the
            // token then vanishes from the frame's visible set and
            // `endRenderPass` fires the disappear handler for an image still
            // on screen, deleting it from the terminal or cancelling its
            // decode. The memos decline a buffer that declares this.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            manageLoadLifecycle(
                lifecycle: lifecycle, token: token,
                phaseBox: phaseBox, lastSourceBox: lastSourceBox,
                load: LoadSettings(
                    maxPixelCount: maxPixelCount, urlTimeout: urlTimeout,
                    urlCache: context.environment.resolvedURLImageCache,
                    synchronousDecodeLimit: context.environment.imageSynchronousDecodeLimit,
                    reduction: reduced.reduction, pictureSize: reduced.size),
                imageStore: context.environment.terminalImageStore, pin: pin.value,
                playback: animationPlayback(context: context).value, loads: decoded == nil, measured: measured,
                fileState: reduced.size == nil ? nil : fileDecodeState(context: context)?.value)
            // Written only when the owner changes, as the source is: a write
            // asks for a frame.
            let ownerBox: StateBox<_DecodedImage?> = stateStorage.storage(
                for: StateStorage.StateKey(identity: identity, propertyIndex: StateIndex.decodedOwner),
                default: nil)
            if ownerBox.value?.owner !== decoded?.owner { ownerBox.value = decoded }
        }

        // A picture the cache keeps draws as one held here, its pixels read
        // back from the cache — and held while the view is drawn — and keyed by
        // the decode the cache filed them as rather than by their buffer.
        // Reloading what the cache let go of (``manageLoadLifecycle``): until
        // it lands, what the view last drew of it, where that still fits.
        var held = phaseBox.value
        if context.isMeasuring, case .loading = held,
            let kept = measuredPhase(context: context, reduction: reduced.reduction, size: reduced.size)
        {
            held = kept
        }
        guard case let (phase, decodedPixels, canvas)? = drawablePhase(held, pin: pin.value, context: context) else {
            return lastDrawing(of: phaseBox.value, width: renderWidth, height: renderHeight, context: context)
                ?? renderPlaceholder(
                    width: renderWidth, height: renderHeight, text: placeholderText, spinner: spinner, context: context)
        }

        // Render based on current phase
        switch phase {
        case .loading, .cached, .reduced:
            let placeholder = renderPlaceholder(
                width: renderWidth, height: renderHeight, text: placeholderText, spinner: spinner, context: context)
            return watchingVisibility(of: placeholder, context: context)

        case .success(let loadedImage):
            return renderSuccess(
                loadedImage, decodedPixels: decodedPixels, canvas: canvas, renderWidth: renderWidth,
                renderHeight: renderHeight, zoom: zoom, token: token, context: context)

        case .failure(let message):
            return renderError(message, width: renderWidth, height: renderHeight, context: context)
        }
    }

    /// `canvas` is the size `loadedImage` is laid out as where its pixels
    /// were decoded smaller (``ImageLoadingPhase/reduced(_:)``), as a playing
    /// picture's frames are laid out as the file (``PlayingFrame/canvas``).
    private func renderSuccess(
        _ loadedImage: RGBAImage,
        decodedPixels: DecodedPixels?,
        canvas: (width: Int, height: Int)?,
        renderWidth: Int,
        renderHeight: Int,
        zoom: Double,
        token: String,
        context: RenderContext
    ) -> FrameBuffer {
        let characterSet = context.environment.imageCharacterSet
        let shapeAware = context.environment.imageShapeAware
        let colorMode = context.environment.imageColorMode.resolved(
            with: context.environment.palette)
        let dithering = context.environment.imageDithering
        let contentMode = context.environment.imageContentMode
        let aspectRatioOverride = context.environment.imageAspectRatio

        // The file's current frame, if it plays: drawn in the still's place,
        // and in the still's box.
        let playing = playingFrame(token: token, context: context)
        // What is drawn into which box: at its natural size, the image's
        // own box; otherwise the box it was handed, to fit or fill.
        let laidOut = playing?.canvas ?? canvas
        let (rawImage, drawWidth, drawHeight, resizing, keepsAspect) = drawing(
            playing?.image ?? loadedImage, laidOutAs: laidOut, in: (renderWidth, renderHeight), zoom: zoom,
            environment: context.environment)
        // Real pixels first, where the terminal will take them. Falls
        // through to the glyph renderer for every terminal that did not
        // answer the startup handshake, every subtree that asked for
        // glyphs, and every request the protocol cannot express — which is
        // why this is an `if let` and not a branch: the fallback is not an
        // error path, it is the path this framework has always taken.
        // A template is drawn as cells: its pixels are recoloured, and a
        // picture of them would be one more thing to keep current.
        // So is an image in slices: its pixels are made for the box.
        let monoColours = ImageMonoColours(for: colorMode, in: context.environment)
        let picture: FrameBuffer
        // Each keyed on which load its pixels are (`DecodedPixels`): the
        // LOADED buffer, not the drawn one, which a crop makes every frame.
        let decodedPixels = playing.map { DecodedPixels(decode: $0.decode) } ?? decodedPixels ?? DecodedPixels(loadedImage)
        if !isTemplate, resizing?.slices != true, let drawn = renderWithTerminalGraphics(
            rawImage, decodedPixels: decodedPixels, width: drawWidth, height: drawHeight,
            stretches: resizing != nil && !keepsAspect, canvas: laidOut, playing: playing, context: context)
        {
            picture = drawn
        } else {
            playing?.keepFramesHereForGlyphs(token: token, context: context)
            picture = renderImage(
                rawImage, decodedPixels: decodedPixels, width: drawWidth, height: drawHeight,
                characterSet: characterSet, shapeAware: shapeAware, colorMode: colorMode, dithering: dithering,
                toneCurve: context.environment.imageToneCurve?.resolved(
                    with: context.environment.palette),
                supersampling: context.environment.imageSupersampling, edgeThreshold: context.environment.imageEdgeThreshold,
                edgeContrast: context.environment.imageEdgeContrast,
                inkThreshold: context.environment.imageInkThreshold,
                adjustments: context.environment.imageAdjustments, posterizationLevels: context.environment.imagePosterization,
                contentMode: contentMode, aspectRatioOverride: aspectRatioOverride,
                cellAspect: context.environment.imageCellAspect,
                monoColours: monoColours,
                templateInk: isTemplate ? Self.templateInk(in: context.environment) : nil,
                resizing: resizing,
                canvas: laidOut,
                playing: playing,
                stateStorage: context.stateStorage!,
                identity: context.identity
            )
        }
        // A picture drawn in the foreground style — a template's pixels, a
        // mono picture's ink — casts a shadowed style's shadows from the
        // cells it drew (`ShapeStyle.shadow(_:)`).
        let paint = isTemplate || monoColours != nil ? context.environment.foregroundStyle : nil
        let shaded = paint.map { picture.castingShadows(of: $0, context: context, owner: Self.self) } ?? picture
        return watchingVisibility(of: shaded, context: context)
    }
}

// MARK: - Load Lifecycle

extension _ImageCore {
    /// What a load reads of the environment, read on the main actor during
    /// the render and handed to the decode, which runs off it.
    struct LoadSettings: Sendable {
        /// The largest picture, in pixels, the load accepts.
        let maxPixelCount: Int?
        /// How long a download may take, in seconds.
        let urlTimeout: Double
        /// The cache a load goes through (`resolvedURLImageCache`), a URL's
        /// or a file's, or `nil`.
        let urlCache: URLImageCache?
        /// The largest file decoded on the frame that first draws it
        /// (`imageSynchronousDecodeLimit`); 0 for none.
        var synchronousDecodeLimit = 0
        /// The power of two a file's picture is decoded at a fraction of its
        /// size by, for the box it is drawn in; 1 for the picture whole.
        var reduction = 1
        /// The file's picture's size, read from its header, where it is
        /// decoded for its box: `nil` for a URL or a picture decoded whole.
        var pictureSize: (width: Int, height: Int)?
    }

    /// Render-pass-only load management: resets the phase on a source change,
    /// starts the load task on first appearance, and registers the
    /// cancel-on-disappear handler. Split from `renderToBuffer` so the
    /// `!isMeasuring` gate wraps one call (and the body stays within the
    /// function-length limit).
    func manageLoadLifecycle(
        lifecycle: LifecycleManager,
        token: String,
        phaseBox: StateBox<ImageLoadingPhase>,
        lastSourceBox: StateBox<ImageSource?>,
        load settings: LoadSettings,
        imageStore: TerminalImageStore?,
        pin: ImagePixelPin? = nil,
        playback: ImageAnimationPlayback? = nil,
        loads: Bool,
        measured: ImageLoadingPhase? = nil,
        fileState: FileDecodeState? = nil
    ) {
        // Detect source change and force reload
        if let lastSource = lastSourceBox.value, lastSource != source {
            lifecycle.cancelTask(token: token)
            lifecycle.resetAppearance(token: token)
            fileState?.loadingReduction = nil
            // Pixels that came with the image are the new phase: nothing is
            // going to load them.
            phaseBox.value = decoded?.phase ?? .loading
        }
        // Only on an actual change. `StateBox.value.didSet` invalidates
        // unconditionally — it cannot compare, since `Value` is not constrained
        // to `Equatable` — so re-recording the same source every render asked
        // for a frame that would be identical to the one being drawn. The loop
        // is demand-driven, so that request is honoured: an on-screen `Image`
        // held it at 2% CPU forever, writing zero bytes, because the diff
        // writer correctly found nothing to say. Measured with
        // `Tools/Profiling/idle-image.sh`.
        if lastSourceBox.value != source {
            lastSourceBox.value = source
        }

        // A row coming back after the cache let its picture go loads it again
        // from above, an `AsyncImage`'s load: a new decode under the same
        // source, which the phase has to follow, or the view goes on asking the
        // cache for the old one.
        if let decoded, case .cached(let held) = phaseBox.value, decoded.cachedPicture?.decode !== held.decode {
            phaseBox.value = decoded.phase
        }

        // Start loading on first appearance — unless the pixels came with
        // the image, already decoded.
        if !lifecycle.hasAppeared(token: token), loads {
            _ = lifecycle.recordAppear(token: token) {}

            // A picture the cache already holds draws on this, the view's
            // first frame, with no decode: a new view of a picture another
            // view showed — a navigation zoom's photo screen, a list row
            // scrolled back into view — drew a blank frame first, while a
            // task decoded the file again.
            //
            // So does a row coming back whose picture the cache has let go of
            // since it was drawn (``ImageLoadingPhase/cached(_:)``): it has
            // nothing to draw, as a view loading for the first time has not.
            // At any size the cache holds it: one drawn elsewhere at another
            // size draws now, and is loaded at this one's below.
            let needsPixels = Self.needsPixels(phaseBox.value, cache: settings.urlCache)
            if needsPixels,
                let cached = Self.cachedPhase(
                    of: source, cache: settings.urlCache, maxPixelCount: settings.maxPixelCount,
                    reduction: settings.reduction, size: settings.pictureSize, nearest: true)
            {
                phaseBox.value = cached
            } else if needsPixels, let measured {
                // A measure on this frame decoded it already.
                phaseBox.value = measured
            } else if needsPixels, case .file(let path) = source,
                let decoded = Self.smallFilePhase(path: path, settings: settings)
            {
                phaseBox.value = decoded
            } else {
                let src = source
                lifecycle.startTask(token: token, priority: .userInitiated) {
                    // Decode off the main actor (@concurrent guarantees it), then
                    // write the box ON it. The box's invalidation SINK is
                    // thread-safe, but the value itself is a plain property the
                    // render loop reads every frame — assigning a multi-word enum
                    // payload from a pool thread raced those reads (a torn read of
                    // the CoW pixel array is heap corruption, not a glitch). This
                    // is the one place the framework itself wrote @State off-main.
                    guard
                        let loaded = await Self.loadPhase(source: src, settings: settings)
                    else { return }
                    await MainActor.run {
                        // Cancellation is observed HERE, not (only) inside the
                        // decode. `loadPhase` returns nil when it notices — but a
                        // `.file` decode is synchronous with no cancellation
                        // points at all, so the flag `cancelTask` sets on a source
                        // change is never seen by it. Without this check the OLD
                        // task publishes its stale result whenever it finishes
                        // second, and the image the user switched away from
                        // replaces the one they switched to (or an error from the
                        // abandoned path lands on a view that loaded fine).
                        //
                        // Last thing before the write, so it also covers a cancel
                        // that arrives during the hop onto the main actor.
                        guard !Task.isCancelled else { return }
                        pin?.hold(loaded)
                        phaseBox.value = loaded.phase
                    }
                }
            }
        } else {
            _ = lifecycle.recordAppear(token: token) {}
        }

        // Pixels decoded for another box than this one: a box grown past what
        // they hold, or shrunk well inside it, loads the picture at its size.
        if loads, let fileState, let held = phaseBox.value.reduction, held != settings.reduction {
            reloadAtNewSize(
                settings: settings, phaseBox: phaseBox, state: fileState, lifecycle: lifecycle, token: token, pin: pin)
        }

        // Cancel loading task on disappear — and give the terminal its
        // memory back. A transmitted image is retained by the terminal until
        // something deletes it, and this is the only moment anything knows
        // the picture is not coming back.
        // And let go of the pixels the cache keeps: the view keeps a handle
        // until it is drawn again (``ImagePixelPin``).
        lifecycle.registerDisappear(token: token) { [lifecycle] in
            lifecycle.cancelTask(token: token)
            fileState?.loadingReduction = nil
            imageStore?.release(token: token)
            pin?.release()
            playback?.stop(token: token, lifecycle: lifecycle, store: imageStore)
        }
    }

    /// Loads and decodes the image, returning what to publish — or `nil`
    /// if the load was cancelled, which is not a phase: the view has left the
    /// tree (or its source changed), and a replacement task may already be
    /// running, so publishing anything here would either paint an error into a
    /// view nobody asked about any more or clobber the new load's result.
    ///
    /// Decoding is CPU-bound, so `@concurrent` keeps it off the main actor's
    /// executor no matter what context awaits it — the caller then publishes
    /// the result on the main actor, where every other `@State` write happens.
    @concurrent
    static func loadPhase(
        source: ImageSource, settings: LoadSettings
    ) async -> FinishedLoad? {
        let loader = PlatformImageLoader()
        do {
            let rawImage: RGBAImage
            switch source {
            case .file(let path):
                // At the size its box wants (``decodeFile(path:settings:)``).
                return try decodeFile(path: path, settings: settings)
            case .url(let urlString):
                rawImage = try await loader.loadImage(
                    fromURL: urlString,
                    cache: settings.urlCache,
                    timeout: settings.urlTimeout,
                    maxPixelCount: settings.maxPixelCount
                )
            }
            // Store the raw image — or where the cache keeps it, if it does;
            // conversion happens per render pass.
            return FinishedLoad(phase: .loaded(rawImage, from: source, cache: settings.urlCache), pixels: rawImage)
        } catch is CancellationError {
            return nil
        } catch let loadError as ImageLoadError {
            return FinishedLoad(phase: .failure(loadError.description))
        } catch {
            return FinishedLoad(phase: .failure(error.localizedDescription))
        }
    }
}

// MARK: - Image Rendering

extension _ImageCore {

    /// Converts the raw image to ASCII art for the current frame dimensions and settings.
    ///
    /// The conversion is cached in `StateStorage`: if the next render is
    /// passed the same image at the same target size with the same
    /// styling, the previous conversion's `[String]` is returned without
    /// re-running `ASCIIConverter.convert`. That converter is the
    /// hot spot of the renderer (especially in the shape-aware and
    /// `.braille` modes), and the typical TUI redraw cadence —
    /// spinner pulses, focus animations — re-renders an unchanged image
    /// many times per second.
    private func renderImage(  // swiftlint:disable:this function_parameter_count
        _ rawImage: RGBAImage,
        decodedPixels: DecodedPixels,
        width: Int,
        height: Int,
        characterSet: ASCIICharacterSet,
        shapeAware: Bool,
        colorMode: ASCIIColorMode,
        dithering: DitheringMode,
        toneCurve: ASCIIToneCurve?,
        supersampling: Int?,
        edgeThreshold: Double?,
        edgeContrast: Double,
        inkThreshold: Double?,
        adjustments: ImageAdjustments,
        posterizationLevels: Int?,
        contentMode: ContentMode,
        aspectRatioOverride: Double?,
        cellAspect: Double,
        monoColours: ImageMonoColours?,
        templateInk: RGBA?,
        resizing: _ImageResizing?,
        canvas: (width: Int, height: Int)?,
        playing: PlayingFrame?,
        stateStorage: StateStorage,
        identity: ViewIdentity
    ) -> FrameBuffer {
        let targetSize = Self.cellBox(
            imageWidth: canvas?.width ?? rawImage.width,
            imageHeight: canvas?.height ?? rawImage.height,
            maxWidth: width,
            maxHeight: height,
            stretches: resizing != nil,
            contentMode: contentMode,
            aspectRatio: aspectRatioOverride,
            cellAspect: cellAspect
        )

        guard targetSize.width > 0, targetSize.height > 0 else {
            return FrameBuffer()
        }

        // Check the per-view cache; if every conversion input matches,
        // skip the (potentially very expensive) re-conversion.
        // Read once, for the lookup and for the entry it may store: the colours
        // the conversion below measures the terminal's slots under.
        let terminalColors = TerminalColors.current
        // And the depth the converter downgrades the colour mode to, which it
        // reads from the same place as it converts.
        let colorDepth = ColorDepth.current
        let cacheKey = StateStorage.StateKey(identity: identity, propertyIndex: StateIndex.renderCache)
        let cacheBox: StateBox<ImageRenderCache?> = stateStorage.storage(for: cacheKey, default: nil)
        // A playing picture's conversions are kept per frame, and a frame's is
        // no write to the view's state, which would ask for a frame.
        let held = playing.map { $0.playback.conversion(ofFrame: $0.index) } ?? cacheBox.value
        if let cache = held, cache.matches(
            source: source,
            decodedPixels: decodedPixels,
            rawImageWidth: rawImage.width,
            rawImageHeight: rawImage.height,
            width: targetSize.width,
            height: targetSize.height,
            characterSet: characterSet,
            shapeAware: shapeAware,
            colorMode: colorMode,
            dithering: dithering,
            toneCurve: toneCurve,
            supersampling: supersampling,
            edgeThreshold: edgeThreshold,
            edgeContrast: edgeContrast,
            inkThreshold: inkThreshold,
            adjustments: adjustments,
            posterizationLevels: posterizationLevels,
            contentMode: contentMode,
            aspectRatioOverride: aspectRatioOverride,
            cellAspect: cellAspect,
            terminalColors: terminalColors,
            colorDepth: colorDepth,
            templateInk: templateInk,
            resizing: resizing
        ) {
            return Self.buffer(for: cache.art, monoColours: monoColours)
        }

        let converter = ASCIIConverter(
            characterSet: characterSet,
            shapeAware: shapeAware,
            colorMode: colorMode,
            dithering: dithering,
            supersampling: supersampling,
            edgeThreshold: edgeThreshold,
            toneCurve: toneCurve,
            edgeContrast: edgeContrast,
            inkThreshold: inkThreshold,
            adjustments: adjustments,
            posterizationLevels: posterizationLevels
        )
        var pixels = templateInk.map { rawImage.templated(in: $0) } ?? rawImage
        if let resizing, resizing.slices {
            pixels = pixels.sliced(
                resizing, columns: targetSize.width, rows: targetSize.height, cellAspect: cellAspect)
        }
        let art = converter.convert(pixels, width: targetSize.width, height: targetSize.height)

        let conversion = ImageRenderCache(
            source: source,
            decodedPixels: decodedPixels,
            rawImageWidth: rawImage.width,
            rawImageHeight: rawImage.height,
            width: targetSize.width,
            height: targetSize.height,
            characterSet: characterSet,
            shapeAware: shapeAware,
            colorMode: colorMode,
            dithering: dithering,
            toneCurve: toneCurve,
            supersampling: supersampling,
            edgeThreshold: edgeThreshold,
            edgeContrast: edgeContrast,
            inkThreshold: inkThreshold,
            adjustments: adjustments,
            posterizationLevels: posterizationLevels,
            contentMode: contentMode,
            aspectRatioOverride: aspectRatioOverride,
            cellAspect: cellAspect,
            terminalColors: terminalColors,
            colorDepth: colorDepth,
            templateInk: templateInk,
            resizing: resizing,
            art: art
        )
        if let playing {
            playing.playback.keep(conversion, ofFrame: playing.index)
        } else {
            cacheBox.value = conversion
        }

        return Self.buffer(for: art, monoColours: monoColours)
    }

    /// The buffer a converted picture becomes: its lines, inked if it is mono (a
    /// `monoColours` to ink it in), and its coverage as claims.
    ///
    /// **The claims are the glyph path's half of the claim/bytes pairing.** Every cell
    /// the converter drew at less than full coverage states its colour at full strength
    /// — an emitter has no backdrop to composite against — and says here which cells owe
    /// a blend, so the compositor resolves them against what is actually behind the
    /// image rather than against the black the flatten used to assume (§42).
    ///
    /// A fully opaque picture's `coverage` is empty, so this is one `isEmpty` for the
    /// overwhelming majority of images and no allocation at all.
    static func buffer(
        for art: ASCIIArt, monoColours: ImageMonoColours?
    ) -> FrameBuffer {
        var buffer = FrameBuffer(lines: inked(art, monoColours: monoColours))
        buffer.opacityRegions += art.claims
        // The other half of `inked`'s claim/bytes pairing. `art.claims` says what the
        // SOURCE PICTURE owes — its own per-pixel transparency — and is empty for the
        // overwhelming majority of pictures, which are opaque; it says nothing at all
        // about mono's ink and paper, which `inked` stamps over every cell of every line
        // (the view's styles, the theme's where unstated). A
        // faded palette's `foreground`/`background` therefore reached the emitter at
        // full strength and with nothing claimed, which is §68's bug in its seventh
        // place (§42.4 is right that the mono CONVERTER paints no colours and has no
        // claim to make; this post-pass is not the converter).
        //
        // Over exactly the spans `inked` colours: each line less the picture's uncovered
        // runs, which for an opaque picture is the whole line. The resolver multiplies ink
        // and field across every region covering a cell, so these compose with the
        // coverage claims above rather than contradicting them.
        buffer.opacityRegions += Self.inkClaims(for: art, monoColours: monoColours)
        return buffer
    }

    /// What ``inked(_:monoColours:)``'s two colours owe, one region per span it paints —
    /// one per line, for a picture with no uncovered cell.
    ///
    /// `nil`-free by construction: `OpacityRegion.claim` answers `nil` for an opaque
    /// pair, so an opaque pair (an ordinary palette, or opaque styles) adds nothing and
    /// allocates nothing past the `guard`.
    private static func inkClaims(
        for art: ASCIIArt, monoColours: ImageMonoColours?
    ) -> [OpacityRegion] {
        guard let monoColours, !monoColours.isOpaque else { return [] }
        // Only where `inked` painted. A claim left over an uncovered cell is not merely
        // wasted: that cell shows whatever is behind the picture — a `.background(_:)`
        // fill or a row's highlight, written into these same bytes — and the resolver
        // would fade THAT toward the surface by the ink's alpha.
        var uncovered = art.uncovered[...]
        var claims: [OpacityRegion] = []
        for (index, line) in art.lines.enumerated() {
            forEachInkedSpan(ofLine: index, width: line.strippedLength, uncovered: &uncovered) { span in
                if let claim = OpacityRegion.claim(
                    offsetX: span.lowerBound, offsetY: index, width: span.count, height: 1,
                    ink: monoColours.ink, field: monoColours.paper)
                {
                    claims.append(claim)
                }
            }
        }
        return claims
    }

    /// Mono output, in its ink and paper: the view's `.foregroundStyle` and
    /// `.backgroundStyle`, the theme's foreground and background where unstated
    /// (``ImageMonoColours``, which the pixel path reads too).
    ///
    /// ``ASCIIColorMode/mono`` emits no colour at all — that is the point of it,
    /// and what makes it work on a terminal that has none. Inside an app that
    /// paints its own background, though, "no colour" is not black and white:
    /// it is the TERMINAL's defaults, over a page the app has already painted.
    /// Under a dark theme with a dark terminal default that is ink on ink, and
    /// the image simply does not appear.
    ///
    /// Applied here rather than in the converter, and AFTER the render cache,
    /// because the cache is not keyed on the palette or the styles: baking the
    /// colours into the cached lines would serve the old ink forever. Same reason
    /// ``ASCIIColorMode/resolved(with:)`` is applied before it.
    ///
    /// **Never over a cell nothing of the picture reaches.** A mono line cannot say a
    /// cell is absent — the space where a pixel is transparent and the space where it is
    /// dark are the same byte — so the converter says it beside the lines, in
    /// ``ASCIIArt/uncovered``, and those spans go out stating no colour at all: exactly
    /// what every colour mode emits for the same cells (§42.2). Wrapped whole, the
    /// paper covered a logo's transparent surround in the theme's background and hid
    /// the `.background(_:)`, selected row or dialog surface behind it — §42's black
    /// rectangle, back in one mode.
    ///
    /// NOT a zero-field claim over papered cells, the other way to say it. A claim
    /// resolves against what the compositor sees behind the picture, and a
    /// `.background(_:)` fill is not behind it: `applyPersistentBackground` writes it
    /// into these very bytes, restating it only after a reset, and the paper stated at
    /// column 0 has already overridden it. The surround would resolve to the ambient
    /// surface, not to the fill it sits on (§70.5).
    private static func inked(
        _ art: ASCIIArt, monoColours: ImageMonoColours?
    ) -> [String] {
        guard let monoColours else { return art.lines }
        // The opaque spelling, with the alpha claimed beside it by `inkClaims` — the
        // pairing every other painted colour in the framework uses (§16). Handing
        // `palette.foreground`/`palette.background` to `colorize` raw trapped the
        // emitter's `isOpaque` assertion on a faded palette, and in release drew the
        // picture at full strength over a page it was supposed to follow.
        let ink = monoColours.ink.opaqueSpelling
        let paper = monoColours.paper.opaqueSpelling
        // An opaque picture — nearly every picture — has no uncovered cell and keeps the
        // one wrapper per line it always had.
        guard !art.uncovered.isEmpty else {
            return art.lines.map { ANSIRenderer.colorize($0, foreground: ink, background: paper) }
        }
        var uncovered = art.uncovered[...]
        return art.lines.enumerated().map { index, line in
            // Columns are CHARACTERS, as the converter counted them: a mono line carries
            // no escapes, so the two cannot drift.
            var drawn = ""
            var cursor = line.startIndex
            var column = 0
            forEachInkedSpan(ofLine: index, width: line.count, uncovered: &uncovered) { span in
                let start = line.index(cursor, offsetBy: span.lowerBound - column)
                let end = line.index(start, offsetBy: span.count)
                drawn.append(contentsOf: line[cursor..<start])
                drawn += ANSIRenderer.colorize(
                    String(line[start..<end]), foreground: ink, background: paper)
                cursor = end
                column = span.upperBound
            }
            drawn.append(contentsOf: line[cursor...])
            return drawn
        }
    }

    /// Calls `body` with each span of line `line` that ``inked(_:monoColours:)`` paints —
    /// all `width` of its columns less the picture's uncovered runs on it — consuming
    /// those runs from the front of `uncovered`, which is in reading order.
    ///
    /// One walk for the bytes and for their claim, so the two cannot disagree about which
    /// cells carry mono's colours. Clamped to `width` rather than trusted, because a
    /// run naming a column past the line would otherwise index off its end.
    private static func forEachInkedSpan(
        ofLine line: Int, width: Int, uncovered: inout ArraySlice<ASCIIArt.CoverageRun>,
        _ body: (Range<Int>) -> Void
    ) {
        var column = 0
        while let run = uncovered.first, run.line <= line {
            uncovered.removeFirst()
            guard run.line == line else { continue }
            let gap = min(run.columns.lowerBound, width)
            if gap > column { body(column..<gap) }
            column = max(column, min(run.columns.upperBound, width))
        }
        if width > column { body(column..<width) }
    }
}

// MARK: - Coverage as claims

extension ASCIIArt {
    /// What this picture's cells owe the compositor, in the buffer's own coordinates.
    ///
    /// The glyph path's half of the claim/bytes pairing: every cell the converter drew
    /// at less than full coverage states its colour at full strength — an emitter has no
    /// backdrop to composite against — and this says which cells owe a blend, so the
    /// compositor resolves them against what is actually behind the image rather than
    /// against the black the flatten used to assume (§42).
    ///
    /// A run per rectangle, one row tall, which is what `CoverageRun` already coalesced
    /// to. `[]` for a fully opaque picture, which is nearly every picture: one `isEmpty`
    /// and no allocation.
    ///
    /// Its own named property rather than four lines inside `_ImageCore` because
    /// `_ImageCore` is private and this is the only part of it worth asserting directly
    /// — the raster view has no in-memory source, so the end-to-end path cannot be
    /// rendered from pixels in a test.
    var claims: [OpacityRegion] {
        coverage.compactMap { run in
            OpacityRegion.claim(
                offsetX: run.columns.lowerBound, offsetY: run.line,
                width: run.columns.count, height: 1, inkAlpha: run.ink, fieldAlpha: run.field)
        }
    }
}
