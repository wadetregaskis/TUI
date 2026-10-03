//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackedChildren.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Members Nothing Laid Out

/// `children` drawn top to bottom, each at the full available width and the
/// height it measures there.
///
/// How a provider of several members draws when nothing above resolved them
/// into siblings of their own — a `ForEach` that is a view's entire `body`, for
/// one. Vertical for the reason `TupleView` stacks that way: it is what an
/// un-laid-out run of sibling views means here.
@MainActor
func renderStackedVertically(_ children: [ChildView], context: RenderContext) -> FrameBuffer {
    let width = context.availableWidth
    return FrameBuffer(
        verticallyStacking: children.map { child in
            let size = child.measure(
                proposal: ProposedSize(width: width, height: nil), context: context)
            return child.render(width: width, height: size.height, context: context)
        })
}

/// The size ``renderStackedVertically(_:context:)`` draws `children` at: the
/// widest of them, and their heights summed.
@MainActor
func measureStackedVertically(
    _ children: [ChildView], proposal: ProposedSize, context: RenderContext
) -> ViewSize {
    var width = 0
    var height = 0
    var widthFlexible = false
    for child in children {
        let size = child.measure(proposal: proposal, context: context)
        width = max(width, size.width)
        height += size.height
        widthFlexible = widthFlexible || size.isWidthFlexible
    }
    return ViewSize(
        width: width, height: height,
        isWidthFlexible: widthFlexible, isHeightFlexible: false)
}
