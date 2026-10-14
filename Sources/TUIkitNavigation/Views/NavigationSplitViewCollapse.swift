//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewCollapse.swift
//
//  A `NavigationSplitView` in a horizontally compact size class collapses
//  into a stack, as SwiftUI's does on iPhone (decisions A21, B3): one column
//  on top, the columns before it behind, a navigation bar to go back by, and
//  `preferredCompactColumn` saying which column is on top.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - preferredCompactColumn

extension NavigationSplitView where Content == EmptyView {
    /// Creates a two-column navigation split view that enables programmatic
    /// control over which column appears on top when the view collapses into
    /// a single column in a compact size class.
    ///
    /// - Parameters:
    ///   - preferredCompactColumn: A binding to state that controls which
    ///     column appears on top when the view collapses.
    ///   - sidebar: The view to show in the leading column.
    ///   - detail: The view to show in the detail area.
    public init(
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = EmptyView()
        self.detail = detail()
        self.isThreeColumn = false
        self.columnVisibility = nil
        self.preferredCompactColumn = preferredCompactColumn
    }

    /// Creates a two-column navigation split view that enables programmatic
    /// control of the sidebar's visibility in a regular size class and which
    /// column appears on top when the view collapses in a compact one.
    ///
    /// - Parameters:
    ///   - columnVisibility: A binding to state that controls the visibility of the sidebar.
    ///   - preferredCompactColumn: A binding to state that controls which
    ///     column appears on top when the view collapses.
    ///   - sidebar: The view to show in the leading column.
    ///   - detail: The view to show in the detail area.
    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = EmptyView()
        self.detail = detail()
        self.isThreeColumn = false
        self.columnVisibility = columnVisibility
        self.preferredCompactColumn = preferredCompactColumn
    }
}

extension NavigationSplitView {
    /// Creates a three-column navigation split view that enables programmatic
    /// control over which column appears on top when the view collapses into
    /// a single column in a compact size class.
    ///
    /// - Parameters:
    ///   - preferredCompactColumn: A binding to state that controls which
    ///     column appears on top when the view collapses.
    ///   - sidebar: The view to show in the leading column.
    ///   - content: The view to show in the middle column.
    ///   - detail: The view to show in the detail area.
    public init(
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        self.isThreeColumn = true
        self.columnVisibility = nil
        self.preferredCompactColumn = preferredCompactColumn
    }

    /// Creates a three-column navigation split view that enables programmatic
    /// control of the leading columns' visibility in a regular size class and
    /// which column appears on top when the view collapses in a compact one.
    ///
    /// - Parameters:
    ///   - columnVisibility: A binding to state that controls the visibility of leading columns.
    ///   - preferredCompactColumn: A binding to state that controls which
    ///     column appears on top when the view collapses.
    ///   - sidebar: The view to show in the leading column.
    ///   - content: The view to show in the middle column.
    ///   - detail: The view to show in the detail area.
    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        self.isThreeColumn = true
        self.columnVisibility = columnVisibility
        self.preferredCompactColumn = preferredCompactColumn
    }
}

// MARK: - State

/// What a collapsed split keeps between frames, at
/// ``SplitViewStateIndex/collapse``.
@MainActor
final class SplitViewCollapseState {
    /// The column on top of a split with no `preferredCompactColumn` binding.
    /// A split with a binding never reads it.
    var column = NavigationSplitViewColumn.sidebar

    /// The path the columns above the sidebar make: what the navigation bar
    /// goes back along, and whose titles its trail names.
    let coordinator = NavigationCoordinator()

    /// The column on top's way to the next column, which its lists run when a
    /// row is chosen. One box for the split's life, so the environment value
    /// that carries it is the same value every frame and the memos below the
    /// column stay on.
    let advance = DismissAction.Box()

    /// The column on top's `\.dismiss`, going back a column — boxed for the
    /// same reason.
    let dismiss = DismissAction.Box()
}

