//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineExpansion.swift
//
//  Where an outline keeps which of its branches are open: at the outline's own
//  place, as SwiftUI's does, or — for an `OutlineGroup` or `List(_:children:)`
//  handed an `expansion:` binding, which SwiftUI's take none of — in the app's
//  set of ids. The list's twin of `_TableOutlineExpansion` (TUITables), over
//  the outline's own typed ids rather than the table's `AnyHashable` ones.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIView

/// Where an outline's open branches are kept.
///
/// The outline's own state (a ``StateBox`` at its place) unless an
/// `OutlineGroup(_:children:expansion:content:)` was handed the app's binding,
/// in which case the binding is the only record: the outline opens exactly the
/// ids in it, and writes it when the user opens or closes a branch.
///
/// Not actor-isolated, as ``OutlineActivation`` is not: the disclosure closures
/// key dispatch calls hold one, and the render loop is the only writer.
struct OutlineExpansion<ID: Hashable> {
    private enum Store {
        case outline(StateBox<Set<ID>>)
        case app(Binding<Set<ID>>)
    }

    private let store: Store

    /// The expansion the outline keeps itself, at its place.
    init(_ box: StateBox<Set<ID>>) {
        store = .outline(box)
    }

    /// The expansion the app keeps, in `binding`.
    init(_ binding: Binding<Set<ID>>) {
        store = .app(binding)
    }

    /// The open branches as one reading of them: what a flattening opens, and
    /// what the kept rows (``OutlineVisibleNodes``) compare to say they are
    /// still the rows of these branches.
    enum Reading: Equatable {
        /// The outline's own: the box, by identity, and what it held.
        case outline(ObjectIdentifier, Set<ID>)
        /// The app's.
        case app(Set<ID>)

        /// The open branches' ids.
        var open: Set<ID> {
            switch self {
            case .outline(_, let open), .app(let open): open
            }
        }
    }

    /// The open branches now. Read once for each flattening, and once for each
    /// key or click that opens or closes branches, so two keys handled before
    /// the next frame each see what the one before wrote.
    func read() -> Reading {
        switch store {
        case .outline(let box): .outline(ObjectIdentifier(box), box.value)
        case .app(let binding): .app(binding.wrappedValue)
        }
    }

    /// Opens or closes the branches `ids` name, in one write, and says whether
    /// any of them moved. The app's set is copied once, however many branches
    /// an Option-Right reaches, and not written at all where none moved, so an
    /// Option-Right on an open subtree asks for no frame.
    @discardableResult
    func set(_ ids: some Sequence<ID>, open: Bool) -> Bool {
        switch store {
        case .outline(let box):
            let before = box.value.count
            if open { box.value.formUnion(ids) } else { box.value.subtract(ids) }
            return box.value.count != before
        case .app(let binding):
            var set = binding.wrappedValue
            let before = set.count
            if open { set.formUnion(ids) } else { set.subtract(ids) }
            guard set.count != before else { return false }
            binding.wrappedValue = set
            return true
        }
    }
}
