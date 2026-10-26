//  🖥️ TUI — A Terminal UI framework for Swift
//  MeshPaint.swift
//
//  A mesh gradient, resolved: what `Paint.mesh` carries.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

// MARK: - MeshPaint

/// A ``MeshGradient`` with its colours resolved against the palette —
/// everything the renderer needs to answer "what colour is this cell?" for a
/// mesh.
///
/// The vertices keep the form they were given in: positions alone, or with
/// their control points. The implied control points are worked out where the
/// mesh is drawn, so a mesh that moves inside `withAnimation` moves its
/// vertices and lets the curves through them follow, as the vertices'
/// neighbours imply them at each step.
public struct MeshPaint: Equatable, Sendable {
    /// The number of vertices in each row.
    public var width: Int

    /// The number of vertices in each column.
    public var height: Int

    /// The vertices, row by row.
    public var locations: MeshGradient.Locations

    /// The vertices' colours, row by row, resolved — concrete wherever the
    /// palette could make them so.
    public var colors: [Color]

    /// What fills the area the patches do not cover.
    public var background: Color

    /// Whether colours follow cubic curves between vertices rather than
    /// blending bilinearly across each patch.
    public var smoothsColors: Bool

    /// The space colours blend in.
    public var colorSpace: Gradient.ColorSpace

    /// The size to resolve over, from ``ShapeStyle/in(_:)``, as
    /// ``GradientPaint/extent`` is; `nil` is whatever is being painted.
    public var extent: CellSize?

    /// Creates a mesh paint.
    public init(
        width: Int, height: Int, locations: MeshGradient.Locations, colors: [Color], background: Color,
        smoothsColors: Bool, colorSpace: Gradient.ColorSpace, extent: CellSize? = nil
    ) {
        self.width = width
        self.height = height
        self.locations = locations
        self.colors = colors
        self.background = background
        self.smoothsColors = smoothsColors
        self.colorSpace = colorSpace
        self.extent = extent
    }
}

extension MeshPaint {
    /// The one colour that stands in for this mesh where a gradient cannot go:
    /// the colour at its middle — halfway along its rows and its columns, which
    /// for an odd number of each is the middle vertex. A mesh that draws
    /// nothing stands in as its background, which is all it draws.
    ///
    /// The mesh's counterpart of `Gradient.representative`, the colour at
    /// `0.5`, and for the same reason: an end is not a summary.
    public var representative: Color {
        guard MeshVertices(self) != nil else { return background }
        let column = Double(width - 1) / 2
        let row = Double(height - 1) / 2
        let patchColumn = min(Int(column), width - 2)
        let patchRow = min(Int(row), height - 2)
        return MeshColourField(self).colour(
            column: patchColumn, row: patchRow, across: column - Double(patchColumn), down: row - Double(patchRow))
    }

    /// Whether every cell this mesh paints is opaque.
    ///
    /// Every vertex has to be, and so does the background unless the patches
    /// cover the whole box. That last is decided conservatively — the edge
    /// vertices on the box's edges, in order, with their edge control points on
    /// those edges too, which is what the common mesh is — so a mesh that
    /// covers the box some other way (points past its edges) is treated as
    /// letting its background through: it draws the same, through the
    /// translucency path, which costs more and states nothing.
    public var isOpaqueThroughout: Bool {
        guard let vertices = MeshVertices(self) else { return background.isOpaque }
        let count = width * height
        guard colors.count >= count, colors.prefix(count).allSatisfy(\.isOpaque) else { return false }
        return background.isOpaque || vertices.coversUnitSquare
    }
}
