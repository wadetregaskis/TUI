//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedZOrder.swift
//
//  The rows a lazy stack draws, drawn in ascending z-index where one of them
//  has a z-index of its own, as the eager stacks draw their children
//  (`RenderContext.zOrderedStackBuffer`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// What a windowed stack's walk appends, kept as layers once a drawn row has a
/// z-index of its own, so the rows can be drawn again in ascending z-index.
///
/// SwiftUI's `.zIndex` orders overlapping views in any container, and a lazy
/// stack's rows overlap wherever an `.offset` or a negative padding moves one
/// onto another. A windowed stack builds its picture by appending each row it
/// draws below (or beside) the last, a later row over an earlier one's
/// overflow, so a raised row went under the next row moved onto it. The eager
/// stacks draw such children in ascending z-index from the places the layout
/// gave them; a windowed stack has no list of places to sort — only the rows it
/// drew, in the order it drew them — so this keeps them as it appends them,
/// and the rows are drawn again in order at the end (``finish(_:context:)``).
///
/// Only the drawn rows are ordered: a row the window leaves out draws nothing
/// over anything.
///
/// Free where no drawn row has a z-index: one load and test per row, and
/// nothing kept. The rows appended before the first raised one are all at the
/// default z-index and already in declaration order, so they are kept as one
/// layer, the picture so far, and only the rows from there on one each.
@MainActor
struct WindowedZOrder {
    /// Whether the rows run across (an `HStack`'s) rather than down.
    private let isRow: Bool
    /// Each layer and where it goes, in drawing order, once a raised row has
    /// been appended; `nil` until then.
    private var layers: [(buffer: FrameBuffer, x: Int, y: Int, zIndex: Double)]?

    /// A record for a stack laying its rows out across (`horizontally`) or down.
    init(horizontally: Bool = false) {
        isRow = horizontally
    }

    /// Appends `slot`, what `child` drew, to `result` with `spacing` before
    /// it, as `appendVertically` (or `appendHorizontally`) does, keeping it as
    /// a layer once any row has a z-index of its own.
    mutating func append(_ slot: FrameBuffer, of child: ChildView, to result: inout FrameBuffer, spacing: Int) {
        if layers == nil, child.zIndex != 0 {
            layers = [(result, 0, 0, 0)]
        }
        if layers != nil {
            // Where the append below puts it: past the picture and the gap,
            // or with no gap where either side draws nothing on that axis.
            let extent = isRow ? result.width : result.height
            let length = isRow ? slot.width : slot.height
            let at = length > 0 && extent > 0 ? extent + spacing : extent
            layers?.append((slot, isRow ? at : 0, isRow ? 0 : at, child.zIndex))
        }
        if isRow {
            result.appendHorizontally(slot, spacing: spacing)
        } else {
            result.appendVertically(slot, spacing: spacing)
        }
    }

    /// `result`, the picture the appends built, or — where a row had a
    /// z-index of its own — its layers drawn again in ascending z-index,
    /// declaration order within one, on a canvas of the same size.
    func finish(_ result: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard let layers else { return result }
        let order = layers.indices.sorted { (layers[$0].zIndex, $0) < (layers[$1].zIndex, $1) }
        return FrameBuffer.layered(
            order.map { (buffer: layers[$0].buffer, x: layers[$0].x, y: layers[$0].y) },
            width: result.width, height: result.height, splitsOverhang: true,
            wakeToken: "stack-base-run-\(context.identity.path)", context: context)
    }
}
