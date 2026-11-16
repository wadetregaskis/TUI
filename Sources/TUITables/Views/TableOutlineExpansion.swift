//  🖥️ TUI — A Terminal UI framework for Swift
//  TableOutlineExpansion.swift
//
//  Where a hierarchical table keeps which of its branches are open: at the
//  table's own place, as SwiftUI's does, or — for a `Table(_:children:)`
//  handed an `expansion:` binding, which SwiftUI's takes none of — in the
//  app's set of ids.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

/// Where a hierarchical table's open branches are kept: the branches no
/// `DisclosureTableRow` binding owns.
///
/// The table's own state (a ``StateBox`` at its place, keyed by `AnyHashable`
/// ids) unless a `Table(_:children:expansion:)` was handed the app's binding,
/// in which case the binding is the only record: the table opens exactly the
/// ids in it, and writes it when the user opens or closes a branch.
@MainActor
struct _TableOutlineExpansion<Value: Identifiable> {
    private enum Store {
        case table(StateBox<Set<AnyHashable>>)
        case app(Binding<Set<Value.ID>>)
    }

    private let store: Store

    /// The expansion the table keeps itself, at its place.
    init(_ box: StateBox<Set<AnyHashable>>) {
        store = .table(box)
    }

    /// The expansion the app keeps, in `binding`.
    init(_ binding: Binding<Set<Value.ID>>) {
        store = .app(binding)
    }

    /// The open branches as one reading of them: what a flattening asks of
    /// each branch, and what a kept outline compares to say it is still the
    /// outline of these branches.
    enum Reading: Equatable {
        /// The table's own: the box, by identity, and what it held.
        case table(ObjectIdentifier, Set<AnyHashable>)
        /// The app's.
        case app(Set<Value.ID>)

        /// Whether the branch `id` names is open.
        func contains(_ id: Value.ID) -> Bool {
            switch self {
            case .table(_, let open): open.contains(AnyHashable(id))
            case .app(let open): open.contains(id)
            }
        }
    }

    /// The open branches now. Read once for each flattening, and once for
    /// each key or click that opens or closes branches, so two keys handled
    /// before the next frame each see what the one before wrote.
    func read() -> Reading {
        switch store {
        case .table(let box): .table(ObjectIdentifier(box), box.value)
        case .app(let binding): .app(binding.wrappedValue)
        }
    }

    /// Opens or closes the branches `ids` name, in one write: a binding's set
    /// copied once, however many branches an Option-Right reaches, rather than
    /// once a branch.
    func set(_ ids: [Value.ID], open: Bool) {
        guard !ids.isEmpty else { return }
        switch store {
        case .table(let box):
            let keys = ids.lazy.map { AnyHashable($0) }
            if open { box.value.formUnion(keys) } else { box.value.subtract(keys) }
        case .app(let binding):
            var set = binding.wrappedValue
            if open { set.formUnion(ids) } else { set.subtract(ids) }
            binding.wrappedValue = set
        }
    }
}
