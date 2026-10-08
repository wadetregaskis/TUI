//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image+Resizing.swift
//
//  SwiftUI's resizable images: an image that fills its frame, stretched or
//  tiled, with cap insets that keep its edges from scaling.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitImage

extension Image {
    /// The modes that SwiftUI uses to resize an image to fit within its
    /// containing view — mirrors SwiftUI's `Image.ResizingMode`.
    public enum ResizingMode: Sendable, Hashable {
        /// A mode to repeat the image at its original size, as many times as
        /// necessary to fill the available space.
        ///
        /// The original size is the size the whole image fits its frame at:
        /// a raster image has no size in cells of its own.
        case tile

        /// A mode to enlarge or reduce the size of an image so that it fills
        /// the available space.
        case stretch
    }

    /// Sets the mode by which SwiftUI resizes an image to fit its space —
    /// mirrors SwiftUI's `resizable(capInsets:resizingMode:)`.
    ///
    /// A resizable image fills its frame, its aspect not kept, unless a
    /// content mode around it — ``View/scaledToFit()``,
    /// ``View/scaledToFill()``, ``View/aspectRatio(_:contentMode:)`` — says to
    /// keep it:
    ///
    /// ```swift
    /// Image(.file("banner.png"))
    ///     .resizable()                 // stretched to 60 × 4
    ///     .frame(width: 60, height: 4)
    ///
    /// Image(.file("photo.png"))
    ///     .resizable()
    ///     .scaledToFit()               // fitted, aspect kept
    /// ```
    ///
    /// On an axis with no frame to fill — a scroll view's, asked how big its
    /// content is — the image takes the extent its aspect gives it, where
    /// SwiftUI's takes its pixel size.
    ///
    /// Cap insets are in the image's pixels, as SwiftUI's are in its points.
    /// The caps keep the scale the whole image fits its frame at, and the
    /// edges and centre between them stretch, or tile, to fill the rest. An
    /// image drawn in slices — with caps, or tiled — is drawn as cells even on
    /// a terminal that shows pictures, its pixels being made for its frame.
    ///
    /// - Parameters:
    ///   - capInsets: The edges of the image, in pixels, that keep their
    ///     scale. None by default.
    ///   - resizingMode: Whether the parts between the caps stretch or tile.
    ///     Stretch by default.
    /// - Returns: The image, resizable.
    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch) -> Image {
        var copy = self
        copy.resizing = _ImageResizing(capInsets: capInsets, mode: resizingMode)
        return copy
    }
}

/// How ``Image/resizable(capInsets:resizingMode:)`` said to resize an image.
struct _ImageResizing: Equatable, Sendable {
    var capInsets: EdgeInsets
    var mode: Image.ResizingMode

    /// Whether the image is drawn in slices rather than resampled whole: it
    /// has caps to keep, or it tiles.
    var slices: Bool {
        mode == .tile || capInsets != EdgeInsets()
    }
}

extension _ImageResizing {
    /// A plain stretch to the box — what an image at its natural size draws
    /// with, its box being its own shape.
    static let filling = Self(capInsets: EdgeInsets(), mode: .stretch)
}
