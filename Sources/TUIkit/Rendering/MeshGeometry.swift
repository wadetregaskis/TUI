//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeshGeometry.swift
//
//  Where a mesh gradient's patches lie: every vertex's control points, and
//  each patch's sixteen-point Bézier net.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - The vertices

/// A mesh's vertices with all four control points stated, in `Double`, in the
/// unit space of the box being painted.
///
/// The `points:` form's control points are implied here, by the rule SwiftUI
/// draws with — measured on macOS 15.8 by painting the mesh with colours that
/// encode each pixel's place in it, and fitting the patches that put it there:
///
/// - Along a row (or a column), an inner vertex's two control points lie on
///   one line through it, the one that BISECTS its two edges: the sum of the
///   unit vectors from the vertex before to the vertex, and from the vertex to
///   the one after. Each sits a third of the way to its own neighbour, along
///   that line. A straight row of vertices therefore keeps straight edges, cut
///   in thirds, however unevenly they are spaced — and a moved vertex bends its
///   row smoothly through itself. Fitted on four warped meshes: 0.7–0.9 px
///   residual on a 201 px picture against 2–4 px for straight thirds or
///   Catmull–Rom tangents.
/// - An edge vertex, with one neighbour in that direction, aims its control
///   point straight at it, a third of the way; the control point on the side
///   with no neighbour is the vertex itself, unused.
struct MeshVertices {
    /// One vertex: where it is, and its control points toward each neighbour.
    struct Vertex {
        var position: SIMD2<Double>
        var leading: SIMD2<Double>
        var top: SIMD2<Double>
        var trailing: SIMD2<Double>
        var bottom: SIMD2<Double>
    }

    let width: Int
    let height: Int
    /// Row by row.
    let vertices: [Vertex]

    /// The vertices of `paint`, or `nil` when it draws no patches: fewer than
    /// two vertices in a direction, or a location count other than
    /// `width × height` — SwiftUI's mesh then draws its background alone.
    init?(_ paint: MeshPaint) {
        let (width, height) = (paint.width, paint.height)
        guard width >= 2, height >= 2 else { return nil }
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else { return nil }
        self.width = width
        self.height = height
        switch paint.locations {
        case .bezierPoints(let points):
            guard points.count == count else { return nil }
            vertices = points.map {
                Vertex(
                    position: Self.double($0.position), leading: Self.double($0.leadingControlPoint),
                    top: Self.double($0.topControlPoint), trailing: Self.double($0.trailingControlPoint),
                    bottom: Self.double($0.bottomControlPoint))
            }
        case .points(let points):
            guard points.count == count else { return nil }
            let positions = points.map(Self.double)
            vertices = Self.implied(positions, width: width, height: height)
        }
    }

    private static func double(_ point: SIMD2<Float>) -> SIMD2<Double> {
        SIMD2(Double(point.x), Double(point.y))
    }

    /// Every vertex's control points, implied by its neighbours.
    private static func implied(_ positions: [SIMD2<Double>], width: Int, height: Int) -> [Vertex] {
        var out: [Vertex] = []
        out.reserveCapacity(positions.count)
        for row in 0..<height {
            for column in 0..<width {
                let here = positions[row * width + column]
                let across = controls(
                    before: column > 0 ? positions[row * width + column - 1] : nil, at: here,
                    after: column < width - 1 ? positions[row * width + column + 1] : nil)
                let down = controls(
                    before: row > 0 ? positions[(row - 1) * width + column] : nil, at: here,
                    after: row < height - 1 ? positions[(row + 1) * width + column] : nil)
                out.append(
                    Vertex(
                        position: here, leading: across.before, top: down.before, trailing: across.after,
                        bottom: down.after))
            }
        }
        return out
    }

    /// The control points either side of `point` along one direction of the
    /// grid, by the bisector rule above.
    ///
    /// The degenerate cases fall back to aiming straight at each neighbour:
    /// a neighbour on top of the vertex, or one directly behind the other so
    /// that the two edges' directions cancel. Either way there is no bisector,
    /// and a straight edge is the shape that says least.
    private static func controls(
        before: SIMD2<Double>?, at point: SIMD2<Double>, after: SIMD2<Double>?
    ) -> (before: SIMD2<Double>, after: SIMD2<Double>) {
        func third(toward neighbour: SIMD2<Double>?) -> SIMD2<Double> {
            guard let neighbour else { return point }
            return point + (neighbour - point) / 3
        }
        guard let before, let after else {
            return (third(toward: before), third(toward: after))
        }
        let inward = point - before
        let outward = after - point
        let inLength = length(inward)
        let outLength = length(outward)
        guard inLength > 0, outLength > 0 else {
            return (third(toward: before), third(toward: after))
        }
        let bisector = inward / inLength + outward / outLength
        let bisectorLength = length(bisector)
        guard bisectorLength > 1e-9, bisectorLength.isFinite else {
            return (third(toward: before), third(toward: after))
        }
        let direction = bisector / bisectorLength
        return (point - direction * (inLength / 3), point + direction * (outLength / 3))
    }

