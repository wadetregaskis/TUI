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

        // Never transmit more pixels than the picture HAS. The terminal fits
        // the image to the placement rectangle, so upscaling before
        // transmission buys nothing and costs everything: on a 135x48 grid of
        // 16x34-pixel cells at zoom 2 the unclamped size is 4320x3264, which
        // is 56 MB of RGBA resampled UP from a 1101x1080 source. Zoom is what
        // makes this reachable, and zoom is exactly when an app feels slow.
        //
        // Clamped by a single factor rather than per axis, so a source whose
        // aspect differs from the box is not stretched on the way out.
        let cell = context.environment.imageCellPixels
        let wantedWidth = target.width * cell.width
        let wantedHeight = target.height * cell.height
        let widthShrink: Double = Double(rawImage.width) / Double(max(1, wantedWidth))
        let heightShrink: Double = Double(rawImage.height) / Double(max(1, wantedHeight))
        let shrink = min(1.0, min(widthShrink, heightShrink))
        let pixelWidth = max(1, Int((Double(wantedWidth) * shrink).rounded()))
        let pixelHeight = max(1, Int((Double(wantedHeight) * shrink).rounded()))

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
        let signature = TerminalImageSignature(
            source: source,
            rawWidth: rawImage.width, rawHeight: rawImage.height,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            colorMode: colorMode, toneCurve: toneCurve,
            edgeContrast: edgeContrast, dithering: dithering,
            monoInk: mono.ink, monoPaper: mono.paper,
            terminalColors: TerminalColors.current)

        guard
            let lines = store.placeholderRows(
                token: "image-\(context.identity.path)", signature: signature,
                columns: target.width, rows: target.height,
                pixels: {
                    // Only on a miss: this resamples and recolours the decoded
                    // image and can be megabytes. The common case, by a wide
                    // margin, is that nothing has changed since last frame.
                    let converter = ASCIIConverter(
                        colorMode: colorMode, dithering: dithering,
                        toneCurve: toneCurve, edgeContrast: edgeContrast)
                    let packed = Self.pixelBytes(
                        converter.recoloured(
                            rawImage, width: pixelWidth, height: pixelHeight,
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
