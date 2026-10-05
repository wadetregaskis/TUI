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

extension _ImageCore {
    /// The resizing this image draws with here: its own, unless a content mode
    /// set around it keeps its aspect instead.
    func effectiveResizing(in environment: EnvironmentValues) -> _ImageResizing? {
        environment.imageExplicitContentMode == nil ? resizing : nil
    }

    /// The cells a loaded image takes at its natural size, before any zoom —
    /// its size in points over the cell's — or `nil` where it takes none and
    /// fits what it is offered instead.
    ///
    /// SwiftUI draws an image that is not resizable at its size in points:
    /// its pixels over its scale (``_DecodedImage/pointSize(of:)``). A cell's
    /// size in points is what turns that into cells, and it is known only
    /// where the host's report has been measured
    /// (``EnvironmentValues/imageCellPoints``). So: an image that is not
    /// resizable, under the default ``ImageFitTarget/naturalSize``, where the
    /// cell's size is known. Rounded to whole cells, at least one each way,
    /// and at most `maximumNaturalCells`.
    func naturalBox(of rawImage: RGBAImage, in environment: EnvironmentValues) -> (width: Int, height: Int)? {
        guard resizing == nil, environment.imageFitTarget == .naturalSize,
            let cell = environment.imageCellPoints, rawImage.width > 0, rawImage.height > 0
        else { return nil }
        let size = decoded?.pointSize(of: rawImage) ?? (width: Double(rawImage.width), height: Double(rawImage.height))
        func cells(_ points: Double, _ cell: Double) -> Int {
            let count = (points / cell).rounded()
            guard count.isFinite else { return 1 }
            return Int(Swift.min(Swift.max(1, count), Double(Self.maximumNaturalCells)))
        }
        return (cells(size.width, cell.width), cells(size.height, cell.height))
    }

    /// What a loaded image draws, into which box, and how it fills it.
    ///
    /// At its natural size the image draws its own box, whatever it was
    /// handed — as the measure said, and as SwiftUI draws a picture that is not
    /// resizable. The box IS the image's shape, so it is filled rather than
    /// fitted, which could lose a cell to rounding.
    ///
    /// Larger than the space it was given, it is cut to that space from its
    /// top-leading corner, as every view's buffer is cut to its space — but its
    /// PIXELS are cut first, so the part nobody will see is never converted. A
    /// picture tens of thousands of pixels across, at its natural size in an
    /// 80-column terminal, converts 80 columns.
    ///
    /// Otherwise it is the image whole, in `space`, with its own resizing.
    func drawing(
        _ image: RGBAImage, in space: (width: Int, height: Int), zoom: Double, environment: EnvironmentValues
    ) -> (image: RGBAImage, width: Int, height: Int, resizing: _ImageResizing?) {
        guard let natural = naturalBox(of: image, in: environment) else {
            return (image, space.width, space.height, effectiveResizing(in: environment))
        }
        let full = (width: Self.zoomed(natural.width, zoom), height: Self.zoomed(natural.height, zoom))
        let width = Swift.min(full.width, space.width)
        let height = Swift.min(full.height, space.height)
        guard width < full.width || height < full.height else { return (image, width, height, .filling) }
        let cut = image.croppedToLeading(
            fraction: (Double(width) / Double(full.width), Double(height) / Double(full.height)))
        return (cut, width, height, .filling)
    }

    /// The most cells an image takes on either axis at its natural size: more
    /// than any terminal shows, and the bound that keeps the arithmetic, and the
    /// conversion, finite for a picture tens of thousands of pixels across.
    static let maximumNaturalCells = 4_096

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
    /// The image's top-leading part: `fraction` of its width and of its
    /// height, rounded up to whole pixels, at least one each way.
    func croppedToLeading(fraction: (width: Double, height: Double)) -> RGBAImage {
        guard width > 0, height > 0 else { return self }
        let columns = Swift.min(width, Swift.max(1, Int((Double(width) * fraction.width).rounded(.up))))
        let rows = Swift.min(height, Swift.max(1, Int((Double(height) * fraction.height).rounded(.up))))
        guard columns < width || rows < height else { return self }
        var out: [RGBA] = []
        out.reserveCapacity(columns * rows)
        for row in 0..<rows {
            out.append(contentsOf: pixels[(row * width)..<(row * width + columns)])
        }
        return RGBAImage(width: columns, height: rows, pixels: out)
    }

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
