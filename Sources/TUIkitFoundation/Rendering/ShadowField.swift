//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShadowField.swift
//
//  How dark a shadow is at each cell: the cells a view paints, offset, and an
//  alpha that falls off across `radius` cells beyond them (a drop shadow) or in
//  from their edges (an inner one).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The cells a view paints

/// Which cells of a rendered view it paints: a glyph, or a blank that shows
/// something of its own — a field, reverse video, an underline or a strike
/// (`String.columnsShowingNothing(width:)`, inverted).
///
/// A shadow is cast by these. SwiftUI casts one from a view's per-pixel alpha,
/// and at a cell's resolution that alpha is whether the cell is painted at all:
/// a label with no background casts the shape of its letters, a filled card its
/// rectangle.
struct ShadowFootprint {
    let width: Int
    let height: Int
    /// Row-major, `width × height`.
    private let painted: [Bool]
    /// The smallest rectangle holding every painted cell, `nil` when none is.
    let bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)?

    init(_ buffer: FrameBuffer) {
        width = buffer.width
        height = buffer.lines.count
        var painted = [Bool]()
        painted.reserveCapacity(width * height)
        var bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        for (row, line) in buffer.lines.enumerated() {
            let nothing = line.columnsShowingNothing(width: width)
            for column in 0..<width {
                let paints = !nothing[column]
                painted.append(paints)
                guard paints else { continue }
                if let known = bounds {
                    bounds = (
                        min(known.minX, column), min(known.minY, row), max(known.maxX, column), max(known.maxY, row)
                    )
                } else {
                    bounds = (column, row, column, row)
                }
            }
        }
        self.painted = painted
        self.bounds = bounds
    }

    /// Whether the cell at `column`, `row` is painted; a cell outside the view
    /// is not.
    func paints(column: Int, row: Int) -> Bool {
        guard column >= 0, column < width, row >= 0, row < height else { return false }
        return painted[row * width + column]
    }
}

// MARK: - The alpha at each cell

/// A shadow's alpha over a rectangle of cells, in the shadowed view's
/// coordinates.
struct ShadowField {
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int
    /// Row-major, `width × height`: the shadow's alpha at each cell, `0` where
    /// it lays none.
    let alphas: [UInt8]

    /// The alpha at `column`, `row` of the rectangle (its own coordinates).
    func alpha(column: Int, row: Int) -> UInt8 { alphas[row * width + column] }

    /// Whether the shadow lays anything anywhere.
    var isEmpty: Bool { !alphas.contains { $0 > 0 } }

    /// How far from the cells that cast it a shadow is drawn at most, whatever
    /// its radius: 256 cells.
    ///
    /// A terminal shows a few hundred columns at the very most, and a shadow
    /// costs the area it covers, so a radius past this — a ported
    /// `radius: 1000` — would cost a square two thousand cells on a side, all
    /// but a corner of it off the screen. The alpha still falls off at the
    /// radius's own rate inside the reach, so what a screen shows is the
    /// radius's answer.
    static let reachLimit = 256

    /// How far an offset moves a shadow at most: 2^20 cells, past every
    /// screen, which keeps the arithmetic placing it far from overflowing.
    static let offsetLimit = 1 << 20

    /// A drop shadow's field: `footprint` moved by the style's offset, at the
    /// colour's alpha, falling off across `radius` cells around it.
    ///
    /// - Parameters:
    ///   - footprint: The cells the view paints.
    ///   - style: The shadow; its kind is not read.
    ///   - peak: The alpha on the moved footprint itself — the colour's.
    /// - Returns: The field over the moved footprint's bounds, `radius` larger
    ///   all round (``reachLimit`` at most), or `nil` when the view paints
    ///   nothing.
    static func drop(footprint: ShadowFootprint, style: ShadowStyle, peak: UInt8) -> Self? {
        guard let bounds = footprint.bounds, peak > 0 else { return nil }
        let reach = min(style.radius, reachLimit)
        let x = min(max(style.x, -offsetLimit), offsetLimit)
        let y = min(max(style.y, -offsetLimit), offsetLimit)
        let originX = bounds.minX + x - reach
        let originY = bounds.minY + y - reach
        let width = bounds.maxX - bounds.minX + 1 + 2 * reach
        let height = bounds.maxY - bounds.minY + 1 + 2 * reach
        // Every painted cell, moved, lies in the rectangle, so the distance to
        // the nearest is exact everywhere in it.
        let distances = squaredDistances(width: width, height: height) { column, row in
            footprint.paints(column: originX + column - x, row: originY + row - y)
        }
        let ramp = alphaRamp(radius: style.radius, reach: reach, peak: peak)
        return Self(
            originX: originX, originY: originY, width: width, height: height,
            alphas: distances.map { ramp[ring(of: $0, reach: reach)] })
    }

