//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeshGradient.swift
//
//  SwiftUI's two-dimensional gradient: a grid of positioned colours, drawn as
//  Bézier patches.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - MeshGradient

/// A two-dimensional gradient defined by a 2D grid of positioned colors.
///
/// Each vertex has a position, a color and four surrounding Bezier control
/// points (leading, top, trailing, bottom) that define the tangents connecting
/// the vertex with its four neighboring vertices. Vertices on the corners or
/// edges of the mesh have fewer than four neighbors, and ignore their extra
/// control points. Control points may be given explicitly
/// (``init(width:height:bezierPoints:colors:background:smoothsColors:colorSpace:)``)
/// or implied by the positions of a vertex's neighbors
/// (``init(width:height:points:colors:background:smoothsColors:colorSpace:)``).
///
/// ```swift
/// MeshGradient(width: 3, height: 3, points: [
///     .init(0, 0), .init(0.5, 0), .init(1, 0),
///     .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
///     .init(0, 1), .init(0.5, 1), .init(1, 1)
/// ], colors: [
///     .red, .purple, .indigo,
///     .orange, .white, .blue,
///     .yellow, .green, .mint
/// ])
/// ```
///
/// Positions are in the unit space of whatever is painted — `(0, 0)` its
/// top-leading corner, `(1, 1)` its bottom-trailing one — as a
/// ``LinearGradient``'s points are, so a mesh stretches with its box and takes
/// no correction for a cell being taller than it is wide.
///
/// ## In a cell grid
///
/// A mesh is a function from a position to a colour, so every cell has an
/// answer: the colour at the cell's centre, which on a glyph terminal draws a
/// smooth mesh as a staircase of cells. Where the terminal draws pictures
/// (`gradientGraphics(_:)`), an opaque mesh used as a view, or behind blank
/// cells, is a picture instead, the mesh's colour at every pixel, as the other
/// gradients are.
///
/// ## Measured against SwiftUI
///
/// Every rule below came off pixels SwiftUI drew on macOS 15.8:
///
/// - **Each patch is a Coons patch**: its four edges are cubic Béziers through
///   the vertices' control points, and its interior blends them.
/// - **An implied control point** lies a third of the way to its neighbour,
///   along the line that bisects the vertex's two edges in that direction — so
///   a moved vertex bends its rows and columns smoothly through it, and a grid
///   of straight rows and columns stays straight. An edge vertex's control
///   point aims straight at its one neighbour.
/// - **Colours** blend bilinearly across a patch when `smoothsColors` is
///   `false`. When it is `true`, each channel follows a cubic through the
///   vertices whose slope at a vertex is the average of its neighbours'
///   differences, flattened at the mesh's edges and at a vertex brighter or
///   darker than both neighbours, and limited so it never overshoots between
///   two vertices.
/// - **`Gradient.ColorSpace.perceptual`** blends in OKLab — and a smooth
///   blend makes its per-channel decisions in OKLab's cube-root cone space,
///   the stage before its final matrix.
/// - **Translucent colours blend premultiplied**: halfway between red and
///   `.clear` is red at half strength, not a darker red.
/// - **`background`** fills whatever the patches do not cover. A mesh with
///   fewer than two vertices in either direction, or a point count other than
///   `width × height`, draws nothing but its background; a vertex with no
///   colour of its own takes `.clear`.
public struct MeshGradient: ShapeStyle, Equatable, Sendable {

    // MARK: - Storage

    /// The number of vertices in each row.
    public var width: Int

    /// The number of vertices in each column.
    public var height: Int

    // `locations` and `colors` are SwiftUI's enums, and are stored here apart
    // from them: a view value holding a payload enum bypasses the per-pass
    // memos (`ValueHashPlan`), and a mesh is exactly the kind of view whose
    // drawing is worth not repeating. Two arrays and a flag each, the unused
    // array empty, are words and bytes the memo can read.

