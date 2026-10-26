//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+Interpolation.swift
//
//  SwiftUI's image interpolation quality and antialiasing, which a raster
//  image's cells honour through how many samples each one takes; and its
//  template rendering mode.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Image {
    /// The level of quality for rendering an image that requires
    /// interpolation, such as a scaled image — mirrors SwiftUI's
    /// `Image.Interpolation`.
    ///
    /// A raster image here is resampled into cells, and the quality is how
    /// many samples each cell's sub-pixels average: one for `.none` (the
    /// nearest pixel), two, three and four for `.low`, `.medium` and `.high`.
    /// It is ``View/imageSupersampling(_:)``'s factor, set on the one image.
    public enum Interpolation: Sendable, Hashable {
        /// No interpolation: each sample is the nearest pixel.
        case none

        /// A low level of interpolation quality.
        case low

        /// A medium level of interpolation quality.
        case medium

        /// A high level of interpolation quality.
        case high

        /// The supersampling factor this quality draws with.
        var samplingFactor: Int {
            switch self {
            case .none: 1
            case .low: 2
            case .medium: 3
            case .high: 4
            }
        }
    }

    /// Specifies the current level of quality for rendering an image that
    /// requires interpolation — mirrors SwiftUI's `interpolation(_:)`.
    ///
    /// It applies to this image, and wins over an
    /// ``View/imageSupersampling(_:)`` around it. A symbol image is one glyph
    /// and has nothing to interpolate.
    ///
    /// - Parameter interpolation: The quality.
    /// - Returns: The image, drawn at that quality.
    public func interpolation(_ interpolation: Interpolation) -> Image {
        var copy = self
        copy.interpolationQuality = interpolation
        return copy
    }

    /// Specifies whether to apply antialiasing when rendering the image —
    /// mirrors SwiftUI's `antialiased(_:)`.
    ///
    /// `false` takes one sample per cell's sub-pixels, the nearest pixel, as
    /// `.interpolation(.none)` does; `true` keeps the smoothing the image would
    /// otherwise have. An interpolation quality set on the image decides
    /// instead.
    ///
    /// - Parameter isAntialiased: Whether to smooth the image.
    /// - Returns: The image, smoothed or not.
    public func antialiased(_ isAntialiased: Bool) -> Image {
        var copy = self
        copy.isAntialiased = isAntialiased
        return copy
    }

    /// Indicates whether SwiftUI renders an image as-is, or by using a
    /// different mode — mirrors SwiftUI's `Image.TemplateRenderingMode`.
    public enum TemplateRenderingMode: Sendable, Hashable {
        /// A mode that renders all non-transparent pixels as the foreground
        /// color.
        case template

        /// A mode that renders pixels of bitmap images as-is.
        case original
    }

    /// Indicates whether SwiftUI renders an image as-is, or by using a
    /// different mode — mirrors SwiftUI's `renderingMode(_:)`.
    ///
    /// `.template` draws a raster image's pixels in the foreground style (or
    /// the palette's foreground), each at its own alpha, so an icon takes the
    /// colour of the text around it; it is drawn as cells, never as a
    /// terminal picture. `.original`, and `nil`, draw the pixels as they are.
    /// A symbol image is a single-colour glyph in the foreground already —
    /// a template by nature — and stays one.
    ///
    /// - Parameter renderingMode: The mode, or `nil` for the default.
    /// - Returns: The image, drawn in that mode.
    public func renderingMode(_ renderingMode: TemplateRenderingMode?) -> Image {
        var copy = self
        copy.templateRenderingMode = renderingMode
        return copy
    }
}