    /// An inner shadow's field: over the cells the view paints, the colour's
    /// alpha falling off across `radius` cells in from the nearest cell it does
    /// not paint — the view's own unpainted cells and everything outside it —
    /// with that outside moved by the style's offset, so the shadow is deepest
    /// on the side the offset points away from.
    ///
    /// - Parameters:
    ///   - footprint: The cells the view paints.
    ///   - style: The shadow; its kind is not read.
    ///   - peak: The alpha where the moved outside covers a painted cell.
    /// - Returns: The field over the view, or `nil` when the view paints
    ///   nothing.
    static func inner(footprint: ShadowFootprint, style: ShadowStyle, peak: UInt8) -> Self? {
        guard footprint.bounds != nil, peak > 0 else { return nil }
        let reach = min(style.radius, reachLimit)
        let x = min(max(style.x, -offsetLimit), offsetLimit)
        let y = min(max(style.y, -offsetLimit), offsetLimit)
        // One cell more than the reach all round: the nearest unpainted cell
        // that matters is never further from the view than that, and every cell
        // outside the view is unpainted.
        let margin = reach + 1
        let width = footprint.width + 2 * margin
        let height = footprint.height + 2 * margin
        let distances = squaredDistances(width: width, height: height) { column, row in
            !footprint.paints(column: column - margin - x, row: row - margin - y)
        }
        let ramp = alphaRamp(radius: style.radius, reach: reach, peak: peak)
        var alphas = [UInt8]()
        alphas.reserveCapacity(footprint.width * footprint.height)
        for row in 0..<footprint.height {
            for column in 0..<footprint.width {
                guard footprint.paints(column: column, row: row) else {
                    alphas.append(0)
                    continue
                }
                let distance = distances[(row + margin) * width + column + margin]
                alphas.append(ramp[ring(of: distance, reach: reach)])
            }
        }
        return Self(
            originX: 0, originY: 0, width: footprint.width, height: footprint.height, alphas: alphas)
    }

    /// The alpha at each ring, `0` through `reach`, and `0` past it at
    /// `reach + 1`: `peak` on the footprint, falling by `peak / (radius + 1)`
    /// a ring, so it reaches nothing at the ring past `radius`.
    ///
    /// - Parameters:
    ///   - radius: The shadow's radius, which sets the step.
    ///   - reach: The last ring drawn: the radius, or ``reachLimit`` past it.
    ///   - peak: The alpha at ring `0`.
    static func alphaRamp(radius: Int, reach: Int, peak: UInt8) -> [UInt8] {
        let rings = Double(radius) + 1
        return (0...reach).map { ring in UInt8((Double(peak) * (rings - Double(ring)) / rings).rounded()) } + [0]
    }

    /// The ring a cell `squaredDistance` from the footprint is in: the distance
    /// rounded to whole cells, `reach + 1` for anything past the last ring
    /// drawn.
    ///
    /// Rounded rather than truncated or raised: the cell diagonally off a
    /// corner, 1.4 cells out, is in the first ring with the cells beside it, so
    /// a shadow one cell wide keeps square corners and wider ones round off.
    static func ring(of squaredDistance: Int?, reach: Int) -> Int {
        guard let squaredDistance else { return reach + 1 }
        return min(reach + 1, Int(Double(squaredDistance).squareRoot().rounded()))
    }

    /// The squared Euclidean distance, in cells, from each cell of a `width` ×
    /// `height` rectangle to the nearest cell of it where `isSource` holds, or
    /// `nil` where none does — row-major.
    ///
    /// Two passes, each linear: along every row the distance to the nearest
    /// source in that row, then down every column the lower envelope of the
    /// parabolas those distances make (Felzenszwalb and Huttenlocher, "Distance
    /// Transforms of Sampled Functions", 2012). So the cost is the rectangle's
    /// area whatever the radius, which only sets how large the rectangle is.
    static func squaredDistances(width: Int, height: Int, isSource: (Int, Int) -> Bool) -> [Int?] {
        guard width > 0, height > 0 else { return [] }
        // Along each row: the distance to the nearest source in it.
        var along = [Int?](repeating: nil, count: width * height)
        for row in 0..<height {
            var last: Int?
            for column in 0..<width {
                if isSource(column, row) { last = column }
                if let last { along[row * width + column] = column - last }
            }
            last = nil
            for column in stride(from: width - 1, through: 0, by: -1) {
                let index = row * width + column
                if along[index] == 0 { last = column }
                if let last, along[index].map({ last - column < $0 }) ?? true { along[index] = last - column }
            }
        }
        // Down each column: the nearest of those, counting the rows between.
        var squared = [Int?](repeating: nil, count: width * height)
        var column = [Int?](repeating: nil, count: height)
        for x in 0..<width {
            for y in 0..<height { column[y] = along[y * width + x].map { $0 * $0 } }
            let envelope = lowerEnvelope(column)
            for y in 0..<height { squared[y * width + x] = envelope[y] }
        }
        return squared
    }

    /// For each index `p` of `costs`, the least `(p − q)² + costs[q]` over the
    /// `q` that have a cost, or `nil` where none does: the one-dimensional
    /// squared distance transform.
    private static func lowerEnvelope(_ costs: [Int?]) -> [Int?] {
        // The parabolas making up the envelope, by their vertex, and where each
        // one starts being the lowest.
        var vertices: [Int] = []
        var starts: [Double] = []
        for (vertex, cost) in costs.enumerated() {
            guard let cost else { continue }
            var start = -Double.infinity
            while let previous = vertices.last, let previousCost = costs[previous] {
                start =
                    Double((cost + vertex * vertex) - (previousCost + previous * previous))
                    / Double(2 * (vertex - previous))
                guard start <= starts[starts.count - 1] else { break }
                vertices.removeLast()
                starts.removeLast()
                start = -Double.infinity
            }
            vertices.append(vertex)
            starts.append(start)
        }
        guard !vertices.isEmpty else { return costs.map { _ in nil } }
        var result = [Int?](repeating: nil, count: costs.count)
        var parabola = 0
        for point in costs.indices {
            while parabola + 1 < vertices.count, starts[parabola + 1] < Double(point) { parabola += 1 }
            let vertex = vertices[parabola]
            let offset = point - vertex
            result[point] = offset * offset + (costs[vertex] ?? 0)
        }
        return result
    }
}
