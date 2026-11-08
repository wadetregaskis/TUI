//  🖥️ TUI — A Terminal UI framework for Swift
//  TabView+NoColor.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension FrameBuffer {
    /// This tab view's buffer with its active tab's label reversed, if the strip holds
    /// the focus, where a control says its state without colour
    /// (`RenderContext.statesWithoutColor`): at ``ColorDepth/noColor``, where the tab's
    /// breath is nothing, and under Differentiate Without Colour.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the strip shows the focus.
    ///   - region: The active tab's click region.
    ///   - isFolder: Whether it's a `.bordered` folder tab, whose region starts at its
    ///     top border and has walls outside it. A `.compact` chip's region is just
    ///     the chip, between half-block caps that reversed would light the half
    ///     facing away from the label.
    ///   - context: Where the tab view is drawn.
    func reversedForActiveTab(
        isFocused: Bool, region: (x: Int, y: Int, width: Int, height: Int, index: Int)?, isFolder: Bool,
        context: RenderContext
    ) -> FrameBuffer {
        guard let region else { return self }
        return isFolder
            ? reversedWithoutColor(
                if: isFocused, rows: (region.y + 1)..<(region.y + 2), columns: region.x..<(region.x + region.width),
                context: context)
            : reversedWithoutColor(
                if: isFocused, rows: region.y..<(region.y + region.height),
                columns: (region.x + 1)..<max(region.x + 1, region.x + region.width - 1), context: context)
    }
}
