//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusedValueRegistry.swift
//
//  What `.focusedValue(_:_:)` and `.focusedSceneValue(_:_:)` publish, kept
//  across frames on the focus manager, and what `@FocusedValue` reads back for
//  wherever the focus is.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// The focused-value tables published this frame and last, and the reading
/// of them for a focus location.
///
/// ## Which value a reader sees
///
/// A value published with `.focusedValue` is seen while the focus is on the
/// publishing view or inside it; one published with `.focusedSceneValue` is
/// seen wherever the focus is. Where several publish one key, the one closest
/// to the focus wins — the deepest publisher on the focus's path — and failing
/// any on the path, the scene value published first in the tree.
///
/// ## Why last frame's tables, and the second frame
///
/// A reader is usually NOT an ancestor of the focused control — a detail pane
/// beside a list, a status line above it — so it may render before the view
/// that publishes what it reads. A table filled only by this frame's walk would
/// read empty to every reader drawn ahead of its publisher. So a read answers
/// from this walk's tables where the publisher has posted, and from last
/// frame's where it has not yet.
///
/// That is right unless a publisher's value changed this frame after a reader
/// read the old one. Every table handed to a reader during a render is kept,
/// and at the end of the pass the reading is repeated against the frame's
/// final tables and focus: if any differs, ``requestFrame`` asks for one more
/// frame, which reads what this one published. A value that cannot be compared
/// (a closure, a `Binding`) counts as unchanged while the same view publishes
/// it — so the check cannot ask for frames forever over a closure rebuilt each
/// render — and it is read through at the moment it is used anyway.
package final class FocusedValueRegistry {
    /// One modifier's publication. Two modifiers on one view render at one
    /// identity, so a publication is keyed by its kind as well.
    private struct Key: Hashable {
        let identity: ViewIdentity
        let isScene: Bool
    }

    private struct Publication {
        let table: FocusedValues
        let identity: ViewIdentity
        let isScene: Bool
        /// The order it was published in, within its walk.
        let order: Int
    }

    /// The last pass's final walk.
    private var previous: [Key: Publication] = [:]

    /// This walk's, so far.
    private var current: [Key: Publication] = [:]

    /// Publications made so far this walk.
    private var order = 0

    /// Whether a walk is in progress: a read outside one (an event closure)
    /// is not kept for the end-of-pass check.
    private var isRendering = false

    /// The tables handed to readers this walk, each kept once in a row.
    private var reads: [FocusedValues] = []

    /// Asks the app for another frame. Wired by the run loop; a test drives
    /// its own frames.
    package var requestFrame: (() -> Void)? { get { _requestFrame } set { _requestFrame = newValue } }

    /// ``requestFrame``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _requestFrame: (() -> Void)?

    /// Starts a walk of the view tree: what it publishes replaces, view by
    /// view, what the last pass published.
    func beginWalk() {
        current.removeAll(keepingCapacity: true)
        reads.removeAll(keepingCapacity: true)
        order = 0
        isRendering = true
    }

    /// Records `table`, published by the modifier rendered at `identity`.
    ///
    /// Two modifiers of one kind on one view meet here at one identity; the
    /// later of them is the inner one, nearer the view, and its value for a
    /// key both name wins.
    func post(_ table: FocusedValues, by identity: ViewIdentity, isScene: Bool) {
        guard !table.isEmpty else { return }
        let key = Key(identity: identity, isScene: isScene)
        let stamped = table.published(by: identity)
        if let existing = current[key] {
            var merged = existing.table
            merged.overlay(stamped)
            current[key] = Publication(
                table: merged, identity: identity, isScene: isScene, order: existing.order)
        } else {
            order += 1
            current[key] = Publication(
                table: stamped, identity: identity, isScene: isScene, order: order)
        }
    }

    /// The values a reader sees with the focus at `focused`.
    func table(focusedAt focused: ViewIdentity?) -> FocusedValues {
        let table = resolve(focusedAt: focused)
        if isRendering, reads.last != table { reads.append(table) }
        return table
    }

    /// Ends the pass: keeps what its last walk published, and asks for one
    /// more frame if a reader was handed something the frame then changed.
    func endPass(focusedAt focused: ViewIdentity?) {
        isRendering = false
        let final = resolve(focusedAt: focused)
        let stale = reads.contains { $0 != final }
        previous = current
        current = [:]
        reads.removeAll()
        if stale { requestFrame?() }
    }

    /// The reading itself — see the type's notes.
    private func resolve(focusedAt focused: ViewIdentity?) -> FocusedValues {
        var publications = previous
        publications.merge(current) { _, new in new }
        var table = FocusedValues()
        guard !publications.isEmpty else { return table }
        // Scene values, the first published winning: overlaid last to first.
        for publication in publications.values.filter(\.isScene).sorted(by: { $0.order > $1.order }) {
            table.overlay(publication.table)
        }
        guard let focused else { return table }
        // The focus's path, outermost first so the innermost wins; at one
        // identity a focused value over a scene value.
        let path = publications.values.filter {
            $0.identity == focused || $0.identity.isAncestor(of: focused)
        }
        for publication in path.sorted(by: Self.outermostFirst) {
            table.overlay(publication.table)
        }
        return table
    }

    private static func outermostFirst(_ lhs: Publication, _ rhs: Publication) -> Bool {
        if lhs.identity.depth != rhs.identity.depth { return lhs.identity.depth < rhs.identity.depth }
        return lhs.isScene && !rhs.isScene
    }
}
