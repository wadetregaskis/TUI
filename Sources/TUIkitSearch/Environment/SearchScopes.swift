//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SearchScopes.swift
//
//  `searchScopes`: a segmented picker of scopes under a searchable's field,
//  shown while the search is under way.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - SearchScopeActivation

/// The ways that searchable modifiers can show or hide search scopes. Mirrors
/// SwiftUI's `SearchScopeActivation`.
public struct SearchScopeActivation: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case automatic, onTextEntry, onSearchPresentation
    }

    let kind: Kind

    /// The automatic activation of the scope bar: ``onSearchPresentation``, as
    /// on macOS.
    public static var automatic: Self { Self(kind: .automatic) }

    /// An activation where the scopes show once typing begins in the search
    /// field, and hide when the search is cancelled.
    public static var onTextEntry: Self { Self(kind: .onTextEntry) }

    /// An activation where the scopes show when search is presented — the
    /// search field takes the focus — and hide when the search is cancelled.
    public static var onSearchPresentation: Self { Self(kind: .onSearchPresentation) }
}

// MARK: - Modifiers

extension View {
    /// Configures the search scopes for this view. Mirrors SwiftUI's
    /// `searchScopes(_:scopes:)`.
    ///
    /// Write it after the `searchable`, as SwiftUI's examples do. The scopes
    /// are a segmented picker under the search field, built from `scopes` —
    /// views tagged with values of the binding's type, as a ``Picker``'s
    /// content is:
    ///
    /// ```swift
    /// ProductList()
    ///     .searchable(text: $query)
    ///     .searchScopes($scope) {
    ///         Text("Fruit").tag(ProductScope.fruit)
    ///         Text("Vegetable").tag(ProductScope.vegetable)
    ///     }
    /// ```
    ///
    /// The scopes show as macOS shows them: when search is presented. See
    /// ``View/searchScopes(_:activation:_:)`` for the other activations, and
    /// what "presented" and "cancelled" mean in a terminal.
    ///
    /// - Parameters:
    ///   - scope: The active scope of the search field.
    ///   - scopes: The scoping options, each with a ``View/tag(_:includeOptional:)``.
    public func searchScopes<V: Hashable, S: View>(
        _ scope: Binding<V>, @ViewBuilder scopes: () -> S
    ) -> some View {
        searchScopes(scope, activation: .automatic, scopes)
    }

    /// Configures the search scopes for this view with the specified
    /// activation strategy. Mirrors SwiftUI's `searchScopes(_:activation:_:)`.
    ///
    /// The search field is always on screen here, so the scopes' showing and
    /// hiding follows what the reader does with it:
    ///
    /// - ``SearchScopeActivation/onSearchPresentation`` (and
    ///   ``SearchScopeActivation/automatic``): shown while the field holds the
    ///   focus, while the query is not empty, and while the focus is in the
    ///   scopes themselves — so Tab from the field reaches them.
    /// - ``SearchScopeActivation/onTextEntry``: shown while the query is not
    ///   empty, and while the focus is in the scopes.
    ///
    /// Cancelling the search — `dismissSearch`, or leaving an empty field —
    /// hides them.
    ///
    /// - Parameters:
    ///   - scope: The active scope of the search field.
    ///   - activation: When the scopes show.
    ///   - scopes: The scoping options, each with a ``View/tag(_:includeOptional:)``.
    public func searchScopes<V: Hashable, S: View>(
        _ scope: Binding<V>, activation: SearchScopeActivation, @ViewBuilder _ scopes: () -> S
    ) -> some View {
        _SearchScopesModifier(content: self, scope: scope, activation: activation, scopes: scopes())
    }
}

// MARK: - The environment value

/// The scopes a `searchScopes` hands in to the searchable's field.
///
/// An object the modifier holds in `@State` and refreshes each body, compared
/// by identity, for the reason ``SearchDismissal`` is one: the picker it
/// carries holds a binding, which cannot be compared, and a value that cannot
/// be compared turns the memos off below it — the whole searchable content.
@MainActor
final class SearchScopeBar: Equatable {
    var picker = AnyView(EmptyView())
    var activation = SearchScopeActivation.automatic

    nonisolated static func == (lhs: SearchScopeBar, rhs: SearchScopeBar) -> Bool { lhs === rhs }
}

extension EnvironmentValues {
    /// The scopes for the nearest searchable's field.
    ///
    /// Kept in the substrate's `.searchScopeBar` slot (``FeatureObjectSlot``),
    /// which detaching an environment clears.
    var searchScopeBar: SearchScopeBar? {
        get { self[featureObject: .searchScopeBar] as? SearchScopeBar }
        set { self[featureObject: .searchScopeBar] = newValue }
    }
}

struct _SearchScopesModifier<Content: View, V: Hashable, S: View>: View {
    let content: Content
    let scope: Binding<V>
    let activation: SearchScopeActivation
    let scopes: S

    @State private var bar = SearchScopeBar()

    var body: some View {
        // Refreshed on every evaluation, so the field draws the scopes and the
        // binding as they stand now.
        bar.picker = AnyView(
            Picker(selection: scope, content: { scopes }, label: { EmptyView() })
                .pickerStyle(.segmented)
                .labelsHidden())
        bar.activation = activation
        return content.environment(\.searchScopeBar, bar)
    }
}

// MARK: - Drawing

/// The rows under the search field — the scopes, the suggested tokens: records
/// where they rendered, so the searchable can tell when the focus is in them.
struct _SearchAccessoryFrame<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let search: SearchDismissal

    var body: Never {
        fatalError("_SearchAccessoryFrame renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring { search.accessoryIdentity = context.identity }
        return TUIkitView.renderToBuffer(content, context: context)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension SearchScopeActivation {
    /// Whether the scopes show, for a field that does or does not hold the
    /// focus, over a query that is or is not empty, with the focus in the
    /// scopes or not.
    func showsScopes(isSearching: Bool, hasQuery: Bool, focusInScopes: Bool) -> Bool {
        if hasQuery || focusInScopes { return true }
        switch kind {
        case .automatic, .onSearchPresentation: return isSearching
        case .onTextEntry: return false
        }
    }
}