/// Where a collapsed split's column on top is kept — the app's binding, else
/// the split's own state — and the columns it moves among. Read when a key or
/// a list moves along the stack, not when the closure doing so was made, so
/// the move steps from the column on top at that moment.
@MainActor
struct CompactColumnPosition {
    let binding: Binding<NavigationSplitViewColumn>?
    let state: SplitViewCollapseState
    /// The columns from the bottom of the stack: the sidebar, the content
    /// column in a three-column split, and the detail.
    let columns: [NavigationSplitViewColumn]

    /// How far up the stack the column on top is. A two-column split has no
    /// content column, and what follows its sidebar is the detail.
    var depth: Int {
        let column = binding?.wrappedValue ?? state.column
        if columns.count == 2, column == .content { return 1 }
        return columns.firstIndex(of: column) ?? 0
    }

    /// Puts the column at `depth` on top, through the binding when there is
    /// one.
    func show(depth: Int) {
        let column = columns[max(0, min(depth, columns.count - 1))]
        if let binding {
            binding.wrappedValue = column
        } else {
            state.column = column
        }
    }
}

// MARK: - Rendering

extension _NavigationSplitViewCore {
    /// Whether the split is collapsed: its horizontal size class is compact.
    func isCollapsed(_ context: RenderContext) -> Bool {
        context.environment.horizontalSizeClass == .compact
    }

