//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackColumnAssembly.swift
//
//  An eager column's last pass: its children, rendered at the rows the
//  distribution gave them, placed down the column. Moved out of `VStack.swift`,
//  which had reached the file-length ceiling.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _VStackCore {
    /// `renderClip`'s PASS 3: `children`, drawn as `buffers` (`nil` for a
    /// spacer, `heights` its rows), placed down the column and across it by
    /// `guideRun` or the alignment within `alignmentWidth`, then clamped to
    /// the space the column was given.
    func assembleColumn(
        _ children: [ChildView], buffers: [FrameBuffer?], heights finalHeights: [Int],
        alignmentWidth: Int, guideRun: AlignmentGuideRun?, context: RenderContext
    ) -> FrameBuffer {
        // Empty children (e.g. `if false { ChildView() }`, which
        // ViewBuilder lowers to `Optional<ChildView>.none`, and
        // `EmptyView()`) are filtered from layout entirely: they
        // contribute no height, and FrameBuffer.appendVertically
        // drops the spacing slot they would otherwise have claimed.
        // This matches SwiftUI's VStack semantics — a non-rendering
        // child is treated as if it weren't in the children list at
        // all. To reserve a row regardless, opt in with a sized
        // placeholder (Color.clear.frame(height: 1), Spacer with an
        // explicit height, etc.) — note that EmptyView() in an else
        // branch will also be filtered.
        var result = FrameBuffer()
        for (index, child) in children.enumerated() {
            let spacingToApply = index > 0 ? spacing : 0
            if child.isSpacer {
                result.appendVertically(
                    FrameBuffer(emptyWithHeight: finalHeights[index]), spacing: spacingToApply)
            } else if let buffer = buffers[index] {
                let alignedBuffer =
                    guideRun.map {
                        buffer.placedHorizontallyDrawingOverhang(
                            inWidth: min($0.extent, max(0, context.availableWidth)), offset: $0.offsets[index],
                            isMeasuring: context.isMeasuring)
                    } ?? buffer.horizontallyAligned(toWidth: alignmentWidth, alignment: alignment)
                result.appendVertically(alignedBuffer, spacing: spacingToApply)
            }
        }

        // Final guard against overflow on a terminal smaller than the content.
        return result.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }
}
