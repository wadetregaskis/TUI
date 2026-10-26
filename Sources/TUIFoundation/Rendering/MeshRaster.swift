//  🖥️ TUI — A Terminal UI framework for Swift
//  MeshRaster.swift
//
//  A mesh gradient over a grid of samples — cells, or a picture's pixels.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

// MARK: - The raster

/// Which colour each sample of a grid takes under a mesh.
///
/// A sample is a point — a cell's centre, or a picture pixel's — and its colour
/// is the mesh's at that point: the patch it falls in and the `(u, v)` it falls
/// at, then ``MeshColourField``. The work is the first half, which has two
/// ways in:
///
/// - **A grid of rectangles**, the common mesh (``MeshVertices/rectilinear``):
///   each patch is its own bilinear map, so `(u, v)` is a lookup of the column
///   and row a sample lies between and two divisions. No subdivision at all.
/// - **Anything else**: each patch is split in half — de Casteljau on its
///   sixteen points, across whichever way it bends more — until every piece is
///   within a twentieth of a sample of the bilinear map of its own corners,
///   skipping any piece whose control points' box misses the samples asked
///   for. Each sample in a piece is then placed by inverting that bilinear
///   map. SwiftUI tessellates too; this tessellation is finer than a sample,
///   and each halving takes a curved piece a quarter of the way closer to
///   flat, so a gently warped patch is a few dozen pieces. Cost follows the
///   samples ASKED FOR rather than the size of the mesh, which is what lets a
///   `Table` ask for one row of a ramp ten thousand rows tall.
///
/// Patches are drawn in reading order, a later one over an earlier where a
/// mesh folds over itself. A sample no patch reaches takes the background.
struct MeshRaster {
    private let background: Color
    private let field: MeshColourField
    private let vertices: MeshVertices?
    private let grid: (columns: [Double], rows: [Double])?
    /// Every patch, in sample space, row by row.
    private let nets: [MeshPatchNet]
    private let offset: SIMD2<Double>
    private let extent: SIMD2<Double>

    /// A raster of `paint` over a grid whose sample `(i, j)` sits at the unit
    /// point `((offset.x + i + ½) / extent.x, (offset.y + j + ½) / extent.y)` —
    /// for cells, `offset` is where the painted block starts in the ramp's
    /// extent and `extent` that extent's size.
    init(paint: MeshPaint, offset: SIMD2<Double>, extent: SIMD2<Double>) {
        background = paint.background
        field = MeshColourField(paint)
        let vertices = MeshVertices(paint)
        self.vertices = vertices
        self.offset = offset
        self.extent = extent
        grid = vertices?.rectilinear
        guard let vertices, grid == nil else {
            nets = []
            return
        }
        var nets: [MeshPatchNet] = []
        nets.reserveCapacity((vertices.width - 1) * (vertices.height - 1))
        for row in 0..<(vertices.height - 1) {
            for column in 0..<(vertices.width - 1) {
                nets.append(vertices.net(column: column, row: row).mapped(scale: extent, offset: offset))
            }
        }
        self.nets = nets
    }

    /// The colours of the samples in `columns` × `rows`, row by row.
    func colours(columns: Range<Int>, rows: Range<Int>) -> [Color] {
        guard let vertices, !columns.isEmpty, !rows.isEmpty else {
            return Array(repeating: background, count: columns.count * rows.count)
        }
        var hits = Hits(columns: columns, rows: rows)
        if let grid {
            hits.fill(grid: grid, offset: offset, extent: extent)
        } else {
            for (index, net) in nets.enumerated() {
                hits.draw(net, patch: Int32(index), range: Hits.ParameterRange(), depth: 0)
            }
        }
        let patchColumns = vertices.width - 1
        var out: [Color] = []
        out.reserveCapacity(hits.patch.count)
        for index in hits.patch.indices {
            let patch = Int(hits.patch[index])
            guard patch >= 0 else {
                out.append(background)
                continue
            }
            out.append(
                field.colour(
                    column: patch % patchColumns, row: patch / patchColumns, across: hits.across[index],
                    down: hits.down[index]))
        }
        return out
    }
}

// MARK: - Where samples land

/// For each sample of a region, the patch it fell in (`-1` for none) and its
/// `(u, v)` there: how far `across` the patch and how far `down` it.
private struct Hits {
    let columns: Range<Int>
    let rows: Range<Int>
    var patch: [Int32]
    var across: [Double]
    var down: [Double]

