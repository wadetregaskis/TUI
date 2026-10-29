//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore+TerminalGraphics.swift
//
//  A picture drawn in the terminal's own pixels (Kitty's graphics protocol)
//  rather than in glyphs: its cell box, the resolution it is sent at, and the
//  placeholder cells that draw it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation
import TUIImage

// MARK: - Drawing with the terminal's own graphics

extension _ImageCore {

    /// The image as **real pixels**, if this terminal will place one in its
    /// cell grid — or `nil`, which means "draw it out of glyphs, as always".
    ///
    /// What comes back is ordinary text: `columns` × `rows` cells of Unicode
    /// placeholders that the terminal replaces with parts of the picture. It
    /// measures, clips, scrolls, composites and diffs exactly like the glyph
    /// rendering it replaces, so nothing downstream of here knows the
    /// difference. See ``KittyGraphics``.
    ///
    /// ## The six gates, and why each is separate
    ///
    /// - **`isSupported`** — the startup handshake's answer. Default `false`,
    ///   so a terminal nobody asked draws glyphs.
    /// - **`terminalGraphics`** — the app's preference. The glyph renderer is
    ///   a look and not only a fallback; see ``View/terminalGraphics(_:)``.
    /// - **`!isMeasuring`** — transmitting is a side effect, and a measure
    ///   pass that renders (a Card sizing its container, a Table probing a
    ///   multi-line cell) must not put an image in the terminal for a branch
    ///   that may never be drawn. The measured SIZE is unaffected: both paths
    ///   produce the same cell box, because both ask
    ///   ``ASCIIConverter/targetSize(imageWidth:imageHeight:maxWidth:maxHeight:contentMode:overrideAspectRatio:cellAspect:)``.
    /// - **a store** — `nil` in a headless render, where there is no terminal
    ///   to transmit to.
    /// - **mono's two colours** — a `.mono` picture whose ink or paper has no
    ///   RGB (the terminal's own colours before it reports them) cannot be baked
    ///   into pixels, and glyphs can spell it. See `ImageMonoColours.pixels`.
    /// - **the store's own answer** — `nil` for an extent past what
    ///   placeholders can address (297 cells; there is no combining mark for
    ///   the 298th column).
    /// The resolution to send `rawImage` at for `wanted` pixels: as many,
    /// but never more than the picture HAS. The terminal fits the image to the
    /// placement rectangle, so upscaling before transmission buys nothing and
    /// costs everything: on a 135x48 grid of 16x34-pixel cells at zoom 2 the
    /// unclamped size is 4320x3264, which is 56 MB of RGBA resampled UP from a
    /// 1101x1080 source. Zoom is what makes this reachable, and zoom is
    /// exactly when an app feels slow.
    ///
    /// Clamped by a single factor rather than per axis, so a source whose
    /// aspect differs from the box is not stretched on the way out.
    nonisolated static func pixelSize(
        of rawImage: RGBAImage, fitting wanted: (width: Int, height: Int)
    ) -> (width: Int, height: Int) {
        pixelSize(of: (rawImage.width, rawImage.height), fitting: wanted)
    }

    /// ``pixelSize(of:fitting:)`` for a picture of `source` pixels.
    nonisolated static func pixelSize(
        of source: (width: Int, height: Int), fitting wanted: (width: Int, height: Int)
    ) -> (width: Int, height: Int) {
        let widthShrink = Double(source.width) / Double(max(1, wanted.width))
        let heightShrink = Double(source.height) / Double(max(1, wanted.height))
        let shrink = min(1.0, min(widthShrink, heightShrink))
        return (
            max(1, Int((Double(wanted.width) * shrink).rounded())),
            max(1, Int((Double(wanted.height) * shrink).rounded()))
        )
    }

    /// Whether pixels `kept`, which the terminal fits to a box of `box`
    /// pixels with their aspect kept and centres, draw within a pixel of
    /// where pixels `fresh` would, on both axes: the same box must draw the
    /// picture the same way, whatever it was drawn in before.
    nonisolated static func drawsAlike(
        _ kept: (width: Int, height: Int), _ fresh: (width: Int, height: Int), in box: (width: Int, height: Int)
    ) -> Bool {
        func fitted(_ pixels: (width: Int, height: Int)) -> (width: Double, height: Double) {
            let width = Double(max(1, pixels.width))
            let height = Double(max(1, pixels.height))
            let scale = min(Double(box.width) / width, Double(box.height) / height)
            return (width * scale, height * scale)
        }
        let keptDrawn = fitted(kept)
        let freshDrawn = fitted(fresh)
        return abs(keptDrawn.width - freshDrawn.width) <= 1 && abs(keptDrawn.height - freshDrawn.height) <= 1
    }