    /// The vertices' positions, for the `points:` form.
    private var storedPoints: [SIMD2<Float>]

    /// The vertices with their control points, for the `bezierPoints:` form.
    private var storedBezierPoints: [BezierPoint]

    /// The colours, for the `colors:` form.
    private var storedColors: [Color]

    /// The colours, for the `resolvedColors:` form.
    private var storedResolvedColors: [Color.Resolved]

    /// The color used to fill the area the mesh does not cover. `.clear` by
    /// default, which leaves whatever is behind showing.
    public var background: Color

    /// Whether the colours between vertices follow cubic curves (`true`) or
    /// blend bilinearly across each patch.
    public var smoothsColors: Bool

    /// The color space the vertex colours are blended in.
    public var colorSpace: Gradient.ColorSpace

    /// Which of `storedPoints` and `storedBezierPoints` is in use.
    private var hasBezierPoints: Bool

    /// Which of `storedColors` and `storedResolvedColors` is in use.
    private var hasResolvedColors: Bool

    // MARK: - SwiftUI's two enums

    /// The vertices: their positions alone, or with their control points.
    public var locations: Locations {
        get { hasBezierPoints ? .bezierPoints(storedBezierPoints) : .points(storedPoints) }
        set {
            switch newValue {
            case .points(let points):
                storedPoints = points
                storedBezierPoints = []
                hasBezierPoints = false
            case .bezierPoints(let points):
                storedPoints = []
                storedBezierPoints = points
                hasBezierPoints = true
            }
        }
    }

    /// The vertices' colours, row by row.
    public var colors: Colors {
        get { hasResolvedColors ? .resolvedColors(storedResolvedColors) : .colors(storedColors) }
        set {
            switch newValue {
            case .colors(let colors):
                storedColors = colors
                storedResolvedColors = []
                hasResolvedColors = false
            case .resolvedColors(let colors):
                storedColors = []
                storedResolvedColors = colors
                hasResolvedColors = true
            }
        }
    }

    /// One location in a gradient mesh, along with the four Bezier control
    /// points surrounding it.
    @frozen
    public struct BezierPoint: Equatable, Sendable {
        /// The position of the vertex.
        public var position: SIMD2<Float>

        /// The Bezier control point of the vertex's leading edge.
        public var leadingControlPoint: SIMD2<Float>

        /// The Bezier control point of the vertex's top edge.
        public var topControlPoint: SIMD2<Float>

        /// The Bezier control point of the vertex's trailing edge.
        public var trailingControlPoint: SIMD2<Float>

        /// The Bezier control point of the vertex's bottom edge.
        public var bottomControlPoint: SIMD2<Float>

        /// Creates a new vertex.
        ///
        /// - Parameters:
        ///   - position: the position of the vertex in the coordinate space
        ///     the gradient is interpreted in.
        ///   - leadingControlPoint: the Bezier control point of the vertex's
        ///     leading edge.
        ///   - topControlPoint: the Bezier control point of the vertex's top
        ///     edge.
        ///   - trailingControlPoint: the Bezier control point of the vertex's
        ///     trailing edge.
        ///   - bottomControlPoint: the Bezier control point of the vertex's
        ///     bottom edge.
        public init(
            position: SIMD2<Float>, leadingControlPoint: SIMD2<Float>, topControlPoint: SIMD2<Float>,
            trailingControlPoint: SIMD2<Float>, bottomControlPoint: SIMD2<Float>
        ) {
            self.position = position
            self.leadingControlPoint = leadingControlPoint
            self.topControlPoint = topControlPoint
            self.trailingControlPoint = trailingControlPoint
            self.bottomControlPoint = bottomControlPoint
        }
    }

    /// An array of 2D locations and their control points.
    public enum Locations: Equatable, Sendable {
        /// Vertices are only specified as their location, their control
        /// points are inferred from the locations of their neighbors.
        case points([SIMD2<Float>])