    init(columns: Range<Int>, rows: Range<Int>) {
        self.columns = columns
        self.rows = rows
        let count = columns.count * rows.count
        patch = Array(repeating: -1, count: count)
        across = Array(repeating: 0, count: count)
        down = Array(repeating: 0, count: count)
    }

    /// The part of a patch's parameter square a piece of it covers.
    struct ParameterRange {
        var u0 = 0.0
        var u1 = 1.0
        var v0 = 0.0
        var v1 = 1.0
    }

    // MARK: A grid of rectangles

    /// Every sample's patch and `(u, v)` in a mesh whose patches are rectangles
    /// at these column and row positions.
    mutating func fill(grid: (columns: [Double], rows: [Double]), offset: SIMD2<Double>, extent: SIMD2<Double>) {
        let placesAcross = columns.map {
            Self.locate((offset.x + Double($0) + 0.5) / extent.x, in: grid.columns)
        }
        let placesDown = rows.map {
            Self.locate((offset.y + Double($0) + 0.5) / extent.y, in: grid.rows)
        }
        let patchColumns = grid.columns.count - 1
        var index = 0
        for vertical in placesDown {
            guard let vertical else {
                index += placesAcross.count
                continue
            }
            for horizontal in placesAcross {
                defer { index += 1 }
                guard let horizontal else { continue }
                patch[index] = Int32(vertical.cell * patchColumns + horizontal.cell)
                across[index] = horizontal.fraction
                down[index] = vertical.fraction
            }
        }
    }

    /// Which interval of `positions` holds `value`, and how far along it —
    /// `nil` outside them all.
    private static func locate(_ value: Double, in positions: [Double]) -> (cell: Int, fraction: Double)? {
        guard let first = positions.first, let last = positions.last, value >= first, value <= last,
            positions.count >= 2
        else { return nil }
        var low = 0
        var high = positions.count - 2
        while low < high {
            let middle = (low + high + 1) / 2
            if positions[middle] <= value { low = middle } else { high = middle - 1 }
        }
        return (low, (value - positions[low]) / (positions[low + 1] - positions[low]))
    }

    // MARK: Any mesh

    /// The deepest a patch is split in either direction — 2²⁴ pieces across,
    /// far past any extent a terminal draws, so only a degenerate patch (NaN,
    /// or a point stretched to infinity) ever reaches it.
    private static let maximumDepth = 24

    /// How far, in samples, a piece's control points may stray from the
    /// bilinear map of its corners and still be drawn as that map.
    private static let flatEnough = 0.05

    /// How far past a piece's edge, in samples, a sample may lie and still
    /// count as inside it. Neighbouring pieces split to different depths meet
    /// along slightly different approximations of the same curve, at most
    /// ``flatEnough`` apart, and this closes the sliver between them; at the
    /// mesh's own edge it is a tenth of a sample.
    private static let edgeTolerance = 0.1

    /// Draws one patch — or a piece of one — into the samples it covers.
    mutating func draw(_ net: MeshPatchNet, patch patchIndex: Int32, range: ParameterRange, depth: Int) {
        guard let bounds = net.bounds else { return }
        // Sample centres sit at `i + ½`; a piece is skipped when its box misses
        // every centre asked for.
        let slack = Self.edgeTolerance
        guard bounds.high.x >= Double(columns.lowerBound) + 0.5 - slack,
            bounds.low.x <= Double(columns.upperBound) - 0.5 + slack,
            bounds.high.y >= Double(rows.lowerBound) + 0.5 - slack,
            bounds.low.y <= Double(rows.upperBound) - 0.5 + slack
        else { return }
        guard net.deviation > Self.flatEnough, depth < Self.maximumDepth else {
            drawPiece(net, patch: patchIndex, range: range)
            return
        }
        var low = range
        var high = range
        let halves: (MeshPatchNet, MeshPatchNet)
        if net.bendsMoreAlongU {
            halves = net.splitU()
            let middle = (range.u0 + range.u1) / 2
            low.u1 = middle
            high.u0 = middle
        } else {
            halves = net.splitV()
            let middle = (range.v0 + range.v1) / 2
            low.v1 = middle
            high.v0 = middle
        }
        draw(halves.0, patch: patchIndex, range: low, depth: depth + 1)
        draw(halves.1, patch: patchIndex, range: high, depth: depth + 1)
    }

