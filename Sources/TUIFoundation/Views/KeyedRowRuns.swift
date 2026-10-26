//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyedRowRuns.swift
//
//  Where a flattened container's keyed rows come from: the walk of its content
//  that finds each loop and outline in the order the splice emits their rows,
//  for `FlattenedRowIDs` to place them. Split out of `FlattenedRowIDs.swift`,
//  which had passed the file-length guideline.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Where keyed rows come from

/// One provider's share of a flattened container's KEYED children, in the
/// order the splice emits them.
@MainActor
package enum KeyedRowRun {
    /// A `ForEach`'s rows, each keyed by its element: `rowsPerElement` of them
    /// from every element — one, or a row's several views (decisions B15) —
    /// or, `nil`, as many as each element's row makes, placed by their keys.
    case loop(any KeyedLoop, rowsPerElement: Int?)
    /// An `OutlineGroup`'s rows: one per VISIBLE node, which only the outline's
    /// expansion state knows — so the run is recognised by its rows' type
    /// rather than counted. They keep the hand-written rule.
    case outline
    /// A provider this walk cannot see into, whose children may be keyed and
    /// cannot be counted — `MenuStyleConfiguration.Content`, or one added
    /// after this was written. They keep the hand-written rule.
    case opaque

    var isLoop: Bool {
        if case .loop = self { return true }
        return false
    }
}

/// The runs a walk of a container's content finds, in order, each with the
/// static slot of the content's OUTERMOST tuple it was found in — the slot the
/// splice stamps on the keyed rows it hands over (`ChildView.spliceSlot`) —
/// or `nil` for one found outside any tuple.
@MainActor
package struct KeyedRowRuns {
    /// The runs, in the order the splice emits their rows.
    private(set) var runs: [KeyedRowRun] = []

    /// Each run's slot, by its index in ``runs``.
    private(set) var slots: [Int?] = []

    /// The slot of the outermost tuple the walk is in now, `nil` while it is
    /// in none.
    fileprivate var slot: Int?

    /// Appends `run`, found in the slot the walk is in now.
    package mutating func append(_ run: KeyedRowRun) {
        runs.append(run)
        slots.append(slot)
    }
}

/// A loop, asked about its rows by the element that made them.
@MainActor
package protocol KeyedLoop {
    /// How many elements the loop iterates.
    var keyedElementCount: Int { get }

    /// The key every row the `element`-th element makes carries — its
    /// `identityChildKey`.
    func keyedRowKey(ofElement element: Int) -> String

    /// What the `element`-th element's rows name themselves when the loop is
    /// its container's whole content, without the index fallback.
    func keyedRowSelectionID<RowID: Hashable>(ofElement element: Int) -> RowID?

    /// The `id` of the `element`-th element.
    func keyedRowElementID(ofElement element: Int) -> AnyHashable
}

/// A view that flattens keyed rows into its container, or passes another's
/// through — `ForEach`, `OutlineGroup`, and the providers between them and the
/// container.
///
/// The shape a `Picker`'s options and a text field's suggestions were read in
/// until they moved to the member resolution, asked a different question. The
/// wrappers that pass a provider's members through by ``ContentRewrapping`` or
/// as a `ModifiedView` need no conformance: ``appendKeyedRowRuns(of:to:)``
/// looks through every ``SingleContentWrapper`` that is also a
/// ``ChildViewProvider``, which is exactly when the splice does.
@MainActor
package protocol KeyedRowProvider {
    /// Appends the runs of keyed rows this view flattens, in order — with each
    /// `Section` kept whole when `sectionsWhole`, as the walk that flattened
    /// the children did (`RenderContext.keepsSectionsWhole`).
    func appendKeyedRowRuns(to runs: inout KeyedRowRuns, sectionsWhole: Bool)
}

