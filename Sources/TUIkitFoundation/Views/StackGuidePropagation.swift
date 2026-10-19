//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackGuidePropagation.swift
//
//  An explicit alignment guide travels up through the views that place a child
//  at a known offset — a column, and padding — as SwiftUI's does. `HStack` and
//  `ZStack` answer the same question in their own files, beside the layout
//  they reuse.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - VStack

extension VStack {
    /// Its content's answer: the column lays its content out as its own
    /// children, so a guide in any of them can be the column's to report.
    public static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

extension _VStackCore {
    /// See ``VStack/_providesAlignmentGuide``.
    package static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

extension _VStackCore: AlignmentGuideQuerying {
    /// The guide the column's children give, each moved by where the column
    /// puts it, merged by the guide's rule: SwiftUI's measured behaviour — a
    /// custom guide or a text baseline inside a `VStack` inside a `VStack`
    /// aligned on it moves the inner column as a whole. An edge or centre
    /// guide does that only out of a column that is statically one view
    /// (``AlignmentGuideQuery/staysInside(contentOf:)``); a column of several
    /// places them by it and keeps it.
    ///
    /// The placement is `renderClip`'s, predicted from measures as its ramp
    /// placement is: heights distributed over `dimensions.height`, each row
    /// measured at the width it is drawn at, then the row's own guide run or
    /// the column's alignment across. A lazy column answers nothing: it draws
    /// only the rows in its window, and a guide must not move as rows scroll.
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        guard overflow == .clip, !query.staysInside(contentOf: Content.self) else { return nil }
        let context = context.publishingContainerAxis(.vertical, passesNoWidthOn: isStaticallyOneView(Content.self))
        let children = stackChildren(of: content, context: context).laidOut
        guard anyAlignmentGuide(in: children) else { return nil }

        var naturalHeights: [Int] = []
        var isFlexible: [Bool] = []
        var fillsWidth = false
        for child in children {
            if child.isSpacer {
                naturalHeights.append(child.spacerLength(along: .vertical))
                isFlexible.append(true)
            } else {
                let size = child.measure(proposal: .unspecified, context: context)
                naturalHeights.append(size.height)
                isFlexible.append(size.isHeightFlexible)
                if size.isWidthFlexible { fillsWidth = true }
            }
        }
        // As the render distributes them, priorities included.
        let priorities = layoutPriorities(of: children)
        let heights = distributeLinearSpace(
            naturalSizes: naturalHeights, isFlexible: isFlexible,
            available: dimensions.height, spacing: spacing, shares: false, isSpacer: { children[$0].isSpacer },
            priorities: priorities,
            minimumSize: { minimumLength(of: children[$0], horizontally: false, across: nil, context: context) },
            statedMinimum: { statedMinimumLength(of: children[$0], horizontally: false) },
            sizeAt: { index, offer in
                children[index].measure(proposal: ProposedSize(width: nil, height: offer), context: context).height
            })
        let sizes = children.indices.map { index -> (width: Int, height: Int) in
            guard !children[index].isSpacer else { return (width: 0, height: 0) }
            let size = children[index].measure(
                proposal: ProposedSize(width: dimensions.width, height: heights[index]),
                context: context)
            return (width: min(size.width, dimensions.width), height: heights[index])
        }
        let widest = sizes.map(\.width).max() ?? 0
        // Placed as the column draws them: a guide past its trailing edge stays
        // on the line (`holdsChildrenInside: false`), and is reported from there.
        let run = horizontalGuideRun(
            children, sizes: sizes, alignment: alignment,
            fixedExtent: fillsWidth ? dimensions.width : nil, minimumExtent: widest,
            holdsChildrenInside: false, context: context)
        let alignmentWidth = fillsWidth ? dimensions.width : widest
        var frames: [(x: Int, y: Int, width: Int, height: Int)] = []
        frames.reserveCapacity(children.count)
        var y = 0
        for (index, size) in sizes.enumerated() {
            let x =
                run?.offsets[index]
                ?? alignment.childOffset(childWidth: size.width, in: alignmentWidth)
            frames.append((x: x, y: y, width: size.width, height: size.height))
            // A row of no lines earns no gap — `gradientOffsets`' rule.
            y += heights[index] + (heights[index] > 0 ? spacing : 0)
        }
        return mergedExplicitGuide(query, of: children, frames: frames, context: context)
    }
}

// MARK: - Padding

extension PaddingModifier {
    /// Padding lays its content out at a fixed inset, so a guide inside it is
    /// the padded view's, moved by that inset — measured in SwiftUI with
    /// `.padding(0)` between a guide and the stack that aligns on it.
    public static var _translatesAlignmentGuides: Bool { true }

    /// Padding lays its content out anew, at the size it is offered less the
    /// insets, so a priority written inside it is lost, as SwiftUI loses it
    /// under `.padding(0)` (`Tools/SwiftUIProbes/Layout priority/priority.out`).
    public static var _changesLayout: Bool { true }
}

extension ModifiedView: AlignmentGuideQuerying {
    /// Padded, the content's guide, laid out at the padded view's size less
    /// the insets, moved by the leading and top insets. Under a modifier that
    /// keeps its content where it is (``BufferModifier/_keepsContentGeometry``),
    /// the content's guide unmoved, in the context the modifier hands its
    /// content (an `.id` splices its key into the identity there).
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        guard let modifier = modifier as? PaddingModifier else {
            guard Modifier._keepsContentGeometry else { return nil }
            return TUIkitFoundation.explicitGuide(
                of: content, query, in: dimensions, context: self.modifier.adjustContext(context))
        }
        let insets = modifier.insets
        var contentContext = context
        contentContext.availableWidth = max(0, dimensions.width - insets.leading - insets.trailing)
        contentContext.availableHeight = max(0, dimensions.height - insets.top - insets.bottom)
        let contentDimensions = ViewDimensions(
            width: contentContext.availableWidth, height: contentContext.availableHeight)
        return TUIkitFoundation.explicitGuide(
            of: content, query, in: contentDimensions, context: contentContext
        ).map { query.translated($0, by: (x: insets.leading, y: insets.top)) }
    }
}
