//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+DrawnPosition.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIView

extension ItemListHandler {
    /// This list's or table's ``DrawnScrollPosition``, the lines scrolled off
    /// its top row included.
    package var drawnPosition: DrawnScrollPosition {
        DrawnScrollPosition(self, subRowLines: scrollTopClipLines)
    }
}
