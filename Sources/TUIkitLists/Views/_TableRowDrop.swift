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
struct _TableRowDrop {
    /// Whether a drag carrying this payload can land on the row.
    let accepts: (Any) -> Bool
    /// Performs the drop with the payloads it accepts.
    let perform: ([Any]) -> Void
}
