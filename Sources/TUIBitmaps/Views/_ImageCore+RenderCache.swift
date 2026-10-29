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
    /// The colour a template image's pixels were drawn in, or `nil` for an
    /// image drawn in its own colours.
    var templateInk: RGBA?
    /// How a resizable image filled its box: stretched, or in slices.
    var resizing: _ImageResizing?
    var art: ASCIIArt

    /// Returns whether `self` was built from the same inputs as the
    /// pending render. Compares everything except the cached `art`.
    func matches(  // swiftlint:disable:this function_parameter_count
        source: ImageSource,
        rawImageWidth: Int, rawImageHeight: Int,
        width: Int, height: Int,
        characterSet: ASCIICharacterSet, shapeAware: Bool, colorMode: ASCIIColorMode,
        dithering: DitheringMode, toneCurve: ASCIIToneCurve?,
        supersampling: Int?, edgeThreshold: Double?, edgeContrast: Double, inkThreshold: Double?,
        adjustments: ImageAdjustments, contentMode: ContentMode,
        aspectRatioOverride: Double?,
        cellAspect: Double,
        terminalColors: TerminalColors,
        templateInk: RGBA?,
        resizing: _ImageResizing?
    ) -> Bool {
        guard self.rawImageWidth == rawImageWidth,
            self.rawImageHeight == rawImageHeight,
            self.width == width,
            self.height == height,
            self.characterSet == characterSet,
            self.shapeAware == shapeAware,
            self.colorMode == colorMode,
            self.dithering == dithering,
            self.toneCurve == toneCurve,
            self.supersampling == supersampling,
            self.edgeThreshold == edgeThreshold,
            self.edgeContrast == edgeContrast,
            self.inkThreshold == inkThreshold,
            self.adjustments == adjustments,
            self.contentMode == contentMode,
            self.aspectRatioOverride == aspectRatioOverride,
            self.cellAspect == cellAspect,
            self.terminalColors == terminalColors,
            self.templateInk == templateInk,
            self.resizing == resizing
        else { return false }
        // Last: the scalar comparisons above reject the frequent miss — a
        // resize — before this one runs. It is the field that decides
        // correctness, not the one that usually decides the answer.
        return self.source == source
    }
}
