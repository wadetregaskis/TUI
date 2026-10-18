//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeRaster.swift
//
//  What a shape covers, pixel by pixel: polygons in, coverage out. Pure
//  arithmetic, so a shape's coverage is the same on every terminal.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Coverage

/// How much of each pixel of a grid a set of polygons covers — the half of
/// drawing a shape that knows nothing about cells or colours.
///
/// A pixel is sampled at a regular `samples × samples` lattice of points, and
/// its coverage is the share of those points inside the polygons by the fill
/// rule. That share is what the cell renderer turns into alpha
/// (`ShapeCells`), and the compositor resolves alpha against what is behind:
/// antialiasing, done by the machinery `.opacity(_:)` already uses
/// (`Documentation/Colour and styling/Opacity as composition.md`).
///
/// The sampling is a scanline walk: for each row of sample points, the
/// polygons' edges that cross it are found, sorted, and the runs between them
/// that the rule says are inside are counted into the pixels they span. Its
/// cost is the rows of samples times the edges, plus the samples inside —
/// nothing per sample outside a run.
struct ShapeCoverage: Equatable {
    /// The grid's width, in pixels.
    let width: Int
    /// The grid's height, in pixels.
    let height: Int
    /// Each pixel's covered sample count, row by row from the top.
    private(set) var counts: [UInt16]
    /// The sample points along each side of a pixel.
    let samples: Int

    /// The share of `pixel` covered, `0…1`.
    func coverage(x: Int, y: Int) -> Double {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return Double(counts[y * width + x]) / Double(samples * samples)
    }

    /// The polygons' coverage of a `width` × `height` grid of unit pixels.
    ///
    /// - Parameters:
    ///   - polygons: The polygons, in pixel coordinates — each implicitly
    ///     closed.
    ///   - evenOdd: Whether a point is inside by the even-odd rule rather than
    ///     the non-zero winding rule.
    ///   - width: The grid's width.
    ///   - height: The grid's height.
    ///   - samples: The sample points along each side of a pixel.
    init(polygons: [[CGPoint]], evenOdd: Bool, width: Int, height: Int, samples: Int = 4) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.samples = max(1, samples)
        self.counts = [UInt16](repeating: 0, count: self.width * self.height)
        guard self.width > 0, self.height > 0 else { return }
        let edges = Self.edges(of: polygons)
        guard !edges.isEmpty else { return }
        let step = 1.0 / Double(self.samples)
        var crossings: [(x: Double, direction: Int)] = []
        crossings.reserveCapacity(16)
        for sampleRow in 0..<(self.height * self.samples) {
            let y = (Double(sampleRow) + 0.5) * step
            crossings.removeAll(keepingCapacity: true)
            for edge in edges where edge.top <= y && y < edge.bottom {
                crossings.append((edge.x(at: y), edge.direction))
            }
            guard crossings.count > 1 else { continue }
            crossings.sort { $0.x < $1.x }
            var winding = 0
            for index in 0..<(crossings.count - 1) {
                winding += crossings[index].direction
                let inside = evenOdd ? !winding.isMultiple(of: 2) : winding != 0
                if inside {
                    fill(from: crossings[index].x, to: crossings[index + 1].x, row: sampleRow / self.samples)
                }
            }
        }
    }

    /// Counts the sample points of pixel row `row` whose x lies in
    /// `[start, end)` — at `(i + ½) / samples` across each pixel.
    private mutating func fill(from start: Double, to end: Double, row: Int) {
        // Samples `first..<last` are inside.
        let first = sampleIndex(atOrAfter: start)
        let last = sampleIndex(atOrAfter: end)
        guard first < last else { return }
        let base = row * width
        var sample = first
        while sample < last {
            let pixel = sample / samples
            let pixelEnd = min(last, (pixel + 1) * samples)
            counts[base + pixel] += UInt16(pixelEnd - sample)
            sample = pixelEnd
        }
    }

    /// The first sample index of a row at or after `x`, held to the row's
    /// `0…width × samples` while it is still a `Double`: a far-off point's
    /// crossing — a line to `.greatestFiniteMagnitude`, a shape scaled by
    /// `1e19` — lies past any `Int`, and converting it first trapped.
    private func sampleIndex(atOrAfter x: Double) -> Int {
        let limit = width * samples
        let index = (x * Double(samples) - 0.5).rounded(.up)
        guard index > 0 else { return 0 }
        return index < Double(limit) ? Int(index) : limit
    }

    /// One edge of a polygon, top to bottom, with which way it ran.
    private struct Edge {
        let top: Double
        let bottom: Double
        let x0: Double
        let slope: Double
        let direction: Int

        func x(at y: Double) -> Double { x0 + (y - top) * slope }
    }

    /// Every non-horizontal edge of `polygons`, each closed back to its start.
    private static func edges(of polygons: [[CGPoint]]) -> [Edge] {
        var edges: [Edge] = []
        for polygon in polygons where polygon.count > 2 {
            var previous = polygon[polygon.count - 1]
            for point in polygon {
                defer { previous = point }
                let (y0, y1) = (Double(previous.y), Double(point.y))
                guard y0 != y1, y0.isFinite, y1.isFinite, previous.x.isFinite, point.x.isFinite else { continue }
                let downward = y1 > y0
                let (top, bottom) = downward ? (previous, point) : (point, previous)
                // A slope too steep to hold is the steepest that is held: where
                // it is infinite, the crossing at the edge's own top would be
                // zero times infinity — not a number, which no clamp orders.
                let slope = Double(bottom.x - top.x) / Double(bottom.y - top.y)
                let held = slope.isFinite ? slope : slope > 0 ? Double.greatestFiniteMagnitude : -Double.greatestFiniteMagnitude
                edges.append(
                    Edge(
                        top: Double(top.y), bottom: Double(bottom.y), x0: Double(top.x), slope: held,
                        direction: downward ? 1 : -1))
            }
        }
        return edges
    }
}

// MARK: - A shape's coverage of whole cells

extension ShapeCoverage {
    /// How much of each whole cell of `frame` `shape` covers — what a clip
    /// keeps by, and where a shape behind a view draws only part of a cell.
    init(cellsOf shape: any Shape, evenOdd: Bool, frame: ShapeFrame) {
        let aspect = CGFloat(frame.aspect)
        let polygons = shape.path(in: frame.rect).contours(tolerance: 0.05).map {
            $0.points.map { CGPoint(x: $0.x, y: $0.y / aspect) }
        }
        self.init(polygons: polygons, evenOdd: evenOdd, width: frame.columns, height: frame.rows)
    }

    /// The runs of columns of pixel row `row` whose coverage `matches`.
    func runs(row: Int, where matches: (Double) -> Bool) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for column in 0...width {
            let inside = column < width && matches(coverage(x: column, y: row))
            if inside, start == nil { start = column }
            if !inside, let begun = start {
                runs.append(begun..<column)
                start = nil
            }
        }
        return runs
    }
}
