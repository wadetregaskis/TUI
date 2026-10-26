//  🖥️ TUI — A Terminal UI framework for Swift
//  BranchGuidePropagation.swift
//
//  An explicit alignment guide travels out through an `if`, an `if`/`else`
//  and a `switch`, which put one view where they stand: the shapes a body of
//  the app's own most often takes besides a single view, which a guide inside
//  it travels out of as it does in SwiftUI (decisions B19).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension ConditionalView: AlignmentGuideQuerying {
    /// The live branch's guide, laid out where the branch is: at the same
    /// size, at the branch identity it renders at.
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        switch self {
        case .trueContent(let content):
            TUIFoundation.explicitGuide(
                of: content, query, in: dimensions, context: context.withBranchIdentity("true"))
        case .falseContent(let content):
            TUIFoundation.explicitGuide(
                of: content, query, in: dimensions, context: context.withBranchIdentity("false"))
        }
    }
}

extension Optional: AlignmentGuideQuerying where Wrapped: View {
    /// The wrapped view's guide, laid out where it is — at the same size and
    /// identity, as an optional renders it — or none while it is `nil`.
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        guard case .some(let view) = self else { return nil }
        return TUIFoundation.explicitGuide(of: view, query, in: dimensions, context: context)
    }
}