    /// How a picture's pixels are fitted to its cell box. The box is whole
    /// cells, so its aspect is the picture's only to within a cell, and the
    /// pixels sent decide what that rounding does to the picture (the
    /// owner's PICTURE-ASPECT, 2026-10-28):
    enum PixelFit: Equatable {
        /// The picture's own aspect, never distorted: the terminal fits it to
        /// the box with its aspect kept, leaving up to half a cell blank on one
        /// axis, the page's ground. `.scaledToFit()`, and a picture at its
        /// natural size.
        case ownAspect
        /// The box's aspect, the picture cropped to it, centred, at its own
        /// aspect: the box covered edge to edge with nothing distorted.
        /// `.scaledToFill()`.
        case crop
        /// The box's aspect, the picture stretched to it: what a `.resizable()`
        /// picture with no aspect ratio asks for.
        case stretch

        init(stretches: Bool, contentMode: ContentMode) {
            self = stretches ? .stretch : contentMode == .fill ? .crop : .ownAspect
        }

        /// The pixels to send for a box of `wanted` pixels, never more than
        /// the picture (or the part of it a crop keeps) has.
        func pixels(of image: RGBAImage, fitting wanted: (width: Int, height: Int)) -> (width: Int, height: Int) {
            switch self {
            case .stretch:
                return _ImageCore.pixelSize(of: image, fitting: wanted)
            case .crop:
                return _ImageCore.pixelSize(of: image.croppedSize(toAspectOf: wanted.width, wanted.height), fitting: wanted)
            case .ownAspect:
                // In steps: as one expression the type-check guard times out.
                let imageWidth = Double(image.width)
                let imageHeight = Double(image.height)
                let acrossScale = Double(max(1, wanted.width)) / imageWidth
                let downScale = Double(max(1, wanted.height)) / imageHeight
                let scale: Double = min(1.0, min(acrossScale, downScale))
                let width: Int = max(1, Int((imageWidth * scale).rounded()))
                let height: Int = max(1, Int((imageHeight * scale).rounded()))
                return (width, height)
            }
        }
    }

