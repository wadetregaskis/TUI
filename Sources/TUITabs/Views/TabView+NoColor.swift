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
    /// breath is nothing, and under Differentiate Without Colour; and where the chip's
    /// breath draws only its resting colour at the terminal's depth
    /// (`ActiveChipCycle.drawsAsResting(context:)`).
    ///
    /// - Parameters:
    ///   - isFocused: Whether the strip shows the focus.
    ///   - region: The active tab's click region.
    ///   - isFolder: Whether it's a `.bordered` folder tab, whose region starts at its
    ///     top border and has walls outside it. A `.compact` chip's region is just
    ///     the chip, between half-block caps that reversed would light the half
    ///     facing away from the label.
    ///   - chip: The active chip's breath.
    ///   - context: Where the tab view is drawn.
    func reversedForActiveTab(
        isFocused: Bool, region: (x: Int, y: Int, width: Int, height: Int, index: Int)?, isFolder: Bool,
        chip: ActiveChipCycle, context: RenderContext
    ) -> FrameBuffer {
        guard let region else { return self }
        let unseen = isFocused && chip.drawsAsResting(context: context)
        var buffer = self
        if unseen {
            // The chip's breath draws only its resting colour here, and its run, caps
            // and all, would repaint that over the reversal below.
            let rows = region.y..<(region.y + region.height)
            let columns = region.x..<(region.x + region.width)
            buffer.animatedCells.removeAll { run in
                rows.contains(run.offsetY) && columns.overlaps(run.offsetX..<(run.offsetX + run.width))
            }
        }
        return isFolder
            ? buffer.reversedWithoutColor(
                if: isFocused, rows: (region.y + 1)..<(region.y + 2), columns: region.x..<(region.x + region.width),
                focusDrawsAsResting: unseen, context: context)
            : buffer.reversedWithoutColor(
                if: isFocused, rows: region.y..<(region.y + region.height),
                columns: (region.x + 1)..<max(region.x + 1, region.x + region.width - 1), focusDrawsAsResting: unseen,
                context: context)
    }
}
