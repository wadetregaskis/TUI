//  🖥️ TUI — A Terminal UI framework for Swift
//  StackOverflowProbe.swift
//
//  The eager column's answer to a scroll view's overflow probe: the
//  scrollbar's first round asks only WHETHER the content is taller than the
//  viewport, and a column of rows knows that once its rows pass the viewport,
//  without measuring the rest. See `RenderContext.asksOverflow` for the mark
//  that asks, and `ScrollView+Content.swift`'s `contentOverflowsCanvas` for
//  the one asker.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Content the probe may ask

/// A view whose measure IS an eager column's: `VStack`, whose body is the
/// `.clip` core that answers the overflow mark.
///
/// A marker rather than a check of `_VStackCore`, which is `LazyVStack`'s body
/// too: a lazy stack ignores the mark, but the mark would still key its
/// answers apart from every unmarked ask in the pass.
package protocol OverflowProbedColumn {}

@MainActor extension VStack: OverflowProbedColumn {}

/// Whether measuring a `V` is measuring an eager column, by `V`'s type alone:
/// `V` is a `VStack`, or a view of the app's own whose body is one, at any
/// depth of such views.
///
/// The test that decides where the overflow mark may go, because a column
/// that stops answers for its height exactly and for its width and
/// flexibility only as far as it measured. A view of the app's own measures
/// as its body does and nothing else (`measureCompositeBody`), so between it
/// and the column nothing reads those. Anything else might — a `fixedSize`
/// that proposes the column its own ideal width back, a row that hands its
/// children the width the others leave, a `ViewThatFits` that picks by width
/// — and a narrower width than the column's real one could pick a layout that
/// is taller than the real one: a yes for content that fits. So the mark goes
/// nowhere else, and such content is asked as before.
///
/// Bounded, for a view whose body type is itself, which could not be drawn
/// either.
func measuresAsEagerColumn<V: View>(_ type: V.Type, depth: Int = 0) -> Bool {
    if type is any OverflowProbedColumn.Type { return true }
    guard depth < 16, V.Body.self != Never.self, !(type is any Layoutable.Type), !(type is any Renderable.Type)
    else { return false }
    return measuresAsEagerColumn(V.Body.self, depth: depth + 1)
}

// MARK: - The column's answer

@MainActor extension _VStackCore {
    /// The eager column's size under the overflow mark
    /// (`RenderContext.asksOverflow`): its rows measured as the unmarked
    /// probe measures them, until they reach the column's budget — one line
    /// past the height the probe asks about.
    ///
    /// The rows are asked exactly what the unmarked probe asks them: the mark
    /// cleared, and the budget the ladder's first rung offers for that height
    /// (`naturalExtentStartingBudget`), which is what the unmarked probe
    /// offers the whole content. So each row's answer, and its entry in the
    /// pass's memo, is what it was; a `TabView` among them files the extent it
    /// always did; a `ViewThatFits` picks what it always picked. Only the
    /// column's own answer differs, and the mark keys it apart.
    ///
    /// Once the rows and the gaps between them reach the budget, the column
    /// is at least that tall whatever the rest hold: a measured height is
    /// never negative, and neither is a gap — a NEGATIVE `spacing` subtracts
    /// one per row, so such a column never stops. It then reports the budget,
    /// which is what the whole column reports there (`min(total, budget)`),
    /// with the width and flexibility of the rows it measured, which are not
    /// its own, and no claim to a natural size.
    ///
    /// The walk is the column's own (`clipSizeThatFits`, told where to stop),
    /// so a column that never reaches the budget has measured every row once,
    /// as the unmarked ask does, and answers from them as the whole column
    /// does. Not a walk of its own here with the column's after it to answer:
    /// that walks a column that fits twice — on every layout of a text-style
    /// view's content-margins probe, a lookup per row where the memo keeps
    /// them and a measure per row where it does not.
    func overflowProbeSizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let budget = context.availableHeight
        var rowContext = context.askingOverflow(false)
        if budget > 0, budget < Int.max {
            rowContext.availableHeight = naturalExtentStartingBudget(forVisible: budget - 1)
        }
        let stops = proposal.width != nil && proposal.height == nil && !context.asksIdealWidth && spacing >= 0 && budget > 0
        return clampedToBudget(
            clipSizeThatFits(proposal: proposal, context: rowContext, stoppingAt: stops ? budget : nil), budget)
    }

    /// `size`, as the column answers at `budget`: its height no taller, and
    /// no claim to a natural size when that cut it.
    private func clampedToBudget(_ size: ViewSize, _ budget: Int) -> ViewSize {
        guard size.height > max(0, budget) else { return size }
        return ViewSize(
            width: size.width, height: max(0, budget),
            isWidthFlexible: size.isWidthFlexible, isHeightFlexible: size.isHeightFlexible)
    }
}
