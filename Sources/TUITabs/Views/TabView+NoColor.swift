//  🖥️ TUI — A Terminal UI framework for Swift
//  TabView+NoColor.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension FrameBuffer {
    /// This tab view's buffer with its active tab's label reversed, if the strip holds
    /// the focus, at ``ColorDepth/noColor``, where the tab's breath is nothing.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the strip shows the focus.
    ///   - region: The active tab's click region.
    ///   - isFolder: Whether it's a `.bordered` folder tab, whose region starts at its
    ///     top border and has walls outside it. A `.compact` chip's region is just
    ///     the chip, between half-block caps that reversed would light the half
    ///     facing away from the label.
    func reversedForActiveTab(
        isFocused: Bool, region: (x: Int, y: Int, width: Int, height: Int, index: Int)?, isFolder: Bool
    ) -> FrameBuffer {
        guard let region else { return self }
        return isFolder
            ? reversedWithoutColor(
                if: isFocused, rows: (region.y + 1)..<(region.y + 2), columns: region.x..<(region.x + region.width))
            : reversedWithoutColor(
                if: isFocused, rows: region.y..<(region.y + region.height),
                columns: (region.x + 1)..<max(region.x + 1, region.x + region.width - 1))
    }
}
