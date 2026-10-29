//  🖥️ TUI — A Terminal UI framework for Swift
//  _ImageCore+Resizing.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIImage

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
        guard resizing == nil, environment.imageFitTarget == .naturalSize else { return nil }
        return naturalCells(of: rawImage, in: environment)
    }

    /// The image's size in cells at its natural size, before any zoom, where a
    /// cell's size in points is known: ``naturalBox(of:in:)``'s arithmetic,
    /// whether or not the image is resizable — what a sliced image's caps and
    /// tiles are cut at.
    func naturalCells(of rawImage: RGBAImage, in environment: EnvironmentValues) -> (width: Int, height: Int)? {
        guard let cell = environment.imageCellPoints, rawImage.width > 0, rawImage.height > 0 else { return nil }
        let size = pointSize(of: rawImage)
        func cells(_ points: Double, _ cell: Double) -> Int {
            let count = (points / cell).rounded()
            guard count.isFinite else { return 1 }
            return Int(Swift.min(Swift.max(1, count), Double(Self.maximumNaturalCells)))
        }
        return (cells(size.width, cell.width), cells(size.height, cell.height))
    }

    /// The image's size in points.
    private func pointSize(of rawImage: RGBAImage) -> (width: Double, height: Double) {
        decoded?.pointSize(of: rawImage) ?? (width: Double(rawImage.width), height: Double(rawImage.height))
    }

    /// `resizing` with the box its slices are cut at, where the image is drawn in
    /// slices and a cell's size in points is known (``_ImageResizing/sliceBox``).
    func slicing(_ resizing: _ImageResizing?, of rawImage: RGBAImage, in environment: EnvironmentValues)
        -> _ImageResizing?
    {
        guard var resizing, resizing.slices, let cells = naturalCells(of: rawImage, in: environment) else {
            return resizing
        }
        let points = pointSize(of: rawImage)
        let perPoint = points.width > 0 ? Double(rawImage.width) / points.width : 1
        resizing.sliceBox = .init(width: cells.width, height: cells.height, pixelsPerPoint: perPoint)
        return resizing
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
    ) -> (image: RGBAImage, width: Int, height: Int, resizing: _ImageResizing?, keepsAspect: Bool) {
        guard let natural = naturalBox(of: image, in: environment) else {
            let resizing = slicing(effectiveResizing(in: environment), of: image, in: environment)
            return (image, space.width, space.height, resizing, false)
        }
        let full = (width: Self.zoomed(natural.width, zoom), height: Self.zoomed(natural.height, zoom))
        let width = Swift.min(full.width, space.width)
        let height = Swift.min(full.height, space.height)
        // Whole at its natural size, the box is the picture's own rounded to
        // whole cells, so its pixels keep their aspect (`PixelFit.ownAspect`)
        // rather than stretch by up to half a cell on each axis.
        guard width < full.width || height < full.height else { return (image, width, height, .filling, true) }
        let cut = image.croppedToLeading(
            fraction: (Double(width) / Double(full.width), Double(height) / Double(full.height)))
        return (cut, width, height, .filling, false)
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
            let size = ASCIIConverter.targetSize(
                imageWidth: imageWidth, imageHeight: imageHeight,
                maxWidth: maxWidth, maxHeight: maxHeight,
                contentMode: stretches ? .fit : contentMode,
                overrideAspectRatio: aspectRatio, cellAspect: cellAspect)
            // Held as at the natural size: the converter clamps an extreme
            // ratio's side to `Int.max`, which its own pixel arithmetic then
            // overflowed.
            func held(_ cells: Int) -> Int { Swift.min(cells, Self.maximumNaturalCells) }
            return (held(size.width), held(size.height))
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
