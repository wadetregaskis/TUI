//  🖥️ TUI — A Terminal UI framework for Swift
//  CellPoint.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A position in whole terminal cells — the counterpart of `CGPoint`, beside
/// ``CellSize`` and ``CellRect``, for geometry: an anchor, a scroll position.
///
/// The pointer is the exception: a gesture or a hover reports a `CGPoint`, as
/// SwiftUI's does, measured in cells, because a terminal may report the pointer
/// within a cell. ``init(_:)`` is the cell such a location falls in.
public struct CellPoint: Hashable, Sendable {
    /// The column, in cells from the coordinate space's origin.
    public var x: Int

    /// The row, in rows from the coordinate space's origin.
    public var y: Int

    /// Creates a position in whole cells.
    ///
    /// - Parameters:
    ///   - x: The column.
    ///   - y: The row.
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// The cell a pointer location falls in: the whole cells before it, so a
    /// location 2.75 cells along is in column 2.
    ///
    /// Not `Int(_:)` of each coordinate, which rounds toward zero, putting the
    /// quarter-cell either side of a view's edge in the same column. A location
    /// that is not a number is in cell 0, rather than a trap.
    ///
    /// - Parameter location: A location from a gesture or a hover, in cells.
    public init(_ location: CGPoint) {
        self.init(x: Self.wholeCells(before: location.x), y: Self.wholeCells(before: location.y))
    }

    /// The whole number of cells before `coordinate`, within what an `Int` holds.
    private static func wholeCells(before coordinate: CGFloat) -> Int {
        guard coordinate.isFinite else { return 0 }
        return Int(max(-1e15, min(1e15, coordinate.rounded(.down))))
    }

    /// The origin, `(0, 0)`.
    public static let zero = Self(x: 0, y: 0)
}

extension CGFloat {
    /// The nearest whole number of cells, within what an `Int` holds, and none
    /// for what is not a number: how a distance in SwiftUI's type becomes the
    /// cells a view can move by.
    var nearestCell: Int {
        guard isFinite else { return 0 }
        return Int(Swift.max(-1e15, Swift.min(1e15, rounded())))
    }
}

extension CellSize {
    /// A drag's translation to the nearest whole cell in each direction: the
    /// distance a view that moves by cells moves.
    ///
    /// - Parameter size: A translation or a velocity, in cells.
    public init(_ size: CGSize) {
        self.init(width: size.width.nearestCell, height: size.height.nearestCell)
    }
}

extension CGPoint {
    /// The location at the top-left corner of `cell`, which is where a terminal
    /// that reports whole cells says the pointer is.
    init(_ cell: CellPoint) {
        self.init(x: Double(cell.x), y: Double(cell.y))
    }
}
