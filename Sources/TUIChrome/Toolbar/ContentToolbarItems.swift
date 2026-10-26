//  🖥️ TUI — A Terminal UI framework for Swift
//  ContentToolbarItems.swift
//
//  `.contentToolbar(for:content:)` for toolbar content: the items a tab view's
//  sidebar draws at its foot, whatever tab is selected. The view-builder form,
//  the placement and the sidebar's slot are TUIFoundation's
//  (`ContentToolbar.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Public Modifier

extension View {
    /// Populates the toolbar of the specified content view type with the
    /// toolbar content you provide — mirrors SwiftUI's
    /// `contentToolbar(for:content:)` for toolbar content.
    ///
    /// For ``ContentToolbarPlacement/tabViewSidebar``, the items at the foot
    /// of a `.sidebarAdaptable` tab view's sidebar, under its tabs, whichever
    /// tab is selected: those placed in the top bar in a row, and under them
    /// those placed in the bottom bar, as iPadOS puts a `.bottomBar` item at
    /// the bottom of the sidebar — each row in the order the items are
    /// declared, one column apart.
    ///
    /// ```swift
    /// TabView { … }
    ///     .tabViewStyle(.sidebarAdaptable)
    ///     .contentToolbar(for: .tabViewSidebar) {
    ///         ToolbarItem(placement: .automatic) { DisconnectDevicesButton() }
    ///         ToolbarItem(placement: .bottomBar) { AccountSummaryView() }
    ///     }
    /// ```
    ///
    /// The items are drawn in the sidebar, in its environment, as the
    /// view-builder form's views are. iPadOS keeps an `.automatic` item in
    /// the sidebar's overflow menu; a terminal sidebar has room to show it, so
    /// it is in the row. A title menu, a default item and an item hidden with
    /// `hidden(_:)` are not drawn: the first two name the window's bars, which
    /// a sidebar is not.
    ///
    /// - Parameters:
    ///   - placement: The content view whose toolbar to populate.
    ///   - content: The toolbar content.
    /// - Returns: A view whose tab view sidebar's toolbar holds `content`.
    public func contentToolbar<Content: ToolbarContent>(
        for placement: ContentToolbarPlacement, @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        contentToolbar(for: placement, drawing: AnyView(_ContentToolbarRows(items: toolbarItems(of: content()))))
    }
}

// MARK: - The Rows

/// A content toolbar's items as the sidebar draws them: the top bar's
/// placements in a row, the bottom bar's in a row under it.
struct _ContentToolbarRows: View {
    /// The items the toolbar content declared, in order.
    let items: [_ToolbarItemSpec]

    var body: some View {
        let shown = items.filter { !$0.customization.isHiddenByApp && !$0.isTitleMenu && $0.defaultKind == nil }
        let top = shown.filter { $0.placement.bar == .top }
        let bottom = shown.filter { $0.placement.bar == .bottom }
        VStack(alignment: .leading, spacing: 0) {
            if !top.isEmpty { Self.row(top) }
            if !bottom.isEmpty { Self.row(bottom) }
        }
    }

    /// `items` side by side, each keyed by its place in the declaration (or
    /// its identifier), so its `@State` follows it.
    private static func row(_ items: [_ToolbarItemSpec]) -> some View {
        HStack(spacing: 1) {
            ForEach(items, id: \.slotKey) { $0.view }
        }
    }
}
