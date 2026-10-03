//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CellPoint.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// A position in whole terminal cells — the counterpart of `CGPoint`, beside
/// ``CellSize`` and ``CellRect``.
///
/// Where SwiftUI hands an action a `CGPoint` — the pointer under
/// ``View/onContinuousHover(coordinateSpace:perform:)``, a tap under
/// ``View/onTapGesture(count:coordinateSpace:perform:)`` — TUIkit hands it the
/// cell, because that is all a terminal reports (see
/// `Documentation/SwiftUI-compatibility.md` §2.2).
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

    /// The origin, `(0, 0)`.
    public static let zero = Self(x: 0, y: 0)
}
