//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollPlacing.swift
//
//  The containers SCROLL-FIT's pull passes through (design B-SCROLLFIT-12):
//  each hands a scroll view's request on to the child it leads to, in that
//  child's lines, and places what the child draws in its own.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A container that places its children against a scroll view's request,
/// handing the request on to the children that are pulled (SCROLL-FIT design
/// B-SCROLLFIT-12): a column outward from an anchor (`_VStackCore`,
/// `StackPulledColumn.swift`), and the containers the later lanes make pull.
///
/// A marker, read by type from the identity chain: a lazy stack is pulled only
/// where every container that holds it among siblings conforms — or, for an
/// app's `Layout`, which has no identity of its own, is filed as placing
/// (`PullConsumers.noteLayout(_:places:)`) —
/// (`_VStackCore.isPulledWhereItStands(context:)`), which its measure knows
/// before any request arrives; below any other it is drawn whole
/// (B-SCROLLFIT-13). Nothing is asked of a conformer through it — each shape
/// (column, parallel, forward) reads and answers the request in its own
/// render — so it neither refines `LayoutPlacing` nor asks for a method:
/// a container that pulls need not be one a placement query can walk.
/// Package-wide, for the containers outside this module (`TabView`,
/// `NavigationStack`).
@MainActor
package protocol ScrollPlacing {}

@MainActor extension RenderContext {
    /// Files the container at this context's identity as one that holds a
    /// pulled view (`PullConsumers.Kind.pullsChildren`) — one below any of
    /// `children`, the identities its measure has just measured — or
    /// withdraws it: a column above hands such a container a request, which
    /// it hands on. Only in scroll content, where there is a request to pull
    /// by, and only once something is filed at all, which on most pages
    /// nothing ever is. Says whether it filed it.
    @discardableResult
    package func notePulledContainer(holding children: () -> [ViewIdentity]) -> Bool {
        guard scrollContentOriginDepth != 0, let cache = renderCache else { return false }
        let holds = !cache.pullConsumers.isEmpty && children().contains { cache.pullConsumers.holdsConsumer(below: $0) }
        cache.pullConsumers.note(identity, as: holds ? .pullsChildren : nil)
        return holds
    }

    /// This context with `request` in it for the pulled child at `identity`,
    /// which was handed `last` on the frame before.
    ///
    /// A memo between the container and what reads the request keys on no
    /// part of it — a `ForEach` row's trusts the environment its subtree
    /// noted, and a request is noted by no one — so a child handed a request
    /// other than the last frame's has its memo entries dropped, buffers only:
    /// a request moves which of the child's lines are drawn, never its size.
    /// One handed the same request (an idle frame, a child off the band) keeps
    /// them, and its reply is said again from the memo's journal.
    func handingPulled(
        _ request: ScrollContentWindow, to identity: ViewIdentity, last: ScrollContentWindow?
    ) -> RenderContext {
        if last != request {
            renderCache?.clearAffected(by: identity, keepingSizes: true)
        }
        var handed = self
        handed.environment.scrollContentWindow = request
        return handed
    }
}
