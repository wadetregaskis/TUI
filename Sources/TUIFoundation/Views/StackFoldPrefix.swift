//  🖥️ TUI — A Terminal UI framework for Swift
//  StackFoldPrefix.swift
//
//  The rows a lazy stack's append-while-fits walk can reach, built one at a
//  time, for a large keyed loop: the walk draws rows top-down and stops at
//  the first that does not fit, so it never needs a row past that one, and
//  building the loop's every row for it cost Ω(rows) on every such walk — and
//  for SwiftUI's endless-list idiom, `ForEach(0..<Int.max)`, an array of
//  `Int.max` children, which traps. The walk itself is `renderWindow`'s.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

@MainActor extension _VStackCore {
    /// The rows of a large keyed loop down to the first that would not fit
    /// in `context.availableHeight`, that one included, with the membership
    /// test of the loop's every row for the rows' fades — or `nil`, for the
    /// whole of the content resolved as before.
    ///
    /// Taken where `renderWindow`'s walk draws from the stack's first row,
    /// whole: under a measure, which takes no window — the first frame's
    /// measuring walk of the page (`RenderLoop.prepareWindowChrome`), whose
    /// scroll view gives its content only the lines down to the viewport's
    /// bottom (`drawsPrefixOnly`) — and where there is no window to take. Not
    /// where the viewport window would be drawn instead, which places every
    /// row it is handed.
    ///
    /// Only for the content the anchored measure estimates
    /// (`estimatesRows(count:context:)`), a loop whose rows are built on
    /// demand (`ChildViewCollection/isUniformlyKeyed`): below the threshold
    /// the eager resolve is what it always was. A row met that is a spacer
    /// gives the content back to the eager resolve, which distributes the
    /// height among every spacer; one past the fold is not looked for, as the
    /// anchored measure looks only in its sample.
    ///
    /// Each row is measured as the walk measures it, so the walk's own measure
    /// of it is the pass memo's; the prefix ends where that walk stops, or one
    /// row later where a row draws taller than it measures, where the walk
    /// stops sooner.
    func foldPrefix(
        context: RenderContext
    ) -> (children: [ChildView], isRow: @MainActor (WindowedRow) -> Bool)? {
        guard context.isMeasuring || consumableScrollWindow(context: context) == nil else { return nil }
        let collection = resolveChildViewCollection(from: content, context: context)
        guard collection.isUniformlyKeyed, estimatesRows(count: collection.count, context: context) else {
            return nil
        }
        var rowsContext = context
        rowsContext.leaveScrollOrigin()
        var prefix: [ChildView] = []
        var height = 0
        for ordinal in 0..<collection.count {
            let child = collection[ordinal]
            guard !child.isSpacer else { return nil }
            prefix.append(child)
            let measured = child.measure(proposal: .unspecified, context: rowsContext).height
            let gap = linearSpacing(before: measured, placedExtent: height, spacing: spacing)
            let next = height.saturatingAdding(gap).saturatingAdding(measured)
            if next > context.availableHeight { break }
            height = next
        }
        return (prefix, WindowedRow.isAmong(collection, under: context.identity))
    }
}