    /// The split collapsed into a stack: the column on top, full width, under
    /// a navigation bar when it is not the sidebar.
    ///
    /// The columns behind it render too, off-screen and isolated from focus
    /// and keys as a navigation stack's root is, so their `@State` is there to
    /// come back to and their titles name the bar's trail. The columns ahead of
    /// it do not: a detail is not drawn, nor its `task` run, until something
    /// brings it to the top, as on iPhone. Column visibility is ignored, as
    /// SwiftUI ignores it in a collapsed split; so are the handles, the widths
    /// and the sidebar chords.
    func renderCollapsed(context: RenderContext) -> FrameBuffer {
        let toggleState = beginToggleRender(context: context)
        let position = CompactColumnPosition(
            binding: preferredCompactColumn,
            state: context.stateStorage?.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: SplitViewStateIndex.collapse),
                default: SplitViewCollapseState()
            ).value ?? SplitViewCollapseState(),
            columns: isThreeColumn ? [.sidebar, .content, .detail] : [.sidebar, .detail])
        let depth = position.depth
        let top = position.columns[depth]
        let focusManager = context.environment.focusManager
        declareFocusRegistrations(context: context, focusManager: focusManager)

        let width = max(0, context.availableWidth)
        let columnHeight = max(0, context.availableHeight - (depth > 0 ? NavigationBar.height : 0))
        let coordinator = position.state.coordinator
        if !context.isMeasuring {
            // The path is the columns above the sidebar, read and written at
            // the moment the bar goes back along it.
            coordinator.read = { position.columns.dropFirst().prefix(position.depth).map { AnyHashable($0) } }
            coordinator.write = { path in position.show(depth: path.count) }
            renderColumnsBehind(
                position.columns.prefix(depth), coordinator: coordinator,
                context: context.withAvailableSize(width: width, height: columnHeight))
        }

        // Each column keeps its own focus section, so going forward a column
        // and back restores the focus the column you left was holding, as a
        // navigation stack's depths do. Before the column renders, so it
        // registers into its section with any deeper one already gone.
        let section =
            context.isMeasuring
            ? nil
            : coordinator.enterSection(
                depth: depth, context: context,
                sectionID: { focusSectionID(for: position.columns[$0], context: context) })
        var columnContext = context.withAvailableSize(width: width, height: columnHeight)
        if let section {
            columnContext = columnFocusContext(columnContext, sectionID: section, focusManager: focusManager)
        }
        wireCompactActions(position: position, depth: depth, columnContext: &columnContext)

        // Where the bar's Escape handler goes: behind everything the column
        // registers (see `NavigationBar.render`).
        let escapeHandlerSlot = context.environment.keyEventDispatcher?.handlerCount ?? 0
        // The column's own preferences, for the bar to read the title it set.
        // Collecting observes this pass's preferences, and is declared to any
        // value-memoizing ancestor, as a navigation stack's collection is.
        let collectsTitle = depth > 0 && !context.isMeasuring
        let preferences = columnContext.environment.preferenceStorage
        if collectsTitle {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            preferences?.push()
        }
        let column = renderColumn(top, context: columnContext, toggleState: toggleState)
        let published = collectsTitle ? preferences?.pop() : nil
        if !context.isMeasuring {
            // The keyboard stays in the split when the section that held it
            // went with the columns the collapse put away.
            endToggleRender(
                toggleState: toggleState, visibleColumns: [top], context: context, focusManager: focusManager)
        }

        let content = NavigationBar.padded(column, toWidth: width, height: columnHeight)
        guard depth > 0 else { return content }
        var barContext = context
        if let section { barContext.environment.activeFocusSectionID = section }
        var buffer = NavigationBar(coordinator: coordinator).render(
            title: published?[NavigationTitleKey.self] ?? "",
            subtitle: published?[NavigationSubtitleKey.self] ?? "",
            hidesBack: published?[NavigationBackButtonHiddenKey.self] ?? false,
            hidesTitle: published?[ToolbarTitleRemovedKey.self] == true || context.environment.toolbarTitleRemoved,
            width: width, escapeHandlerSlot: escapeHandlerSlot, context: barContext)
        buffer.appendVertically(content)
        return buffer
    }

    /// Renders the columns behind the one on top, off-screen, for their
    /// `@State` and their titles: each records its `navigationTitle` at its
    /// depth, for the bar's trail.
    private func renderColumnsBehind(
        _ behind: ArraySlice<NavigationSplitViewColumn>, coordinator: NavigationCoordinator,
        context: RenderContext
    ) {
        guard !behind.isEmpty else { return }
        // Not a demand for a frame but a refusal to be cached, as a navigation
        // stack's root render is: served from a memo, the columns behind would
        // not render, and `endRenderPass` would prune the `@State` this exists
        // to keep.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        for (depth, column) in zip(behind.indices, behind) {
            let backdrop = context.isolatedForBackground()
            let preferences = backdrop.environment.preferenceStorage
            preferences?.push()
            _ = backdrop.withThrowawayFrameDemand { hidden in renderColumnContent(column, context: hidden) }
            coordinator.recordTitle(preferences?.pop()[NavigationTitleKey.self] ?? "", atDepth: depth)
        }
    }

    /// Hands the column on top its ways along the stack: `\.dismiss` goes back
    /// a column, and its lists show the next column when a row is chosen
    /// (``EnvironmentValues/compactColumnAdvance``).
    private func wireCompactActions(
        position: CompactColumnPosition, depth: Int, columnContext: inout RenderContext
    ) {
        let state = position.state
        if depth > 0 {
            state.dismiss.action = { state.coordinator.pop() }
            columnContext.environment.dismiss = DismissAction(box: state.dismiss)
        }
        guard depth < position.columns.count - 1 else {
            // The last column has no next one, and an enclosing collapsed
            // split's is not this split's.
            if columnContext.environment.compactColumnAdvance != nil {
                columnContext.environment.compactColumnAdvance = nil
            }
            return
        }
        let focusManager = columnContext.environment.focusManager
        state.advance.action = {
            // Not from a sheet or a popover over the split, whose lists are in
            // the column's environment too.
            guard focusManager?.activeSectionIsModal != true else { return }
            position.show(depth: position.depth + 1)
        }
        columnContext.environment.compactColumnAdvance = CompactColumnAdvance(box: state.advance)
    }
}
