//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollView+Nested.swift
//
//  SCROLL-FIT's nested scroll views (design 2a, P7). A scroll view asked how
//  tall it would be with nothing to stop it — a horizontal one in a vertical
//  one's content, or one under `.fixedSize` — is its content's height
//  (`naturalHeight(proposal:ideal:context:)`), drawn whole.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension _ScrollViewCore {
    /// This scroll view's height when it is asked how tall it would be with
    /// nothing to stop it — no height proposed, offered the natural-extent
    /// ladder's budget, given none: `.fixedSize`, or a horizontal scroll view
    /// in a vertical one's content. Its content's ideal height (`ideal`),
    /// where it answered the budget, flexibly: 4,096 lines in a scroll view,
    /// and under `.fixedSize` the height it was offered. `nil` anywhere else.
    func naturalHeight(proposal: ProposedViewSize, ideal: (width: Int, height: Int)?, context: RenderContext) -> Int? {
        guard context.environment.scrollFitsContent, proposal.height == nil, !context.hasExplicitHeight,
            isNaturalExtentBudget(context.availableHeight), let ideal
        else { return nil }
        return ideal.height
    }
}
