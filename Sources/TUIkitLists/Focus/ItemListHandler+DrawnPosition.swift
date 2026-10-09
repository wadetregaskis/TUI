//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+DrawnPosition.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation
import TUIkitView

extension ItemListHandler {
    /// This list's or table's ``DrawnScrollPosition``, the lines scrolled off
    /// its top row included.
    var drawnPosition: DrawnScrollPosition {
        DrawnScrollPosition(self, subRowLines: scrollTopClipLines)
    }
}
