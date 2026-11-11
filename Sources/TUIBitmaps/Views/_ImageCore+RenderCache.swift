//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore+RenderCache.swift
//
//  The image core's cached conversion: the glyphs one image last converted
//  to, and every input that decided them.
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation
import TUIImage

// MARK: - Render Cache

/// Cached ASCII conversion output along with the input parameters that
/// produced it.
///
/// Re-using `ASCIIConverter` output across frames is safe whenever every
/// input that influences the output is unchanged. The cache key spans the
/// SOURCE, the loaded image's pixel dimensions, the output cell footprint, and
/// every styling environment value that the converter reads. A `_ImageCore`
/// only keeps the most-recent entry because each instance hosts one
/// image; on a hit the cached `[String]` is returned without touching
/// `ASCIIConverter.convert`.
struct ImageRenderCache: Equatable {
    /// WHICH picture this was converted from — not merely how big it decoded.
    ///
    /// Pixel dimensions are not an identity. Two photographs, two icons, two
    /// frames of one sequence are routinely the same size, so a source change
    /// that lands on a same-size file re-decoded into an entry that still
    /// "matched", and the view drew the picture it used to show for as long as
    /// that identity lived. Carried for the same reason, and named the same
    /// way, as ``TerminalImageSignature/source`` on the pixel path — which had
    /// it from the start, so the same app switching pictures was correct on a
    /// Kitty-graphics terminal and stale on every other one.
    var source: ImageSource
    /// And which LOAD of it: a file rewritten at the same path and size
    /// decodes to new pixels under the same source and the same dimensions,
    /// and this view loads it again when it comes back into a window that
    /// kept its state. See ``DecodedPixels``; it costs two pointer reads.
    var decodedPixels: DecodedPixels
    var rawImageWidth: Int
    var rawImageHeight: Int
    var width: Int
    var height: Int
    var characterSet: ASCIICharacterSet
    var shapeAware: Bool
    var colorMode: ASCIIColorMode
    var dithering: DitheringMode
    var toneCurve: ASCIIToneCurve?
    var supersampling: Int?
    var edgeThreshold: Double?
    var edgeContrast: Double
    var inkThreshold: Double?
    var adjustments: ImageAdjustments
    var posterizationLevels: Int?
    var contentMode: ContentMode
    var aspectRatioOverride: Double?
    var cellAspect: Double
    /// The colours the terminal had reported when this was converted.
    ///
    /// A mode that names the terminal's slots — `.ansi16`, or a `.palette` of
    /// `.ansi(_:)` entries — matches each pixel against each slot as the colour
    /// the terminal reported for it, or as xterm's value while it has reported
    /// none. And a palette mode compares equal by its colours, whatever they
    /// measure as. So `colorMode` alone matched a conversion made before a
    /// report, and the view drew it for as long as nothing else changed.
    ///
    /// By value, not by `TerminalColors.generation`: a task-local pin changes
    /// what a slot measures as without moving the generation.
    var terminalColors: TerminalColors
    /// How many colours the terminal shows, which the conversion downgrades the
    /// colour mode to (`ASCIIColorMode.effective(for:)`, read from
    /// `ColorDepth.current`). The render cache clears itself when the depth
    /// moves, and this lives in the view's state, where that clear does not
    /// reach: without it a picture converted in true colour went on being
    /// drawn in true-colour escapes on a 256-colour terminal, and the other
    /// way round.
    var colorDepth: ColorDepth
    /// The colour a template image's pixels were drawn in, or `nil` for an
    /// image drawn in its own colours.
    var templateInk: RGBA?
    /// How a resizable image filled its box: stretched, or in slices.
    var resizing: _ImageResizing?
    var art: ASCIIArt

    /// Whether `other` was converted with every input this was but the pixels
    /// and what came of them: another frame of one animation, at the same
    /// settings, in the same box.
    func hasSameSettings(as other: Self) -> Bool {
        var other = other
        other.decodedPixels = decodedPixels
        other.art = art
        return other == self
    }

    /// This conversion's settings, for the frame whose pixels `decodedPixels`
    /// are, converted to `art`.
    func converted(_ decodedPixels: DecodedPixels, to art: ASCIIArt) -> Self {
        var conversion = self
        conversion.decodedPixels = decodedPixels
        conversion.art = art
        return conversion
    }
}
