//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _TableRowDrop.swift
//
//  The drop a table row takes onto itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - What a row carries

/// A drop a row takes onto itself, from a `.dropDestination(for:action:)` on
/// row content.
package struct _TableRowDrop {
    /// Whether a drag carrying this payload can land on the row.
    package let accepts: (Any) -> Bool
    /// Performs the drop with the payloads it accepts.
    package let perform: ([Any]) -> Void

    /// The memberwise initializer, written out: a synthesized one is internal,
    /// and a table in TUIkitTables makes these (module split, step C2), and a
    /// tab's drop destination in TUIkitTabs (step C3).
    package init(accepts: @escaping (Any) -> Bool, perform: @escaping ([Any]) -> Void) {
        self.accepts = accepts
        self.perform = perform
    }
}
