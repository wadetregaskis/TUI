//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SearchPresentation.swift
//
//  Reaching the search field a `.searchable` draws from outside it: binding
//  its focus to a `@FocusState` (`searchFocused`), and presenting or ending
//  the search from a binding (`searchable(text:isPresented:…)`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - searchFocused

extension View {
    /// Binds the focus of the search field of the nearest searchable modifier
    /// to a Boolean focus state. Mirrors SwiftUI's `searchFocused(_:)`.
    ///
    /// Write it after the `searchable`, as SwiftUI's examples do:
    ///
    /// ```swift
    /// List(results) { Text($0.name) }
    ///     .searchable(text: $query)
    ///     .searchFocused($isSearchFieldFocused)
    /// ```
    ///
    /// When the focus moves to the search field the state becomes `true`, and
    /// `false` when it leaves; setting it to `true` moves the focus there, and
    /// to `false` takes the focus off it.
    ///
    /// - Parameter binding: The focus state to bind.
    /// - Returns: The modified view.
    public func searchFocused(_ binding: FocusState<Bool>.Binding) -> some View {
        environment(\.searchFocusOffer, TypedSearchFocusOffer(store: binding.store, value: true))
    }

    /// Binds the focus of the search field of the nearest searchable modifier
    /// to a focus state's value. Mirrors SwiftUI's `searchFocused(_:equals:)`.
    ///
    /// The state takes `value` while the search field holds the focus, and
    /// setting the state to `value` moves the focus there.
    ///
    /// - Parameters:
    ///   - binding: The focus state to bind.
    ///   - value: The value the state takes while the search field is
    ///     focused.
    /// - Returns: The modified view.
    public func searchFocused<V: Hashable>(_ binding: FocusState<V>.Binding, equals value: V) -> some View {
        environment(\.searchFocusOffer, TypedSearchFocusOffer(store: binding.store, value: value))
    }
}

/// A `searchFocused` binding on its way in to the search field.
///
/// Compared by the focus state's stable id and the bound value, not by
/// identity: the modifier builds a new one on every body, and an environment
/// value that changed every frame would turn the memos off below it — the
/// whole of the searchable content.
@MainActor
class SearchFocusOffer: Equatable {
    let storeID: String
    /// Immutable, and only compared — `AnyHashable` is not `Sendable`, so the
    /// comparison, which the environment makes from outside the main actor,
    /// reads it unchecked.
    nonisolated(unsafe) let value: AnyHashable

    init(storeID: String, value: AnyHashable) {
        self.storeID = storeID
        self.value = value
    }

    /// Binds the field that renders under `focusID` to the focus state.
    func bind(focusID: String, context: RenderContext) {}

    nonisolated static func == (lhs: SearchFocusOffer, rhs: SearchFocusOffer) -> Bool {
        lhs.storeID == rhs.storeID && lhs.value == rhs.value
    }
}

/// The offer for a focus state of one value type.
final class TypedSearchFocusOffer<Value: Hashable>: SearchFocusOffer {
    private let store: FocusStateStore<Value>
    private let boundValue: Value

    init(store: FocusStateStore<Value>, value: Value) {
        self.store = store
        self.boundValue = value
        super.init(storeID: store.storeID, value: AnyHashable(value))
    }

    override func bind(focusID: String, context: RenderContext) {
        FocusBindingRegistrar.bind(store: store, value: boundValue, focusID: focusID, context: context)
    }
}

private struct SearchFocusOfferKey: EnvironmentKey {
    static let defaultValue: SearchFocusOffer? = nil
}

extension EnvironmentValues {
    /// The `searchFocused` binding for the nearest searchable's field.
    var searchFocusOffer: SearchFocusOffer? {
        get { self[SearchFocusOfferKey.self] }
        set { self[SearchFocusOfferKey.self] = newValue }
    }
}

// MARK: - The field's wrapper

/// Wraps the search field a `.searchable` draws: records where it rendered,
/// so the searchable can move the focus to it, and binds a `searchFocused`
/// focus state to it when one was offered.
struct _SearchFieldFocus<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let search: SearchDismissal

    var body: Never {
        fatalError("_SearchFieldFocus renders via Renderable")
    }

    /// The id a bound field is forced to — derived from this wrapper's own
    /// identity, as `.focused`'s is from its own.
    private func forcedID(_ context: RenderContext) -> String {
        "searchfield-\(context.identity.path)"
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring { search.fieldIdentity = context.identity }
        guard let offer = context.environment.searchFocusOffer else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        let id = forcedID(context)
        offer.bind(focusID: id, context: context)
        var environment = context.environment
        environment.searchFocusOffer = nil
        environment.assignedFocusID = AssignedFocusID(id: id)
        return TUIkitView.renderToBuffer(content, context: context.withEnvironment(environment))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard context.environment.searchFocusOffer != nil else {
            return measureChild(content, proposal: proposal, context: context)
        }
        var environment = context.environment
        environment.searchFocusOffer = nil
        environment.assignedFocusID = AssignedFocusID(id: forcedID(context))
        return measureChild(content, proposal: proposal, context: context.withEnvironment(environment))
    }
}
