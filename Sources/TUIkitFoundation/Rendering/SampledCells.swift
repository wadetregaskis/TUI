//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SampledCells.swift
//
//  A paint sampled cell by cell — a mesh gradient — as a ramp sampler's
//  entries: its colours over the cells of an extent, worked out a band of rows
//  at a time as they are asked for.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

/// A paint whose colour is worked out for each cell on its own — a mesh's
/// (``MeshRaster``) — rather than read off a ramp.
protocol CellColourRaster {
    /// The colours of the cells in `columns` × `rows`, row by row.
    func colours(columns: Range<Int>, rows: Range<Int>) -> [Color]
}

extension MeshRaster: CellColourRaster {}

/// A per-cell paint's colours over a ramp's extent, for ``RampSampler``.
///
/// A ramp's sampler knows every colour it can hand out before the first cell is
/// asked — they are the steps of the ramp — and its callers key their escape
/// tables by entry. A mesh's colours are not a sequence to sample in advance:
/// each cell's is the mesh at that cell. So this names them as they are met,
/// the same colour the same entry, and the callers' tables grow to fit
/// (`PaintRenderer.band`, `.background`).
///
/// The rows are worked out a band at a time, the first time any cell of the
/// band is asked about, and kept for as long as the sampler is. Never all of
/// them at once: a `Table`'s ramp runs over every row of its data and is asked
/// only about the rows on screen.
///
/// A class because the sampler that holds it is a value its callers copy and
/// ask from, and what has been worked out has to stay worked out.
final class SampledCells {
    /// How many rows are worked out at a time.
    static let bandRows = 8

    private let raster: any CellColourRaster
    /// How many columns, from the block's own first, a band covers.
    private let columns: Int
    private let depth: ColorDepth

    /// Every colour named so far, by entry.
    private(set) var colours: [Color] = []
    private var named: [Color: Int] = [:]
    private var bands: [Int: [Int32]] = [:]
    private var currentBand = Int.min
    private var currentEntries: [Int32] = []

    /// The cells of `paint` over `extent`, from its origin: column 0 of the
    /// block is the extent's `originX`, and row 0 its `originY`.
    convenience init(mesh paint: MeshPaint, extent: GradientFrame, depth: ColorDepth) {
        self.init(
            raster: MeshRaster(
                paint: paint, offset: SIMD2(Double(extent.originX), Double(extent.originY)),
                extent: SIMD2(Double(max(1, extent.width)), Double(max(1, extent.height)))),
            columns: max(1, extent.width - extent.originX), depth: depth)
    }

    /// The cells `raster` colours, `columns` of them a row, quantised for
    /// `depth`.
    init(raster: any CellColourRaster, columns: Int, depth: ColorDepth) {
        self.raster = raster
        self.columns = max(1, columns)
        self.depth = depth
    }

    /// The entry for the block's cell at `column`, `row`. A column past the
    /// extent takes the nearest one inside it.
    func entry(column: Int, row: Int) -> Int {
        let band = row >= 0 ? row / Self.bandRows : -((-row - 1) / Self.bandRows) - 1
        if band != currentBand { load(band) }
        let local = (row - band * Self.bandRows) * columns + min(columns - 1, max(0, column))
        return Int(currentEntries[local])
    }

    private func load(_ band: Int) {
        currentBand = band
        if let kept = bands[band] {
            currentEntries = kept
            return
        }
        let first = band * Self.bandRows
        let samples = raster.colours(columns: 0..<columns, rows: first..<(first + Self.bandRows))
        let entries = samples.map { Int32(name($0.downsampled(to: depth))) }
        bands[band] = entries
        currentEntries = entries
    }

    /// The entry for `colour`, naming it if it is new.
    private func name(_ colour: Color) -> Int {
        if let entry = named[colour] { return entry }
        let entry = colours.count
        colours.append(colour)
        named[colour] = entry
        return entry
    }
}