    /// A piece flat enough to be the bilinear map of its corners: each sample
    /// in its box is placed by inverting that map.
    private mutating func drawPiece(_ net: MeshPatchNet, patch patchIndex: Int32, range: ParameterRange) {
        let quad = (net[0, 0], net[3, 0], net[3, 3], net[0, 3])
        let low = MeshPoint(
            min(min(quad.0.x, quad.1.x), min(quad.2.x, quad.3.x)), min(min(quad.0.y, quad.1.y), min(quad.2.y, quad.3.y)))
        let high = MeshPoint(
            max(max(quad.0.x, quad.1.x), max(quad.2.x, quad.3.x)), max(max(quad.0.y, quad.1.y), max(quad.2.y, quad.3.y)))
        let slack = Self.edgeTolerance
        let lowX = max(Double(columns.lowerBound), (low.x - 0.5 - slack).rounded(.up))
        let highX = min(Double(columns.upperBound - 1), (high.x - 0.5 + slack).rounded(.down))
        let lowY = max(Double(rows.lowerBound), (low.y - 0.5 - slack).rounded(.up))
        let highY = min(Double(rows.upperBound - 1), (high.y - 0.5 + slack).rounded(.down))
        guard lowX <= highX, lowY <= highY else { return }
        // The tolerance in each parameter: a tenth of a sample, over the side.
        let span = net.span
        let toleranceS = slack / max(span.u, slack)
        let toleranceT = slack / max(span.v, slack)
        for row in Int(lowY)...Int(highY) {
            for column in Int(lowX)...Int(highX) {
                let point = MeshPoint(Double(column) + 0.5, Double(row) + 0.5)
                guard let (s, t) = Self.invertBilinear(point, quad, tolerance: (toleranceS, toleranceT)) else {
                    continue
                }
                let index = (row - rows.lowerBound) * columns.count + (column - columns.lowerBound)
                patch[index] = patchIndex
                across[index] = range.u0 + (range.u1 - range.u0) * min(1, max(0, s))
                down[index] = range.v0 + (range.v1 - range.v0) * min(1, max(0, t))
            }
        }
    }

    /// Where `point` lies in the bilinear map of a quadrilateral — corners at
    /// `(0, 0)`, `(1, 0)`, `(1, 1)`, `(0, 1)` in that order — or `nil` when it
    /// lies outside by more than the tolerance in either parameter.
    ///
    /// The map is `origin + alongS·s + alongT·t + twist·s·t`; eliminating `s`
    /// leaves a quadratic in `t`, linear when the opposite sides are parallel.
    private static func invertBilinear(
        _ point: MeshPoint, _ quad: (MeshPoint, MeshPoint, MeshPoint, MeshPoint), tolerance: (Double, Double)
    ) -> (Double, Double)? {
        let (origin, alongS, opposite, alongT) = (quad.0, quad.1 - quad.0, quad.2, quad.3 - quad.0)
        let twist = quad.0 - quad.1 + opposite - quad.3
        let offset = point - origin
        let k2 = MeshPoint.cross(twist, alongT)
        let k1 = MeshPoint.cross(alongS, alongT) + MeshPoint.cross(offset, twist)
        let k0 = MeshPoint.cross(offset, alongS)
        func across(at t: Double) -> Double? {
            let alongX = alongS.x + twist.x * t
            let alongY = alongS.y + twist.y * t
            if abs(alongX) >= abs(alongY) {
                return alongX == 0 ? nil : (offset.x - alongT.x * t) / alongX
            }
            return (offset.y - alongT.y * t) / alongY
        }
        func accepted(_ s: Double, _ t: Double) -> Bool {
            s >= -tolerance.0 && s <= 1 + tolerance.0 && t >= -tolerance.1 && t <= 1 + tolerance.1
        }
        let scale = max(abs(k1), abs(k0), 1e-300)
        if abs(k2) <= 1e-12 * scale {
            guard k1 != 0 else { return nil }
            let t = -k0 / k1
            guard let s = across(at: t), accepted(s, t) else { return nil }
            return (s, t)
        }
        let discriminant = k1 * k1 - 4 * k0 * k2
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        // The two roots, nearer first; a piece flat enough to be drawn holds at
        // most one inside it.
        let near = (-k1 - root) / (2 * k2)
        if let s = across(at: near), accepted(s, near) { return (s, near) }
        let far = (-k1 + root) / (2 * k2)
        if let s = across(at: far), accepted(s, far) { return (s, far) }
        return nil
    }
}
