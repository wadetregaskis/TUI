//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+RenderingOptions.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation
import TUIImage

// MARK: - Environment Keys

/// Environment key for the glyph charset used by Image.
private struct ImageCharacterSetKey: EnvironmentKey {
    static let defaultValue: ASCIICharacterSet = .blocks(.fine)
}

/// Environment key for shape-aware glyph matching.
private struct ImageShapeAwareKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

/// Environment key for the color mode used by Image.
private struct ImageColorModeKey: EnvironmentKey {
    static let defaultValue: ASCIIColorMode = .trueColor
}

/// Environment key for the tone curve applied before anything measures the
/// image.
private struct ImageToneCurveKey: EnvironmentKey {
    static let defaultValue: ASCIIToneCurve? = nil
}

/// Environment key for the dithering mode used by Image.
private struct ImageDitheringKey: EnvironmentKey {
    static let defaultValue: DitheringMode = .none
}

/// Environment key for the brightness-mapping supersampling factor.
private struct ImageSupersamplingKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

/// Environment key for the shape-mode edge-glyph gradient threshold.
private struct ImageEdgeThresholdKey: EnvironmentKey {
    static let defaultValue: Double? = 0.9
}

/// Environment key for the local-contrast lift applied before glyph selection.
private struct ImageEdgeContrastKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

/// Environment key for the placeholder text shown while loading.
private struct ImagePlaceholderTextKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

/// The spinner a loading `Image` draws in its placeholder: whether it draws one,
/// and which. `imagePlaceholderSpinner(_:)` writes only `isShown`, and
/// `imagePlaceholderSpinner(style:color:)` writes all three.
struct ImagePlaceholderSpinner: Sendable, Equatable {
    /// Whether the placeholder draws a spinner at all.
    var isShown = true

    /// The animation style to draw.
    var style: SpinnerStyle = .dots

    /// The colour to draw it in, or `nil` for the view's `foregroundStyle`, and
    /// failing that the palette's accent.
    var color: Color?

    static func == (lhs: Self, rhs: Self) -> Bool {
        // `SpinnerStyle` carries a custom-frames case and is not `Equatable`, so
        // compare what is drawn, as `RefreshIndicator` does. The interval as well as
        // the frames: `.custom` with `.line`'s frames still steps at 7 ticks, not 8.
        guard lhs.isShown == rhs.isShown, lhs.style.frames == rhs.style.frames,
            lhs.style.interval == rhs.style.interval
        else { return false }
        return lhs.color == rhs.color
    }
}

/// Environment key for the placeholder's spinner.
private struct ImagePlaceholderSpinnerKey: EnvironmentKey {
    static let defaultValue = ImagePlaceholderSpinner()
}

/// Environment key for the maximum allowed image pixel count.
private struct ImageMaxPixelCountKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

/// Environment key for the URL download timeout in seconds.
private struct ImageURLTimeoutKey: EnvironmentKey {
    static let defaultValue: TimeInterval = 30
}

private struct URLImageCacheKey: EnvironmentKey {
    static let defaultValue: URLImageCache? = nil
}

/// The reference box an image scales to fit — see ``View/imageFitTarget(_:)``.
///
/// `.fit`/`.fill` (``ContentMode``) decides *how* an image scales relative to a box;
/// this decides *which box*. The two are orthogonal.
public enum ImageFitTarget: Sendable, Hashable, CaseIterable {
    /// The image's natural size, as SwiftUI draws an image that is not
    /// resizable — the default. Its size in points, in cells of the
    /// terminal's size in points (``EnvironmentValues/imageCellPoints``),
    /// whatever it is offered. Where the cell's size in points is not known,
    /// and for an image that is resizable, ``proposedSize``.
    case naturalSize

    /// Fit the size the layout proposes. Inside a vertical
    /// `ScrollView` the proposed height is unbounded, so the image is driven by
    /// its width and can be scrolled at full size. Inside one that scrolls
    /// horizontally — alone or both ways — nothing bounds it at all, and a
    /// terminal has no natural size in cells to give a picture, so it fits the
    /// visible viewport, as ``viewport`` does — on every axis a `.frame` inside
    /// the scroll view leaves open. A `.frame(width: 300)` is 300 wide.
    case proposedSize

    /// Fit the visible viewport — the innermost enclosing `ScrollView`'s visible
    /// content area, or the proposed size when there is no enclosing `ScrollView`.
    /// The image fills the viewport at ``View/imageZoom(_:)`` `1` and overflows
    /// (scrolling, with scrollbars appearing automatically) only when zoomed in.
    case viewport
}

/// Environment key for the image fit target.
private struct ImageFitTargetKey: EnvironmentKey {
    static let defaultValue: ImageFitTarget = .naturalSize
}

/// Environment key for the image zoom multiplier.
private struct ImageZoomKey: EnvironmentKey {
    static let defaultValue: Double = 1.0

    /// The largest zoom honoured. Past it a fitted image is thousands of
    /// cells on a side — more than any terminal shows and more glyph
    /// conversion than anyone waits for — and the size arithmetic downstream
    /// stops fitting an `Int` long before the factor stops being finite.
    static let maximum: Double = 64

