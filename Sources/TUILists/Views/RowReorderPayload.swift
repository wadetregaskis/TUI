//  🖥️ TUI — A Terminal UI framework for Swift
//  RowReorderPayload.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// Where inside the grabbed row a reorder drag was pressed, in the row's own
/// cells — the cell a ``RowReorderFeedback/cursor`` drag keeps under the pointer.
///
/// A class because the press-captured mouse closure fills it in on the press and
/// reads it back on the drags that follow: the closure IS the gesture, and it
/// outlives the render that made it.
@MainActor
package final class RowReorderGrabPoint {
    package var x: Int { get { _xCell } set { _xCell = newValue } }

    /// ``x``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _xCell = 0

    package var y: Int { get { _yCell } set { _yCell = newValue } }

    /// ``y``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _yCell = 0

    /// Written out: a class's implicit initializer is internal, and a table in
    /// TUITables makes one per reorder press (module split, step C2).
    package init() {}
}

/// The payload a ``RowReorderFeedback/cursor`` drag carries.
///
/// Not public, and empty on purpose: it exists only to satisfy
/// ``DragAndDropSession``, and no client's `dropDestination` can name — and
/// therefore accept — it, so floating a row over the app can never be mistaken
/// for a drop. The row is placed by the control it belongs to, on release.
/// `package` since step C2 of the module split, so that a table in
/// TUITables can make one; an app still cannot name it.
package struct RowReorderPayload {
    /// Written out: a synthesized one is internal (module split, step C2).
    package init() {}
}
