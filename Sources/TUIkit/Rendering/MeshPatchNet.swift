//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeshPatchNet.swift
//
//  One patch of a mesh gradient as the sixteen control points of a bicubic
//  Bézier patch, and the arithmetic that splits and measures one.
//
//  Created by Wade Tregaskis
//  License: MIT

// The types here are plain structs of `Double`s with operators of their own,
// not `SIMD2`/`SIMD16`, and that is the point of them. SIMD's arithmetic is
// generic over its scalar, and an unoptimised build calls it through the
// protocol for every lane: a warped mesh 80 cells wide took 51 ms to place
// in a debug build when its nets were two `SIMD16<Double>`s, most of it in
// subscripts and lane-wise operators. These compile to direct calls there and
// to the same code as SIMD's in an optimised build.

/// A point in a mesh's plane: unit space, or a raster's sample space.
struct MeshPoint: Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: SIMD2<Double>) {
        self.init(point.x, point.y)
    }

    static func + (lhs: Self, rhs: Self) -> Self { Self(lhs.x + rhs.x, lhs.y + rhs.y) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(lhs.x - rhs.x, lhs.y - rhs.y) }
    static func * (lhs: Self, rhs: Double) -> Self { Self(lhs.x * rhs, lhs.y * rhs) }
    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }

    /// The midpoint of two points — de Casteljau's whole step at a half.
    static func midpoint(_ lhs: Self, _ rhs: Self) -> Self {
        Self((lhs.x + rhs.x) * 0.5, (lhs.y + rhs.y) * 0.5)
    }

    /// How far apart two points are.
    func distance(to other: Self) -> Double {
        let (dx, dy) = (other.x - x, other.y - y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The z of the cross product of two vectors in the plane.
    static func cross(_ lhs: Self, _ rhs: Self) -> Double { lhs.x * rhs.y - lhs.y * rhs.x }
}

/// One cubic Bézier curve: a row or a column of a patch's net.
struct MeshCubic {
    var p0: MeshPoint
    var p1: MeshPoint
    var p2: MeshPoint
    var p3: MeshPoint

    /// The two halves either side of the curve's middle, by de Casteljau.
    func halves() -> (Self, Self) {
        let p01 = MeshPoint.midpoint(p0, p1)
        let p12 = MeshPoint.midpoint(p1, p2)
        let p23 = MeshPoint.midpoint(p2, p3)
        let p012 = MeshPoint.midpoint(p01, p12)
        let p123 = MeshPoint.midpoint(p12, p23)
        let middle = MeshPoint.midpoint(p012, p123)
        return (Self(p0: p0, p1: p01, p2: p012, p3: middle), Self(p0: middle, p1: p123, p2: p23, p3: p3))
    }

    /// How far its inner control points stray from where a straight line
    /// would put them — zero for a line cut in thirds, which is the curve that
    /// IS its chord.
    var bend: Double {
        let third = p0 + (p3 - p0) * (1.0 / 3)
        let twoThirds = p0 + (p3 - p0) * (2.0 / 3)
        return max(p1.distance(to: third), p2.distance(to: twoThirds))
    }
}

/// The sixteen control points of a bicubic Bézier patch, `[i, j]` with `i`
/// along the patch's `u` (its columns) and `j` along `v` (its rows): four rows,
/// each a cubic along `u`.
struct MeshPatchNet {
    var row0: MeshCubic
    var row1: MeshCubic
    var row2: MeshCubic
    var row3: MeshCubic

    /// A net with every point at the origin, to be filled in.
    init() {
        let zero = MeshCubic(p0: MeshPoint(0, 0), p1: MeshPoint(0, 0), p2: MeshPoint(0, 0), p3: MeshPoint(0, 0))
        (row0, row1, row2, row3) = (zero, zero, zero, zero)
    }

    private init(rows: (MeshCubic, MeshCubic, MeshCubic, MeshCubic)) {
        (row0, row1, row2, row3) = rows
    }

    subscript(i: Int, j: Int) -> MeshPoint {
        get {
            let row = j == 0 ? row0 : j == 1 ? row1 : j == 2 ? row2 : row3
            return i == 0 ? row.p0 : i == 1 ? row.p1 : i == 2 ? row.p2 : row.p3
        }
        set {
            func set(_ row: inout MeshCubic) {
                switch i {
                case 0: row.p0 = newValue
                case 1: row.p1 = newValue
                case 2: row.p2 = newValue
                default: row.p3 = newValue
                }
            }
            switch j {
            case 0: set(&row0)
            case 1: set(&row1)
            case 2: set(&row2)
            default: set(&row3)
            }
        }
    }

    /// Column `i`: the cubic along `v`.
    private func column(_ i: Int) -> MeshCubic {
        MeshCubic(p0: self[i, 0], p1: self[i, 1], p2: self[i, 2], p3: self[i, 3])
    }

    /// A net made of four columns, the transpose of the rows above.
    private init(columns: (MeshCubic, MeshCubic, MeshCubic, MeshCubic)) {
        let (c0, c1, c2, c3) = columns
        self.init(
            rows: (
                MeshCubic(p0: c0.p0, p1: c1.p0, p2: c2.p0, p3: c3.p0),
                MeshCubic(p0: c0.p1, p1: c1.p1, p2: c2.p1, p3: c3.p1),
                MeshCubic(p0: c0.p2, p1: c1.p2, p2: c2.p2, p3: c3.p2),
                MeshCubic(p0: c0.p3, p1: c1.p3, p2: c2.p3, p3: c3.p3)
            ))
    }

    /// The four interior points of the Coons patch the twelve edge points
    /// describe: the formula PDF's type 6 shading states for a Coons patch's
    /// implicit interior points.
    mutating func fillCoonsInterior() {
        func blend(_ terms: [(Double, Int, Int)]) -> MeshPoint {
            var sum = MeshPoint(0, 0)
            for (weight, i, j) in terms { sum += self[i, j] * weight }
            return sum * (1.0 / 9)
        }
        self[1, 1] = blend([
            (-4, 0, 0), (6, 0, 1), (6, 1, 0), (-2, 0, 3), (-2, 3, 0), (3, 3, 1), (3, 1, 3), (-1, 3, 3),
        ])
        self[1, 2] = blend([
            (-4, 0, 3), (6, 0, 2), (6, 1, 3), (-2, 0, 0), (-2, 3, 3), (3, 3, 2), (3, 1, 0), (-1, 3, 0),
        ])
        self[2, 1] = blend([
            (-4, 3, 0), (6, 3, 1), (6, 2, 0), (-2, 3, 3), (-2, 0, 0), (3, 0, 1), (3, 2, 3), (-1, 0, 3),
        ])
        self[2, 2] = blend([
            (-4, 3, 3), (6, 3, 2), (6, 2, 3), (-2, 3, 0), (-2, 0, 3), (3, 0, 2), (3, 2, 0), (-1, 0, 0),
        ])
    }

    /// This net moved into another space: `point × scale − offset`, per axis.
    func mapped(scale: SIMD2<Double>, offset: SIMD2<Double>) -> Self {
        func map(_ cubic: MeshCubic) -> MeshCubic {
            func map(_ point: MeshPoint) -> MeshPoint {
                MeshPoint(point.x * scale.x - offset.x, point.y * scale.y - offset.y)
            }
            return MeshCubic(p0: map(cubic.p0), p1: map(cubic.p1), p2: map(cubic.p2), p3: map(cubic.p3))
        }
        return Self(rows: (map(row0), map(row1), map(row2), map(row3)))
    }

    /// The two halves either side of `u = ½`.
    func splitU() -> (Self, Self) {
        let (first, second, third, fourth) = (row0.halves(), row1.halves(), row2.halves(), row3.halves())
        return (
            Self(rows: (first.0, second.0, third.0, fourth.0)), Self(rows: (first.1, second.1, third.1, fourth.1))
        )
    }

    /// The two halves either side of `v = ½`.
    func splitV() -> (Self, Self) {
        let (first, second, third, fourth) = (
            column(0).halves(), column(1).halves(), column(2).halves(), column(3).halves()
        )
        return (
            Self(columns: (first.0, second.0, third.0, fourth.0)),
            Self(columns: (first.1, second.1, third.1, fourth.1))
        )
    }

    /// The box holding every control point — and so, a Bézier patch lying
    /// inside its net, the patch. `nil` if any point is not finite.
    var bounds: (low: MeshPoint, high: MeshPoint)? {
        var low = MeshPoint(.infinity, .infinity)
        var high = MeshPoint(-.infinity, -.infinity)
        for j in 0..<4 {
            for i in 0..<4 {
                let point = self[i, j]
                guard point.x.isFinite, point.y.isFinite else { return nil }
                low = MeshPoint(min(low.x, point.x), min(low.y, point.y))
                high = MeshPoint(max(high.x, point.x), max(high.y, point.y))
            }
        }
        return (low, high)
    }

    /// The furthest any control point lies from where the bilinear map of the
    /// four corners would put it. Zero for an axis-aligned rectangle with
    /// straight edges cut in thirds — the grid's patches — and a quarter as
    /// much for each half of a curved patch, so splitting gets there fast.
    var deviation: Double {
        var worst = 0.0
        for j in 0..<4 {
            for i in 0..<4 where !((i == 0 || i == 3) && (j == 0 || j == 3)) {
                let (s, t) = (Double(i) / 3, Double(j) / 3)
                let bilinear =
                    self[0, 0] * ((1 - s) * (1 - t)) + self[3, 0] * (s * (1 - t)) + self[0, 3] * ((1 - s) * t)
                    + self[3, 3] * (s * t)
                worst = max(worst, self[i, j].distance(to: bilinear))
            }
        }
        return worst
    }

    /// Whether the rows bend more than the columns — which way to split a net
    /// that is not yet flat, since halving across a bend does not straighten it.
    var bendsMoreAlongU: Bool {
        let rows = max(max(row0.bend, row1.bend), max(row2.bend, row3.bend))
        let columns = max(max(column(0).bend, column(1).bend), max(column(2).bend, column(3).bend))
        return rows >= columns
    }

    /// The longer of the net's two sides, along `u` (top and bottom rows) and
    /// along `v` (leading and trailing columns), corner to corner.
    var span: (u: Double, v: Double) {
        (
            max(row0.p0.distance(to: row0.p3), row3.p0.distance(to: row3.p3)),
            max(row0.p0.distance(to: row3.p0), row0.p3.distance(to: row3.p3))
        )
    }
}
