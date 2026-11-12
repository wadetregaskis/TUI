//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationSplitViewNaturalHeight.swift
//
//  How tall a `NavigationSplitView` is when it is offered no height: a
//  vertical scroll view's content, or under `.fixedSize`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIView

extension _NavigationSplitViewCore {
    /// The split's height offered none: the tallest visible column's, each
    /// measured offered no height at the width the render gives it, as
    /// ``HSplitView`` answers its tallest pane's. At least one line.
    ///
    /// It answered one line, flexible, whatever its columns held: in a scroll
    /// view it took the viewport's height, the sidebar's rows past it out of
    /// reach, and under `.fixedSize` it was one line (SCROLL-FIT, L0).
    ///
    /// Read-only: it reads the toggle's, the widths' and the collapse's state
    /// where a render has made them, and makes none. A column hidden by
    /// `columnVisibility` does not count. Collapsed, the column on top counts,
    /// under the navigation bar when anything is behind it; a screen a link
    /// pushed above it is measured as that column, as the destination is only
    /// known from a render.
    func naturalHeight(context: RenderContext) -> Int {
        var measuring = context
        measuring.isMeasuring = true
        if isCollapsed(context) { return max(1, collapsedNaturalHeight(context: measuring)) }
        let toggleState = existingState(SplitViewToggleState.self, at: SplitViewStateIndex.toggle, context)
        let visibleColumns = calculateVisibleColumns(visibility: resolveVisibility(toggleState: toggleState))
        guard !visibleColumns.isEmpty else { return 1 }
        let columnsContext =
            hasEdgeColumn(visibleColumns: visibleColumns, context: measuring, toggleState: toggleState)
            ? columnsBesideEdge(measuring) : measuring
        let resizable = context.environment.navigationSplitViewResizable && context.stateStorage != nil
        let widths: [Int] = columnWidths(
            visibleColumns: visibleColumns, style: context.environment.navigationSplitViewStyle,
            context: columnsContext, widths: resizable ? resolvePersistedWidths(context: measuring) : nil,
            writeBack: false)
        var tallest = 1
        for (column, width) in zip(visibleColumns, widths) {
            let size = measureColumn(
                column, proposal: ProposedViewSize(width: width, height: nil),
                context: columnsContext.withAvailableSize(width: width, height: columnsContext.availableHeight))
            tallest = max(tallest, size.height)
        }
        return tallest
    }

    /// The collapsed split's height offered none: the column on top's, under
    /// the navigation bar when a column or a link is behind it.
    private func collapsedNaturalHeight(context: RenderContext) -> Int {
        let state =
            existingState(SplitViewCollapseState.self, at: SplitViewStateIndex.collapse, context)
            ?? SplitViewCollapseState()
        let position = CompactColumnPosition(
            binding: preferredCompactColumn, state: state,
            columns: isThreeColumn ? [.sidebar, .content, .detail] : [.sidebar, .detail])
        let depth = position.depth
        let links = state.linksDepth == depth ? state.links.count : 0
        let width = max(0, context.availableWidth)
        let column = measureColumn(
            position.columns[depth], proposal: ProposedViewSize(width: width, height: nil),
            context: context.withAvailableSize(width: width, height: context.availableHeight))
        return column.height + (depth + links > 0 ? NavigationBar.height : 0)
    }

    /// The split's state at `index` where a render has made it, else `nil`.
    private func existingState<Value>(_: Value.Type, at index: Int, _ context: RenderContext) -> Value? {
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: index)
        let box: StateBox<Value>? = context.stateStorage?.existingStorage(for: key)
        return box?.value
    }
}
