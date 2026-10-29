//  🖥️ TUI — A Terminal UI framework for Swift
//  TabSearchActivation.swift
//
//  SwiftUI's `TabSearchActivation` and `View.tabViewSearchActivation(_:)`
//  (macOS 26): whether selecting a tab view's search tab
//  (`Tab(role: .search)`) activates the search of a `.searchable` around it,
//  and ending that search goes back to the tab before.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// Configures the activation behavior of search in the search tab — mirrors
/// SwiftUI's `TabSearchActivation`. Set it on a ``TabView`` with
/// ``View/tabViewSearchActivation(_:)``.
public struct TabSearchActivation: Hashable, Sendable {
    private let linksSelection: Bool

    /// The default: search activates only when the user interacts with the
    /// search field, and dismissing search does nothing else.
    public static var automatic: Self { Self(linksSelection: false) }

    /// Links the search tab's selection to search activation: selecting the
    /// search tab activates search (the field takes the focus), and when the
    /// search is dismissed the search tab is deselected and the tab selected
    /// before it is selected again.
    public static var searchTabSelection: Self { Self(linksSelection: true) }

    var isLinked: Bool { linksSelection }
}

private struct TabSearchActivationKey: EnvironmentKey {
    static let defaultValue = TabSearchActivation.automatic
}

extension EnvironmentValues {
    /// How the tab views beneath activate search (``View/tabViewSearchActivation(_:)``).
    var tabSearchActivation: TabSearchActivation {
        get { self[TabSearchActivationKey.self] }
        set { self[TabSearchActivationKey.self] = newValue }
    }
}

extension View {
    /// Configures the activation and deactivation behavior of search in the
    /// search tab — mirrors SwiftUI's `tabViewSearchActivation(_:)`.
    ///
    /// ```swift
    /// TabView {
    ///     Tab("Books", systemImage: "book") { BooksTab() }
    ///     Tab(role: .search) { SearchContent() }
    /// }
    /// .searchable(text: $text)
    /// .tabViewSearchActivation(.searchTabSelection)
    /// ```
    ///
    /// - Parameter activation: How search activates.
    /// - Returns: A view whose tab views activate search so.
    public func tabViewSearchActivation(_ activation: TabSearchActivation) -> some View {
        environment(\.tabSearchActivation, activation)
    }
}

/// A tab view's content with its search tab linked to the search around it,
/// where ``TabSearchActivation/searchTabSelection`` asks (the tab view adds
/// it only then): selecting the search tab
/// activates the search, and the search ending while the search tab is
/// selected selects the tab before it again.
///
/// The search ends when the field gives up the focus with nothing in it —
/// dismissed (which empties it), or left empty. The focus leaving a field that
/// holds a query is the reader going to its results, Tab from the field into
/// the search tab's content, and keeps the tab.
struct _TabSearchLink<Content: View>: View {
    let content: Content
    /// The tab view's selection.
    let selection: Binding<AnyHashable>
    /// The search tab's value.
    let searchTab: AnyHashable

    @Environment(\.searchActivation) private var search

    /// The tab selected before the search tab, to go back to.
    @State private var before: AnyHashable?

    var body: some View {
        let selected = selection.wrappedValue
        let searching = search?.isSearching ?? false
        return content
            .onChange(of: selected) { old, new in
                guard new == searchTab, old != searchTab else { return }
                before = old
                search?.activateSearch()
            }
            .onChange(of: searching) { wasSearching, isSearching in
                guard wasSearching, !isSearching, search?.hasEmptyQuery ?? true, selection.wrappedValue == searchTab,
                    let before
                else { return }
                selection.wrappedValue = before
                self.before = nil
            }
    }
}