    func renderWithTerminalGraphics(
        _ rawImage: RGBAImage, width: Int, height: Int, stretches: Bool, context: RenderContext
    ) -> FrameBuffer? {
        guard KittyGraphics.isSupported,
            context.environment.terminalGraphics,
            let store = context.environment.terminalImageStore,
            rawImage.width > 0, rawImage.height > 0
        else { return nil }

        // The same cell box the glyph renderer would fill, from the same
        // function — so switching renderers cannot move the image or change
        // what the layout around it was told.
        let target = Self.cellBox(
            imageWidth: rawImage.width, imageHeight: rawImage.height,
            maxWidth: width, maxHeight: height,
            stretches: stretches,
            contentMode: context.environment.imageContentMode,
            aspectRatio: context.environment.imageAspectRatio,
            cellAspect: context.environment.imageCellAspect)
        guard target.width > 0, target.height > 0 else { return nil }

        // A measure pass reads a BOX, not a picture. Falling through to the
        // glyph renderer here — which is what bailing on `isMeasuring` did —
        // paid a full glyph conversion for every new size a measure-by-render
        // parent (a Button's label, a Section, a stack holding a Spacer)
        // probed, and threw the ink away: the render pass then transmitted
        // pixels and never looked at it. The box is the contract; blank
        // cells are the cheapest thing that has it.
        if context.isMeasuring {
            return FrameBuffer(
                lines: Array(repeating: String.spaces(target.width), count: target.height))
        }

        // The box's pixels, which ``pixelSize(of:fitting:)`` clamps to the
        // picture's own.
        let cell = context.environment.imageCellPixels
        let wantedWidth = target.width * cell.width
        let wantedHeight = target.height * cell.height

        // The colour settings apply to a real picture as much as to a field of
        // glyphs — more so, since there is no character in the way — and they
        // come from the same converter the glyph path builds, so the two
        // renderings of one picture agree about what the picture IS. The
        // settings that only decide which CHARACTER to draw are not consulted;
        // see `ASCIIConverter.recoloured(_:width:height:)`.
        let colorMode = context.environment.imageColorMode.resolved(
            with: context.environment.palette)
        let toneCurve = context.environment.imageToneCurve?.resolved(
            with: context.environment.palette)
        let edgeContrast = context.environment.imageEdgeContrast
        // Only a mono picture's pixels depend on it (`recoloured`).
        let inkThreshold = colorMode == .mono ? context.environment.imageInkThreshold : nil
        let adjustments = context.environment.imageAdjustments
        let dithering = context.environment.imageDithering
        // Mono's two colours, which pixels have to be TOLD. The character
        // renderer states them after the fact — `inked(_:monoColours:)`, run
        // after the render cache so a style or theme change re-colours a cached
        // conversion — and pixels have nothing to state them onto: a pixel is a
        // colour or it is nothing. So they are baked in, and therefore they are
        // in the signature: change the style or the theme and a mono picture is
        // genuinely a different picture, on every frame of a fading
        // `.foregroundStyle` too. `TerminalImageSignature.monoInk` says what that
        // costs and why it is the choice.
        //
        // A MONO picture. `recoloured` paints the pair for `.mono` and for no
        // other mode, so everywhere else it is pinned to that function's
        // defaults, by the same test on the same requested mode. Read from the
        // palette whatever the mode, a theme change re-sent every true-colour
        // photograph on screen to draw exactly the pixels the terminal held.
        // Both halves are `ImageMonoColours`, the derivation `inked` reads.
        // `nil` where mono's ink or paper has no RGB, which a pixel cannot hold.
        guard let mono = ImageMonoColours.pixels(for: colorMode, in: context.environment) else {
            return nil
        }

        // The transmitted resolution, not the cell box: two boxes that resample
        // to the same pixels are the same picture, and the store answers the
        // second with a placement instead of megabytes.
        let token = "image-\(context.identity.path)"
        let fit = PixelFit(stretches: stretches, contentMode: context.environment.imageContentMode)
        let boxPixels = fit.pixels(of: rawImage, fitting: (wantedWidth, wantedHeight))
        var signature = TerminalImageSignature(
            source: source,
            rawWidth: rawImage.width, rawHeight: rawImage.height,
            pixelWidth: boxPixels.width, pixelHeight: boxPixels.height,
            colorMode: colorMode, toneCurve: toneCurve,
            edgeContrast: edgeContrast, dithering: dithering,
            monoInk: mono.ink, monoPaper: mono.paper,
            terminalColors: TerminalColors.current, cropsToFill: fit == .crop, inkThreshold: inkThreshold,
            adjustments: adjustments)
        // A picture whose box changes — a frame animating it, a zoom growing
        // it, a window dragged — was sent again at every new size, half a
        // megabyte a frame for a photo growing into a screen: the frames came
        // a third of a second apart and the photo jumped in already large.
        // What this view has already sent of this picture is kept wherever it
        // has enough pixels for the box (the store answers with a placement,
        // the terminal fitting it), and where it has too few — the picture
        // grew — it is sent once at twice what the box wants, so a growth
        // costs a send or two, not one a frame.
        //
        // Kept only where the kept pixels draw the box as a fresh send would
        // (``drawsAlike(_:_:in:)``): the terminal fits pixels to a box with
        // their aspect kept, so pixels of the picture's own aspect (`.fit`, the
        // owner's PICTURE-ASPECT, 2026-10-28) draw every box alike, and pixels
        // cropped or stretched to one box's aspect draw another's with bars.
        //
        // And kept only while the box moves: a picture at rest is drawn from
        // pixels sent for its exact box, since a terminal's own scaling is
        // visibly softer (Ghostty, 2026-10-28: edge sharpness down 12-22%
        // scaling down from 2×, 1.25× and 1.1×, the smallest the softest).
        // Once the box has held still for ``PictureSettle/delayNanos``, kept
        // pixels of another size are sent again at the box's own — a picture
        // keeps its aspect, so all that changes is that it sharpens.
        // Asked only of a picture holding pixels of another size: one at its
        // exact size has nothing to settle, and pays nothing.
        if let held = store.signature(heldBy: token) as? TerminalImageSignature, held.isResample(of: signature),
            Self.drawsAlike(
                (held.pixelWidth, held.pixelHeight), (signature.pixelWidth, signature.pixelHeight),
                in: (wantedWidth, wantedHeight)),
            (held.pixelWidth, held.pixelHeight) == (signature.pixelWidth, signature.pixelHeight)
                || !PictureSettle.isSettled(box: (wantedWidth, wantedHeight), context: context, token: token)
        {
            if held.pixelWidth >= signature.pixelWidth - 1, held.pixelHeight >= signature.pixelHeight - 1 {
                (signature.pixelWidth, signature.pixelHeight) = (held.pixelWidth, held.pixelHeight)
            } else {
                let grown = fit.pixels(of: rawImage, fitting: (wantedWidth * 2, wantedHeight * 2))
                (signature.pixelWidth, signature.pixelHeight) = (grown.width, grown.height)
            }
        }
        let pixelWidth = signature.pixelWidth
        let pixelHeight = signature.pixelHeight

        guard
            let lines = store.placeholderRows(
                token: token, signature: signature,
                columns: target.width, rows: target.height,
                pixels: {
                    // Only on a miss: this resamples and recolours the decoded
                    // image and can be megabytes. The common case, by a wide
                    // margin, is that nothing has changed since last frame.
                    let converter = ASCIIConverter(
                        colorMode: colorMode, dithering: dithering,
                        toneCurve: toneCurve, edgeContrast: edgeContrast, inkThreshold: inkThreshold,
                        adjustments: adjustments)
                    // A filled picture is the part of it its box shows, at
                    // its own aspect; any other, the whole picture.
                    let source = fit == .crop ? rawImage.centreCropped(toAspectOf: pixelWidth, pixelHeight) : rawImage
                    let packed = Self.pixelBytes(
                        converter.recoloured(
                            source, width: pixelWidth, height: pixelHeight,
                            monoInk: mono.ink, monoPaper: mono.paper))
                    return (packed.bytes, packed.format, pixelWidth, pixelHeight)
                })
        else { return nil }

        // Every row is exactly `target.width` cells by construction — one
        // placeholder each, and `KittyGraphics.placeholderRows` builds nothing
        // else. Saying so costs nothing and saves every consumer of this buffer
        // re-deriving it EVERY FRAME: measuring a row means walking its scalars
        // through grapheme segmentation, and an image row is four scalars per
        // cell (the placeholder and three marks) with no ASCII fast path to take.
        return FrameBuffer(
            lines: lines, width: target.width, uniformWidth: true,
            lineWidths: [Int](repeating: target.width, count: lines.count))
    }

