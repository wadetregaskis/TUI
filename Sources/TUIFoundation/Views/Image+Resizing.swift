//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+Resizing.swift
//
//  SwiftUI's resizable images: an image that fills its frame, stretched or
//  tiled, with cap insets that keep its edges from scaling.
//
//  Created by Wade Tregaskis
//  License: MIT

@MainActor extension Image {
    /// The modes that SwiftUI uses to resize an image to fit within its
    /// containing view — mirrors SwiftUI's `Image.ResizingMode`.
    public enum ResizingMode: Sendable, Hashable {
        /// A mode to repeat the image at its original size, as many times as
        /// necessary to fill the available space.
        ///
        /// The original size is the image's size in points over a cell's, where
        /// the terminal's cell size is known, as an image that is not resizable
        /// is drawn; elsewhere it is the size the whole image fits its frame at.
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
    /// Cap insets are in the image's points, as SwiftUI's are: a @2x image's
    /// insets are half its pixels. The caps keep the image's natural size —
    /// its size in points over a cell's, where the terminal's cell size is
    /// known, as an image that is not resizable is drawn; elsewhere the size
    /// the whole image fits its frame at — and the edges and centre between
    /// them stretch, or tile at that size, to fill the rest. So a tile follows
    /// the terminal's font, as a natural-size image does. An image drawn in
    /// slices — with caps, or tiled — is drawn as cells even on a terminal
    /// that shows pictures, its pixels being made for its frame.
    ///
    /// - Parameters:
    ///   - capInsets: The edges of the image, in points, that keep their
    ///     scale. None by default.
    ///   - resizingMode: Whether the parts between the caps stretch or tile.
    ///     Stretch by default.
    /// - Returns: The image, resizable.
    nonisolated public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch) -> Image {
        var copy = self
        // Held never negative — a cap has no meaning below nothing — and, as
        // every stated length is, short of `Int`'s end, which the slicing's
        // sums of caps and centre would pass.
        func hold(_ inset: Int) -> Int { max(0, inset.heldToStatedLength) }
        let capInsets = EdgeInsets(
            top: hold(capInsets.top), leading: hold(capInsets.leading), bottom: hold(capInsets.bottom),
            trailing: hold(capInsets.trailing))
        copy.resizing = _ImageResizing(capInsets: capInsets, mode: resizingMode)
        return copy
    }
}

/// How ``Image/resizable(capInsets:resizingMode:)`` said to resize an image.
///
/// `@usableFromInline`, with its fields, so that ``slices`` and ``filling``
/// inline into TUIBitmaps (module split step B5c), whose `_ImageCore` asks
/// them of every image it draws, every frame: each is less work than the call.
/// An `@inlinable` member of a type that is only `package` is not serialized
/// for another module to inline.
@usableFromInline
package struct _ImageResizing: Equatable, Sendable {
    @usableFromInline package var capInsets: EdgeInsets
    @usableFromInline package var mode: Image.ResizingMode
    /// Where the image is drawn, the box its slices are cut at: its natural
    /// size in cells and its pixels per point, or `nil` where a cell's size in
    /// points is not known and the slices are cut at the box the whole image
    /// fits. Set by the drawing, not by ``Image/resizable(capInsets:resizingMode:)``,
    /// and part of the value so a conversion cached for one box is not served
    /// for another.
    @usableFromInline package var sliceBox: SliceBox?

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal, and ``filling`` makes one inline.
    @inlinable
    package init(capInsets: EdgeInsets, mode: Image.ResizingMode) {
        self.capInsets = capInsets
        self.mode = mode
        self.sliceBox = nil
    }

    /// An image's natural size in cells, and its pixels per point: what a sliced
    /// image's caps keep and its tiles repeat at.
    @usableFromInline
    package struct SliceBox: Equatable, Sendable {
        @usableFromInline package var width: Int
        @usableFromInline package var height: Int
        @usableFromInline package var pixelsPerPoint: Double

        @inlinable
        package init(width: Int, height: Int, pixelsPerPoint: Double) {
            self.width = width
            self.height = height
            self.pixelsPerPoint = pixelsPerPoint
        }
    }

    /// Whether the image is drawn in slices rather than resampled whole: it
    /// has caps to keep, or it tiles.
    @inlinable
    package var slices: Bool {
        mode == .tile || capInsets != EdgeInsets()
    }
}

extension _ImageResizing {
    /// A plain stretch to the box — what an image at its natural size draws
    /// with, its box being its own shape.
    ///
    /// Computed rather than a `static let`: read from another module, a
    /// stored static is a call to its addressor, where this folds to the
    /// constant.
    @inlinable
    package static var filling: Self { Self(capInsets: EdgeInsets(), mode: .stretch) }
}
