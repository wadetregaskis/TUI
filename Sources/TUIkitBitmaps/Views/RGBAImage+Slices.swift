//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RGBAImage+Slices.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation
import TUIkitImage

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