    /// `factor`, if it is a zoom the arithmetic can use; the default for NaN,
    /// an infinity or a non-positive value; ``maximum`` for anything past it.
    /// There is deliberately NO lower bound beyond `> 0`: the rendered size
    /// is floored at one cell (`_ImageCore.zoomed`), so a 1/512 zoom shrinks
    /// to a single cell rather than vanishing.
    static func sanitized(_ factor: Double) -> Double {
        guard factor.isFinite, factor > 0 else { return defaultValue }
        return min(factor, maximum)
    }
}

// MARK: - EnvironmentValues

extension EnvironmentValues {
    /// The character set for ASCII art rendering.
    var imageCharacterSet: ASCIICharacterSet {
        get { self[ImageCharacterSetKey.self] }
        set { self[ImageCharacterSetKey.self] = newValue }
    }

    /// Whether image glyphs are shape-matched — see
    /// ``View/imageShapeAware(_:)``.
    var imageShapeAware: Bool {
        get { self[ImageShapeAwareKey.self] }
        set { self[ImageShapeAwareKey.self] = newValue }
    }

    /// The color mode for ASCII art rendering.
    var imageColorMode: ASCIIColorMode {
        get { self[ImageColorModeKey.self] }
        set { self[ImageColorModeKey.self] = newValue }
    }

    /// The recolouring applied before the image is measured or quantised —
    /// see ``View/imageToneCurve(_:)``.
    var imageToneCurve: ASCIIToneCurve? {
        get { self[ImageToneCurveKey.self] }
        set { self[ImageToneCurveKey.self] = newValue }
    }

    /// The supersampling factor for brightness-mapping character sets —
    /// see ``View/imageSupersampling(_:)``.
    var imageSupersampling: Int? {
        get { self[ImageSupersamplingKey.self] }
        set { self[ImageSupersamplingKey.self] = newValue }
    }

    /// The shape-mode edge-glyph threshold — see
    /// ``View/imageEdgeThreshold(_:)``.
    var imageEdgeThreshold: Double? {
        get { self[ImageEdgeThresholdKey.self] }
        set { self[ImageEdgeThresholdKey.self] = newValue }
    }

    /// The local-contrast lift applied before any glyph is chosen — see
    /// ``View/imageEdgeContrast(_:)``.
    var imageEdgeContrast: Double {
        get { self[ImageEdgeContrastKey.self] }
        set { self[ImageEdgeContrastKey.self] = newValue }
    }

    /// The dithering mode for ASCII art rendering.
    var imageDithering: DitheringMode {
        get { self[ImageDitheringKey.self] }
        set { self[ImageDitheringKey.self] = newValue }
    }

    /// Custom placeholder text shown while loading (nil = no text).
    var imagePlaceholderText: String? {
        get { self[ImagePlaceholderTextKey.self] }
        set { self[ImagePlaceholderTextKey.self] = newValue }
    }

    /// Whether the placeholder shows a spinner, and which.
    var imagePlaceholderSpinner: ImagePlaceholderSpinner {
        get { self[ImagePlaceholderSpinnerKey.self] }
        set { self[ImagePlaceholderSpinnerKey.self] = newValue }
    }

    /// The maximum allowed total pixel count for loaded images.
    ///
    /// Images exceeding this limit will fail with `ImageLoadError.imageTooLarge`.
    /// `nil` means no limit (default).
    var imageMaxPixelCount: Int? {
        get { self[ImageMaxPixelCountKey.self] }
        set { self[ImageMaxPixelCountKey.self] = newValue }
    }

    /// The timeout in seconds for URL image downloads.
    ///
    /// Defaults to 30 seconds.
    var imageURLTimeout: TimeInterval {
        get { self[ImageURLTimeoutKey.self] }
        set { self[ImageURLTimeoutKey.self] = newValue }
    }

    /// The cache images downloaded from URLs and read from files are kept in, when a subtree names
    /// one (``View/urlImageCache(_:)``); `nil` leaves it to the app's own.
    var urlImageCache: URLImageCache? {
        get { self[URLImageCacheKey.self] }
        set { self[URLImageCacheKey.self] = newValue }
    }

    /// The cache a URL image loads through: the subtree's, else the app's own,
    /// made when the app first loads one — and none outside an app, where
    /// every load downloads.
    @MainActor
    var resolvedURLImageCache: URLImageCache? {
        urlImageCache ?? appScopedObjects?.object { URLImageCache() }
    }

    /// The reference box images scale to fit — their natural size, the
    /// proposed size, or the visible viewport.
    var imageFitTarget: ImageFitTarget {
        get { self[ImageFitTargetKey.self] }
        set { self[ImageFitTargetKey.self] = newValue }
    }

    /// The zoom multiplier applied to an image's fitted size (`1` = fit exactly).
    ///
    /// Sanitised on the way IN, not where it is read: the value is multiplied
    /// into cell counts and converted to `Int` on both the measure and the
    /// render pass, and `Int(_:)` traps on an infinity. One setter is one
    /// place to enforce that; the two readers then need no guard of their own.
    var imageZoom: Double {
        get { self[ImageZoomKey.self] }
        set { self[ImageZoomKey.self] = ImageZoomKey.sanitized(newValue) }
    }
}
