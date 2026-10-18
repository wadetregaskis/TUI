//  🖥️ TUIkit — Terminal UI Kit for Swift
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

extension _VStackCore {
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
}