        /// Vertices explicitly specifying their location and control points.
        case bezierPoints([BezierPoint])
    }

    /// An array of colors.
    public enum Colors: Equatable, Sendable {
        case colors([Color])
        case resolvedColors([Color.Resolved])
    }

    // MARK: - Initialisers

    /// Creates a new gradient mesh from its vertices and their colours.
    ///
    /// - Parameters:
    ///   - width: the number of vertices in each row.
    ///   - height: the number of vertices in each column.
    ///   - locations: the vertices, row by row: `width × height` of them.
    ///   - colors: the vertices' colours, in the same order.
    ///   - background: the color that fills the area the mesh does not cover.
    ///   - smoothsColors: whether the colours between vertices follow cubic
    ///     curves rather than blending bilinearly.
    ///   - colorSpace: the color space the colours are blended in.
    public init(
        width: Int, height: Int, locations: Locations, colors: Colors, background: Color = .clear,
        smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device
    ) {
        self.width = width
        self.height = height
        storedPoints = []
        storedBezierPoints = []
        storedColors = []
        storedResolvedColors = []
        self.background = background
        self.smoothsColors = smoothsColors
        self.colorSpace = colorSpace
        hasBezierPoints = false
        hasResolvedColors = false
        self.locations = locations
        self.colors = colors
    }

    /// Creates a new gradient mesh from vertex positions, each vertex's
    /// control points inferred from its neighbours.
    ///
    /// See ``init(width:height:locations:colors:background:smoothsColors:colorSpace:)``.
    public init(
        width: Int, height: Int, points: [SIMD2<Float>], colors: [Color], background: Color = .clear,
        smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device
    ) {
        self.init(
            width: width, height: height, locations: .points(points), colors: .colors(colors),
            background: background, smoothsColors: smoothsColors, colorSpace: colorSpace)
    }

    /// Creates a new gradient mesh from vertex positions and resolved colours.
    ///
    /// See ``init(width:height:locations:colors:background:smoothsColors:colorSpace:)``.
    public init(
        width: Int, height: Int, points: [SIMD2<Float>], resolvedColors: [Color.Resolved],
        background: Color = .clear, smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device
    ) {
        self.init(
            width: width, height: height, locations: .points(points),
            colors: .resolvedColors(resolvedColors), background: background, smoothsColors: smoothsColors,
            colorSpace: colorSpace)
    }

    /// Creates a new gradient mesh from vertices that state their own
    /// control points.
    ///
    /// See ``init(width:height:locations:colors:background:smoothsColors:colorSpace:)``.
    public init(
        width: Int, height: Int, bezierPoints: [BezierPoint], colors: [Color], background: Color = .clear,
        smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device
    ) {
        self.init(
            width: width, height: height, locations: .bezierPoints(bezierPoints), colors: .colors(colors),
            background: background, smoothsColors: smoothsColors, colorSpace: colorSpace)
    }

    /// Creates a new gradient mesh from vertices that state their own control
    /// points, and resolved colours.
    ///
    /// See ``init(width:height:locations:colors:background:smoothsColors:colorSpace:)``.
    public init(
        width: Int, height: Int, bezierPoints: [BezierPoint], resolvedColors: [Color.Resolved],
        background: Color = .clear, smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device
    ) {
        self.init(
            width: width, height: height, locations: .bezierPoints(bezierPoints),
            colors: .resolvedColors(resolvedColors), background: background, smoothsColors: smoothsColors,
            colorSpace: colorSpace)
    }

    // MARK: - ShapeStyle

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        let palette = environment.palette
        let resolved: [Color] =
            hasResolvedColors
            ? storedResolvedColors.map { Color($0) }
            : storedColors.map { $0.resolve(with: palette) }
        return .mesh(
            MeshPaint(
                width: width, height: height, locations: locations, colors: resolved,
                background: background.resolve(with: palette), smoothsColors: smoothsColors,
                colorSpace: colorSpace))
    }
}
