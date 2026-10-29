//  🖥️ TUI — A Terminal UI framework for Swift
//  TextFrames.swift
//
//  Where each `Text` is drawn: a region over its cells, which rides every
//  shift, clip and memo with them, read back off the finished page by the
//  screen selection, whose highlight keeps to the text it crosses.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension FrameBuffer {
    /// This buffer, a `Text`'s drawing, filed as the text's frame
    /// (``HitTestRegion/HandlerID/textFrame``): its whole rectangle, the
    /// widest line by every row.
    ///
    /// The rectangle, not each line's own run: a wrapped paragraph's
    /// highlight is then a block to the text's trailing edge, as a Mac's text
    /// view draws a selection across a wrapped line, rather than a ragged
    /// edge that stops at each line's last letter — and it is one region a
    /// text, where per line it was one a line. A centred or trailing line's
    /// leading blanks are the text's own, inside its frame, as they are in
    /// SwiftUI's.
    ///
    /// One region, carried in the buffer: no handler, no journal entry, so a
    /// text served from a memo — a list's row, a value memo's subtree —
    /// carries its frame as it carries its cells, at no cost a frame beyond
    /// the region (the bordered box's interior is filed the same way). Nothing
    /// while measuring, for a buffer that draws nothing, or while no selection
    /// is being made or shown (``EnvironmentValues/filesTextFrames``): filed
    /// on every frame, the regions cost a text-heavy page 3–7% a frame and
    /// `fanout` 8.6 MB more (Stress A/B, 2026-10-28), for a highlight that
    /// is drawn only while there is a selection.
    package consuming func filingTextFrame(context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring, width > 0, height > 0, context.environment.filesTextFrames
        else { return self }
        var buffer = self
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height, handlerID: .textFrame))
        return buffer
    }
}

extension Array where Element == HitTestRegion {
    /// The rectangles of the text frames among these regions
    /// (``HitTestRegion/HandlerID/textFrame``), in the regions' coordinates.
    package var textFrames: [CellRect] {
        var rects: [CellRect] = []
        for region in self where region.isTextFrame {
            rects.append(CellRect(x: region.offsetX, y: region.offsetY, width: region.width, height: region.height))
        }
        return rects
    }
}
