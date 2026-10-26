//  🖥️ TUI — A Terminal UI framework for Swift
//  GridRowProviding.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore
import TUIView

/// A view the enclosing ``Grid`` should treat as a row rather than a cell.
@MainActor
package protocol GridRowProviding {
    /// This row's vertical alignment override, if it set one.
    var rowAlignment: VerticalAlignment? { get }

    /// The row's cells.
    func gridCells(context: RenderContext) -> [ChildView]
}

/// A modified row is still a row, and the modifier belongs to its CELLS.
///
/// SwiftUI: "If you apply a view modifier to a row, the row applies the
/// modifier to all of the cells, similar to how a `Group` behaves. For example,
/// if you apply the `border(_:width:)` modifier to a row, SwiftUI draws a
/// border on each cell in the row rather than around the row."
///
/// A row usually reaches its grid flattened: `GridRow` hands its cells out as a
/// `ChildViewProvider`, and so does a `ModifiedView` around one, re-wrapping
/// each cell. This conformance is for a modified row that arrives WHOLE — a
/// `ForEach` row, which a loop hands over one child per element — which the
/// grid takes apart through it (`wholeGridRow(_:context:)`). Before rows
/// flattened, a wrapped row missed the grid's row test, fell into the "not a
/// `GridRow`, therefore spans every column" branch that exists for a `Divider`
/// between rows, and its cells left the grid's columns.
///
/// The companion to `ModifiedView`'s ``ChildViewProvider`` conformance, and the
/// same shape: resolve through the wrapper, then put the wrapper back around
/// each thing that came out.
extension ModifiedView: GridRowProviding where Content: GridRowProviding {
    package var rowAlignment: VerticalAlignment? { content.rowAlignment }

    package func gridCells(context: RenderContext) -> [ChildView] {
        content.gridCells(context: context).map { $0.modified(by: modifier) }
    }
}

/// The same rule for a row wrapped in something that is not a `BufferModifier`
/// — `.foregroundStyle` and most other modifier factories return a bare
/// wrapper type, not a ``ModifiedView``.
///
/// A ``SingleContentWrapper`` conformance is all a wrapper needs to pick this
/// up; the body here is the one above with ``ChildView/rewrapped(by:)`` in
/// place of ``ChildView/modified(by:)``, for the reason
/// ``SingleContentWrapper`` states: a wrapper has no modifier VALUE to carry
/// to each cell, so it re-wraps them with its own initialiser instead.
extension GridRowProviding where Self: ContentRewrapping, WrappedContent: GridRowProviding {
    package var rowAlignment: VerticalAlignment? { wrappedContent.rowAlignment }

    package func gridCells(context: RenderContext) -> [ChildView] {
        wrappedContent.gridCells(context: context).map { $0.rewrapped(by: self) }
    }
}

// The three environment wrappers live in `TUIView`, which is below this
// module and cannot see `GridRowProviding` — so their conformances are written
// here rather than beside their `ChildViewProvider` ones. Nothing else differs:
// a row carrying `.environment(_:_:)` is as much a row as one carrying
// `.tint(_:)`, and leaving these three out was an artifact of where the files
// sit, not a decision about rows.

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension EnvironmentModifier: GridRowProviding where Content: GridRowProviding {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension TransformEnvironmentModifier: GridRowProviding where Content: GridRowProviding {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension ObjectEnvironmentModifier: GridRowProviding where Content: GridRowProviding {}
