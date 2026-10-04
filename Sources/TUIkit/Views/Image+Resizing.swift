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

extension _ImageCore {
    /// The resizing this image draws with here: its own, unless a content mode
    /// set around it keeps its aspect instead.
    func effectiveResizing(in environment: EnvironmentValues) -> _ImageResizing? {
        environment.imageExplicitContentMode == nil ? resizing : nil
    }

    /// The cells a loaded image draws in, given at most `maxWidth` ×
    /// `maxHeight`.
    ///
    /// Fitted (or filled) to the box with its aspect kept — or, when it
    /// `stretches`, the box itself. An axis offered a natural-extent budget (a
    /// scroll view asking how big its content would be) has no frame to
    /// stretch to; there the image takes the extent its aspect gives it.
    static func cellBox(
        imageWidth: Int, imageHeight: Int, maxWidth: Int, maxHeight: Int,
        stretches: Bool, contentMode: ContentMode, aspectRatio: Double?, cellAspect: Double
    ) -> (width: Int, height: Int) {
        func fitted(maxHeight: Int?) -> (width: Int, height: Int) {
            ASCIIConverter.targetSize(
                imageWidth: imageWidth, imageHeight: imageHeight,
                maxWidth: maxWidth, maxHeight: maxHeight,
                contentMode: stretches ? .fit : contentMode,
                overrideAspectRatio: aspectRatio, cellAspect: cellAspect)
        }
        guard stretches else { return fitted(maxHeight: maxHeight) }
        guard maxWidth > 0, maxHeight > 0 else { return (0, 0) }
        switch (isNaturalExtentBudget(maxWidth), isNaturalExtentBudget(maxHeight)) {
        case (false, false): return (maxWidth, maxHeight)
        case (true, false): return (fitted(maxHeight: maxHeight).width, maxHeight)
        case (false, true): return (maxWidth, fitted(maxHeight: nil).height)
        case (true, true): return fitted(maxHeight: maxHeight)
        }
    }
}

// MARK: - Slices

extension RGBAImage {
    /// The image in nine slices, made to fill `columns` × `rows` cells: its
    /// caps at the scale the whole image fits those cells at, and the edges
    /// and centre between them stretched or tiled.
    ///
    /// Picked rather than resampled — each sample is one source pixel — at
    /// two to four samples a cell, which the converter then averages.
    func sliced(_ resizing: _ImageResizing, columns: Int, rows: Int, cellAspect: Double) -> RGBAImage {
        let fitted = ASCIIConverter.targetSize(
            imageWidth: width, imageHeight: height, maxWidth: columns, maxHeight: rows,
            contentMode: .fit, cellAspect: cellAspect)
        let tiles = resizing.mode == .tile
        let xs = Self.sliceMap(
            source: width, leading: resizing.capInsets.leading, trailing: resizing.capInsets.trailing,
            cells: columns, fittedCells: fitted.width, tiles: tiles)
        let ys = Self.sliceMap(
            source: height, leading: resizing.capInsets.top, trailing: resizing.capInsets.bottom,
            cells: rows, fittedCells: fitted.height, tiles: tiles)
        guard !xs.isEmpty, !ys.isEmpty else { return self }
        var out: [RGBA] = []
        out.reserveCapacity(xs.count * ys.count)
        for y in ys {
            let row = y * width
            for x in xs { out.append(pixels[row + x]) }
        }
        return RGBAImage(width: xs.count, height: ys.count, pixels: out)
    }

    /// For one axis, the source pixel each sample of a sliced image reads.
    ///
    /// - Parameters:
    ///   - source: The image's extent on the axis, in pixels.
    ///   - leading: The leading cap, in pixels.
    ///   - trailing: The trailing cap, in pixels.
    ///   - cells: The cells to fill.
    ///   - fittedCells: The cells the whole image fits on this axis — the
    ///     scale the caps keep.
    ///   - tiles: Whether the middle repeats rather than stretches.
    static func sliceMap(
        source: Int, leading: Int, trailing: Int, cells: Int, fittedCells: Int, tiles: Bool
    ) -> [Int] {
        guard source > 0, cells > 0 else { return [] }
        let scale = Double(source) / Double(max(1, fittedCells))
        let perCell = Swift.min(4, Swift.max(2, Int(scale.rounded(.up))))
        // The caps, clamped into the image, then into the cells: caps wider
        // than the frame share it in proportion.
        let lead = Swift.min(Swift.max(0, leading), source)
        let trail = Swift.min(Swift.max(0, trailing), source - lead)
        var leadCells = Int((Double(lead) / scale).rounded())
        var trailCells = Int((Double(trail) / scale).rounded())
        if leadCells + trailCells > cells {
            let total = leadCells + trailCells
            leadCells = leadCells * cells / total
            trailCells = cells - leadCells
        }
        let leadSamples = leadCells * perCell
        let trailSamples = trailCells * perCell
        let middleSamples = cells * perCell - leadSamples - trailSamples
        let middle = source - lead - trail

        var map: [Int] = []
        map.reserveCapacity(cells * perCell)
        for index in 0..<leadSamples { map.append(index * lead / leadSamples) }
        if middle > 0 {
            // One tile is the middle at the fitted scale.
            let period = tiles
                ? Swift.max(1, Int((Double(middle) / scale * Double(perCell)).rounded())) : middleSamples
            for index in 0..<middleSamples {
                map.append(lead + (index % Swift.max(1, period)) * middle / Swift.max(1, period))
            }
        } else {
            // The caps are the whole image: the seam between them fills.
            map.append(contentsOf: repeatElement(Swift.min(source - 1, lead), count: middleSamples))
        }
        for index in 0..<trailSamples { map.append(source - trail + index * trail / trailSamples) }
        return map
    }
}
