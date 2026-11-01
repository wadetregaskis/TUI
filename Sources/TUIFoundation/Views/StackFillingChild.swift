//  🖥️ TUI — A Terminal UI framework for Swift
//  StackFillingChild.swift
//
//  An eager column's first pass, which measures each child's natural size —
//  except a child whose type fills whatever it is offered (a scroll view,
//  `View._fillsItsOffer`), when it is the column's one filling child. The deal
//  gives such a child what the others leave whatever it would say, and its
//  measure is a walk of all its content: under a heading, a scroll view of
//  300 changing rows paid a whole extra pass over them on every frame.
//
//  Created by Wade Tregaskis
//  License: MIT

@MainActor extension _VStackCore {
    /// Every child's natural size, as `.clip` render's first pass needs it.
    ///
    /// A filling child is answered at the available width and no height,
    /// unmeasured, where ``naturalSizeNeeded(of:sizes:spacing:context:)``
    /// says the deal will not read it; otherwise it is measured like the rest.
    func naturalSizes(of children: [ChildView], context: RenderContext) -> [ViewSize] {
        var sizes: [ViewSize] = []
        sizes.reserveCapacity(children.count)
        var deferred = false
        for child in children {
            if child.fillsItsOffer, !child.isSpacer {
                deferred = true
                sizes.append(
                    ViewSize(width: context.availableWidth, height: 0, isWidthFlexible: true, isHeightFlexible: true))
            } else {
                sizes.append(child.measure(proposal: .unspecified, context: context))
            }
        }
        guard deferred, Self.naturalSizeNeeded(of: children, sizes: sizes, spacing: spacing, context: context)
        else { return sizes }
        for (index, child) in children.enumerated() where child.fillsItsOffer && !child.isSpacer {
            sizes[index] = child.measure(proposal: .unspecified, context: context)
        }
        return sizes
    }

    /// Whether a filling child left unmeasured must be measured after all:
    /// unless it is the column's ONE child that fills, no child states a
    /// layout priority, and the others and the gaps fit, the deal
    /// (`distributeInOrder`) reads its natural height. With all three it
    /// gives it the height the others leave, whatever that natural height is.
    static func naturalSizeNeeded(
        of children: [ChildView], sizes: [ViewSize], spacing: Int, context: RenderContext
    ) -> Bool {
        var filling = 0
        var fixed = 0
        var occupying = 0
        for (index, child) in children.enumerated() {
            if child.isSpacer || sizes[index].isHeightFlexible {
                filling += 1
                occupying += 1
            } else {
                fixed += max(0, sizes[index].height)
                if sizes[index].height > 0 { occupying += 1 }
            }
        }
        // A priority on any child deals by levels, which may read it.
        guard filling == 1, layoutPriorities(of: children) == nil else { return true }
        return fixed + totalLinearSpacing(occupiedChildren: occupying, spacing: max(0, spacing))
            > context.availableHeight
    }

    /// The height each child is dealt out of `available`: what `.clip` render draws
    /// it in.
    func dealtHeights(
        of children: [ChildView], naturalHeight: [Int], isFlexible: [Bool], available: Int, context: RenderContext
    ) -> [Int] {
        let priorities = layoutPriorities(of: children)
        // With room for every child, none is offered less than its natural
        // height (``fitsAtNaturalHeights(_:isFlexible:spacing:available:)``).
        let fits = fitsAtNaturalHeights(naturalHeight, isFlexible: isFlexible, spacing: spacing, available: available)
        return distributeLinearSpace(
            naturalSizes: naturalHeight,
            isFlexible: isFlexible,
            available: available,
            spacing: spacing,
            isSpacer: { children[$0].isSpacer },
            priorities: priorities,
            minimumSize: {
                fits ? naturalHeight[$0] : minimumLength(of: children[$0], horizontally: false, across: nil, context: context)
            },
            statedMinimum: { statedMinimumLength(of: children[$0], horizontally: false) },
            sizeAt: { index, offer in
                children[index].measure(proposal: ProposedSize(width: nil, height: offer), context: context).height
            }
        )
    }

    /// Every child's size for a column whose rows pass `limit`, the `squeezable` ones
    /// measured again in the share of it the render deals them.
    ///
    /// Measured against the whole height, a child that gives way answers for a layout
    /// nobody draws: a scroll view whose rows fit the column's height but not what a
    /// header leaves them answers no column for a bar, and a parent that draws the
    /// column at its measured width (a `TabView`) squeezed the rows by the bar it then
    /// drew. SwiftUI's stack proposes a flexible child its share. Only here, where
    /// the column overflows and such a child's width can move, because a measure is a
    /// walk of the child's content: a child that fits, or that fills a width it was
    /// offered, is not asked twice.
    ///
    /// Only a scroll view (``View/_fillsItsOffer``), not every child that gives way: a
    /// column in a column asked twice at every level is 2^depth walks of what is inside
    /// (1.8 million at twenty levels, `ColumnShareMeasureTests`). So a column between
    /// this one and the scroll view is still measured in the whole height, and the
    /// scroll view a row short of fitting under two headers can still lose a column.
    func widthsInShares(
        of children: [ChildView], squeezable: [(index: Int, size: ViewSize)], proposal: ProposedSize, limit: Int,
        context: RenderContext
    ) -> [ViewSize] {
        var sizes: [ViewSize] = []
        sizes.reserveCapacity(children.count)
        var next = squeezable.startIndex
        for (index, child) in children.enumerated() {
            if next < squeezable.endIndex, squeezable[next].index == index {
                sizes.append(squeezable[next].size)
                next += 1
            } else {
                sizes.append(child.measure(proposal: proposal, context: context))
            }
        }
        let shares = dealtHeights(
            of: children,
            naturalHeight: children.indices.map {
                children[$0].isSpacer ? children[$0].spacerLength(along: .vertical) : sizes[$0].height
            },
            isFlexible: children.indices.map { children[$0].isSpacer || sizes[$0].isHeightFlexible },
            available: max(0, limit), context: context)
        for (index, size) in squeezable where shares[index] < size.height {
            sizes[index] = children[index].measure(
                proposal: ProposedSize(width: proposal.width, height: shares[index]), context: context)
        }
        return sizes
    }
}