    private static func length(_ vector: SIMD2<Double>) -> Double {
        (vector.x * vector.x + vector.y * vector.y).squareRoot()
    }

    subscript(column: Int, row: Int) -> Vertex {
        vertices[row * width + column]
    }

    // MARK: - Patches

    /// The patch between vertices `(column, row)` and `(column + 1, row + 1)`,
    /// as the sixteen control points of a bicubic Bézier patch.
    ///
    /// The twelve on its edges are the vertices and their control points; the
    /// four inside are a COONS patch's — the surface that blends the four edge
    /// curves and nothing else, which is what a mesh vertex has no way to say
    /// anything more than. Fitted against SwiftUI's patches to within the
    /// probe's own noise. The formula is the one PDF's type 6 shading states
    /// for a Coons patch's implicit interior points.
    func net(column: Int, row: Int) -> MeshPatchNet {
        let topLeft = self[column, row]
        let topRight = self[column + 1, row]
        let bottomLeft = self[column, row + 1]
        let bottomRight = self[column + 1, row + 1]
        var net = MeshPatchNet()
        net[0, 0] = MeshPoint(topLeft.position)
        net[1, 0] = MeshPoint(topLeft.trailing)
        net[2, 0] = MeshPoint(topRight.leading)
        net[3, 0] = MeshPoint(topRight.position)
        net[0, 3] = MeshPoint(bottomLeft.position)
        net[1, 3] = MeshPoint(bottomLeft.trailing)
        net[2, 3] = MeshPoint(bottomRight.leading)
        net[3, 3] = MeshPoint(bottomRight.position)
        net[0, 1] = MeshPoint(topLeft.bottom)
        net[0, 2] = MeshPoint(bottomLeft.top)
        net[3, 1] = MeshPoint(topRight.bottom)
        net[3, 2] = MeshPoint(bottomRight.top)
        net.fillCoonsInterior()
        return net
    }

    // MARK: - Shape facts

    /// Whether the patches certainly cover the whole unit square: the edge
    /// vertices lie on its edges in order — the corners at its corners — and so
    /// do their control points along those edges, so the mesh's outline IS the
    /// square's. A mesh that covers it some other way answers `false`, which
    /// costs only the cheaper path.
    var coversUnitSquare: Bool {
        let unit = 0.0...1.0
        // Along the top and bottom rows: on y = 0 and y = 1, edge control points
        // included, the corners at x = 0 and x = 1.
        for column in 0..<width {
            for (row, edge) in [(0, 0.0), (height - 1, 1.0)] {
                let vertex = self[column, row]
                guard vertex.position.y == edge, vertex.leading.y == edge, vertex.trailing.y == edge,
                    unit.contains(vertex.position.x)
                else { return false }
            }
        }
        // Down the leading and trailing columns: on x = 0 and x = 1.
        for row in 0..<height {
            for (column, edge) in [(0, 0.0), (width - 1, 1.0)] {
                let vertex = self[column, row]
                guard vertex.position.x == edge, vertex.top.x == edge, vertex.bottom.x == edge,
                    unit.contains(vertex.position.y)
                else { return false }
            }
        }
        return true
    }

    /// The column and row positions, when every patch is an axis-aligned
    /// rectangle drawn with straight edges cut in thirds — the common mesh,
    /// whose positions form a grid. Such a patch IS its bilinear map, and a
    /// point's place in it is two divisions, with no subdivision at all.
    ///
    /// `nil` unless both lists strictly increase, every vertex sits on its
    /// column's x and its row's y, and every control point is a third of the
    /// way to its neighbour.
    var rectilinear: (columns: [Double], rows: [Double])? {
        let columns = (0..<width).map { self[$0, 0].position.x }
        let rows = (0..<height).map { self[0, $0].position.y }
        guard zip(columns, columns.dropFirst()).allSatisfy({ $0 < $1 }),
            zip(rows, rows.dropFirst()).allSatisfy({ $0 < $1 })
        else { return nil }
        let tolerance = 1e-6
        func near(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Bool {
            abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
        }
        for row in 0..<height {
            for column in 0..<width {
                let vertex = self[column, row]
                let here = SIMD2(columns[column], rows[row])
                guard near(vertex.position, here) else { return nil }
                if column > 0, !near(vertex.leading, here + SIMD2(columns[column - 1] - here.x, 0) / 3) {
                    return nil
                }
                if column < width - 1, !near(vertex.trailing, here + SIMD2(columns[column + 1] - here.x, 0) / 3) {
                    return nil
                }
                if row > 0, !near(vertex.top, here + SIMD2(0, rows[row - 1] - here.y) / 3) { return nil }
                if row < height - 1, !near(vertex.bottom, here + SIMD2(0, rows[row + 1] - here.y) / 3) {
                    return nil
                }
            }
        }
        return (columns, rows)
    }
}