    /// An ``RGBAImage`` as the flat byte run the protocol wants, in the
    /// narrowest format that says everything the picture has to say.
    ///
    /// A photograph has no transparency, and three bytes a pixel rather than
    /// four is a quarter off a multi-megabyte transmission — which is a
    /// quarter off the pause on the frame that first shows it. The scan for an
    /// alpha channel costs one pass over pixels that are about to be copied
    /// anyway.
    ///
    /// Written through `unsafeUninitializedCapacity` rather than an append a
    /// channel: a full-screen image at a Retina cell is over two million
    /// pixels, and eight million bounds-checked appends is a visible pause of
    /// its own.
    static func pixelBytes(
        _ image: RGBAImage
    ) -> (bytes: [UInt8], format: KittyGraphics.PixelFormat) {
        let pixels = image.pixels
        let format: KittyGraphics.PixelFormat =
            pixels.contains { $0.a != .max } ? .rgba : .rgb
        let stride = format.stride
        let capacity = pixels.count * stride
        let bytes = [UInt8](unsafeUninitializedCapacity: capacity) { buffer, initialized in
            var index = 0
            for pixel in pixels {
                buffer[index] = pixel.r
                buffer[index + 1] = pixel.g
                buffer[index + 2] = pixel.b
                if stride == 4 { buffer[index + 3] = pixel.a }
                index += stride
            }
            initialized = index
        }
        return (bytes, format)
    }
}
