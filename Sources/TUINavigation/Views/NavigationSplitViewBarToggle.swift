//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationSplitViewBarToggle.swift
//
//  The sidebar toggle of ``NavigationSplitView`` as a toolbar's button works it:
//  what the split publishes to its columns and offers to the window, and the
//  name a labelled button gives the sidebar in the split's own key hints. Split
//  out of `NavigationSplitViewToggle.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

/// The identity step the window's own button for a split view's sidebar
/// takes under the split's.
enum _SidebarToggleItemSlot {}

/// The identity a bar's automatic content-column button draws at.
enum _ContentColumnToggleItemSlot {}

// MARK: - The bar's toggle

extension _NavigationSplitViewCore {
    /// The sidebar's toggle for a toolbar's button, for this render: published
    /// to the views in the split's columns, so a
    /// `DefaultToolbarItem(kind: .sidebarToggle)` declared there toggles this
    /// split, and offered to the window, whose first split view is the one an
    /// item declared round any split toggles.
    ///
    /// `nil`, and nothing offered, where the split shows no toggle handles —
    /// `.toolbar(removing: .sidebarToggle)` on or in it — or is disabled, as
    /// its chords are then; and while measuring, which declares nothing.
    ///
    /// The button toggles the sidebar alone, as ⌃S does (``SplitViewToggle/togglingSidebar(_:isThreeColumn:)``),
    /// leaving the keyboard where it is: in the bar.
    func sidebarToggle(
        visibleColumns: [NavigationSplitViewColumn], context: RenderContext, toggleState: SplitViewToggleState?
    ) -> PanelToggle? {
        guard let toggleState, !context.isMeasuring, context.environment.isEnabled,
            showsToggle(context: context, toggleState: toggleState)
        else { return nil }
        toggleState.barAction.perform = stepAction(toggleState: toggleState, focus: nil) { visibility, isThreeColumn in
            SplitViewToggle.togglingSidebar(visibility, isThreeColumn: isThreeColumn)
        }
        let toggle = PanelToggle(
            panel: .sidebar, owner: context.identity, isShown: visibleColumns.contains(.sidebar),
            action: toggleState.barAction)
        PanelToggleOffer.offer(
            toggle, itemIdentity: context.withChildIdentity(erasedType: _SidebarToggleItemSlot.self, key: "bar").identity,
            context: context)
        return toggle
    }

    /// `context` for the columns to render in: with this split's
    /// ``sidebarToggle(visibleColumns:context:toggleState:)``, so a toolbar item
    /// declared in a column toggles this split's sidebar — and in a split with no
    /// toggle, none of an outer one's.
    func publishingSidebarToggle(
        visibleColumns: [NavigationSplitViewColumn], context: RenderContext, toggleState: SplitViewToggleState?
    ) -> RenderContext {
        var columnBase = context
        columnBase.environment.sidebarToggleScope = .split(
            sidebarToggle(visibleColumns: visibleColumns, context: context, toggleState: toggleState))
        columnBase.environment.contentColumnToggleScope = .split(
            contentColumnToggle(visibleColumns: visibleColumns, context: context, toggleState: toggleState))
        return columnBase
    }

    /// The content column's toggle for a toolbar's button, as
    /// ``sidebarToggle(visibleColumns:context:toggleState:)`` is the
    /// sidebar's: three-column splits only, and none where the button was
    /// removed (`.toolbar(removing: .contentColumnToggle)`) or the split's
    /// toggles were. See `SplitViewToggle.togglingContent(_:isThreeColumn:)`
    /// for how it and the sidebar's stay coupled.
    func contentColumnToggle(
        visibleColumns: [NavigationSplitViewColumn], context: RenderContext, toggleState: SplitViewToggleState?
    ) -> PanelToggle? {
        guard isThreeColumn, let toggleState, !context.isMeasuring, context.environment.isEnabled,
            !context.environment.contentColumnToggleRemoved, showsToggle(context: context, toggleState: toggleState)
        else { return nil }
        toggleState.contentBarAction.perform = stepAction(toggleState: toggleState, focus: nil) { visibility, isThreeColumn in
            SplitViewToggle.togglingContent(visibility, isThreeColumn: isThreeColumn)
        }
        let toggle = PanelToggle(
            panel: .content, owner: context.identity, isShown: visibleColumns.contains(.content),
            action: toggleState.contentBarAction)
        PanelToggleOffer.offer(
            toggle,
            itemIdentity: context.withChildIdentity(erasedType: _ContentColumnToggleItemSlot.self, key: "bar").identity,
            context: context)
        return toggle
    }

    /// The key hint of a handle that hides (`hides`) or shows a column: "hide
    /// column" or "show column" — or, for the sidebar (`sidebar`) where a bar's
    /// labelled button names it (`DefaultToolbarItem(kind:placement:label:)`),
    /// that name, so the handles and the button speak of one thing.
    func handleHint(hides: Bool, sidebar: Bool, context: RenderContext, toggleState: SplitViewToggleState) -> String {
        if sidebar, let name = PanelToggle.name(of: context.identity, action: toggleState.barAction, in: context) {
            return PanelToggle.activationLabel(for: .sidebar, hides: hides, named: name)
        }
        return LocalizationService.shared.string(
            for: hides ? LocalizationKey.StatusBar.hideColumn : LocalizationKey.StatusBar.showColumn)
    }
}
