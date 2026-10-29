//  🖥️ TUI — A Terminal UI framework for Swift
//  RGBAImage+Slices.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIImage

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

    /// The image cut to the aspect of `width` × `height`, centred — the part a
    /// box of that aspect shows of it when filled with its own aspect kept, as
    /// `.scaledToFill()` fills one. Itself where it already has that aspect.
    func centreCropped(toAspectOf width: Int, _ height: Int) -> RGBAImage {
        let (columns, rows) = croppedSize(toAspectOf: width, height)
        guard columns != self.width || rows != self.height else { return self }
        let left = (self.width - columns) / 2
        let top = (self.height - rows) / 2
        var out: [RGBA] = []
        out.reserveCapacity(columns * rows)
        for row in top..<(top + rows) {
            let start = row * self.width + left
            out.append(contentsOf: pixels[start..<(start + columns)])
        }
        return RGBAImage(width: columns, height: rows, pixels: out)
    }

    /// The size of ``centreCropped(toAspectOf:_:)``, worked out without
    /// copying a pixel.
    func croppedSize(toAspectOf width: Int, _ height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0, self.width > 0, self.height > 0 else { return (self.width, self.height) }
        let wanted = Double(width) / Double(height)
        let own = Double(self.width) / Double(self.height)
        if own > wanted { return (max(1, Int((Double(self.height) * wanted).rounded())), self.height) }
        if own < wanted { return (self.width, max(1, Int((Double(self.width) / wanted).rounded()))) }
        return (self.width, self.height)
    }

    /// The image in nine slices, made to fill `columns` × `rows` cells: its
    /// caps at its natural size (``_ImageResizing/sliceBox``), or at the scale
    /// the whole image fits those cells at where that is unknown, and the edges
    /// and centre between them stretched or tiled at that size. Cap insets are
    /// in points, so they are scaled to pixels by the image's pixels per point.
    ///
    /// Picked rather than resampled — each sample is one source pixel — at
    /// two to four samples a cell, which the converter then averages.
    func sliced(_ resizing: _ImageResizing, columns: Int, rows: Int, cellAspect: Double) -> RGBAImage {
        let fitted =
            resizing.sliceBox.map { (width: $0.width, height: $0.height) }
            ?? ASCIIConverter.targetSize(
                imageWidth: width, imageHeight: height, maxWidth: columns, maxHeight: rows,
                contentMode: .fit, cellAspect: cellAspect)
        let tiles = resizing.mode == .tile
        let perPoint = resizing.sliceBox?.pixelsPerPoint ?? 1
        // Clamping: a cap inset of `Int.max` points is past `Int` in pixels.
        func inPixels(_ points: Int) -> Int { Int(clamping: (Double(points) * perPoint).rounded()) }
        let xs = Self.sliceMap(
            source: width, leading: inPixels(resizing.capInsets.leading), trailing: inPixels(resizing.capInsets.trailing),
            cells: columns, fittedCells: fitted.width, tiles: tiles)
        let ys = Self.sliceMap(
            source: height, leading: inPixels(resizing.capInsets.top), trailing: inPixels(resizing.capInsets.bottom),
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
    ///   - fittedCells: The cells the whole image takes on this axis at the
    ///     size its caps keep and its tiles repeat at.
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