/// Appends the runs of keyed rows `view` flattens into its container, going
/// exactly where `resolveChildViews` flattens and nowhere else.
///
/// A view that is no provider is ONE child of its container, and a positional
/// one, so it adds nothing — `.onAppear` on a loop keeps the loop as one opaque
/// row, exactly as the splice does. A single-content wrapper is looked through
/// only when it is itself a provider: `.foregroundStyle` hands a loop's rows
/// out one by one. Any other provider is a run of its own that cannot be
/// counted.
@MainActor
func appendKeyedRowRuns<V: View>(of view: V, to runs: inout KeyedRowRuns, sectionsWhole: Bool) {
    if let provider = view as? KeyedRowProvider {
        provider.appendKeyedRowRuns(to: &runs, sectionsWhole: sectionsWhole)
        return
    }
    guard view is ChildViewProvider else {
        // A view of the app's own taken apart into its body's views
        // (`compositeMembers(of:context:)`) may hand over a loop's keyed rows,
        // which only its body, evaluated, can say: a run that cannot be counted.
        // Unless its body's type holds no loop — a heading, a pair of rows —
        // or none the container is handed, its loop in a section the walk
        // keeps whole (a body that is a `Section` of a loop, in a `List`): it
        // hands over none, and is no run at all. Counted as one, two of them
        // around a loop in one slot left the loop unplaced.
        if isCompositeHandingOverChildren(V.self), mayHandOver(.keyedRow(sectionsWhole: sectionsWhole), V.self) {
            runs.append(.opaque)
        }
        return
    }
    if let wrapper = view as? any SingleContentWrapper {
        appendKeyedRowRuns(of: wrapper.wrappedContent, to: &runs, sectionsWhole: sectionsWhole)
    } else {
        runs.append(.opaque)
    }
}

/// A tuple's runs, each in its slot: the outermost tuple's slot is the one
/// its splice stamps on what each slot hands over, over any inner tuple's.
extension TupleView: KeyedRowProvider {
    package func appendKeyedRowRuns(to runs: inout KeyedRowRuns, sectionsWhole: Bool) {
        let outermost = runs.slot == nil
        var slot = 0
        for child in repeat each children {
            if outermost { runs.slot = slot }
            TUIFoundation.appendKeyedRowRuns(of: child, to: &runs, sectionsWhole: sectionsWhole)
            slot += 1
        }
        if outermost { runs.slot = nil }
    }
}

extension Group: KeyedRowProvider where Content: View {
    package func appendKeyedRowRuns(to runs: inout KeyedRowRuns, sectionsWhole: Bool) {
        TUIFoundation.appendKeyedRowRuns(of: content, to: &runs, sectionsWhole: sectionsWhole)
    }
}

extension ConditionalView: KeyedRowProvider {
    package func appendKeyedRowRuns(to runs: inout KeyedRowRuns, sectionsWhole: Bool) {
        switch self {
        case .trueContent(let content):
            TUIFoundation.appendKeyedRowRuns(of: content, to: &runs, sectionsWhole: sectionsWhole)
        case .falseContent(let content):
            TUIFoundation.appendKeyedRowRuns(of: content, to: &runs, sectionsWhole: sectionsWhole)
        }
    }
}

/// An `AnyView` hands its container what it erases, taken apart where that is
/// several views, so the loops in it are runs of the container's.
extension AnyView: KeyedRowProvider {
    package func appendKeyedRowRuns(to runs: inout KeyedRowRuns, sectionsWhole: Bool) {
        TUIFoundation.appendKeyedRowRuns(of: erasedView, to: &runs, sectionsWhole: sectionsWhole)
    }
}

extension Optional: KeyedRowProvider where Wrapped: View {
    package func appendKeyedRowRuns(to runs: inout KeyedRowRuns, sectionsWhole: Bool) {
        // A `nil` still leaving keeps a slot in its container (see
        // `Optional.childViews`), but a positional one: no keyed row.
        if case .some(let wrapped) = self {
            TUIFoundation.appendKeyedRowRuns(of: wrapped, to: &runs, sectionsWhole: sectionsWhole)
        }
    }
}

/// A section is its parts' children to a walk that takes it apart, so its
/// parts' loops are runs of the container's; kept whole, it is one positional
/// child and makes none. A collapsed section's content makes none either.
extension Section: KeyedRowProvider where Parent: View, Content: View, Footer: View {
    package func appendKeyedRowRuns(to runs: inout KeyedRowRuns, sectionsWhole: Bool) {
        guard !sectionsWhole else { return }
        TUIFoundation.appendKeyedRowRuns(of: header, to: &runs, sectionsWhole: false)
        if showsContent { TUIFoundation.appendKeyedRowRuns(of: content, to: &runs, sectionsWhole: false) }
        TUIFoundation.appendKeyedRowRuns(of: footer, to: &runs, sectionsWhole: false)
    }
}
