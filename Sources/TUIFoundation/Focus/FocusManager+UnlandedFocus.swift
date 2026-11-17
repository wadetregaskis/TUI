//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManager+UnlandedFocus.swift
//
//  The views that drew while the focus had not landed anywhere, and so
//  answered "is the focus in me" with what they last knew: dropped from the
//  render cache when the focus lands somewhere that answer was wrong for,
//  which the move itself may not name.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Notes that the view at `identity` drew from what it last knew of the
    /// focus — `within`, whether it took the focus to be inside it — because
    /// the focus had not landed: nothing held it, or the control holding it
    /// had not been drawn since the manager last swept where controls are
    /// (``focusedIdentity`` is `nil`).
    ///
    /// What it drew is right for now, and cached as any drawing is. It stops
    /// being right when the focus lands where `within` says it is not, and the
    /// move that lands it drops the cached drawings of the controls at either
    /// end of it — which, from no focus, is only the control it lands on. A
    /// `List` under a popover presented again drew its rows beside its
    /// scrollbar on the frame the popover came back, as it had while it held
    /// the focus; the Tab into the popover landed the focus on its first
    /// control, and the list's stored drawing was served with the bar and its
    /// rows a cell narrower, on every frame after (PERFCASE-F13). So the move
    /// drops these too, where they were wrong (``dropDrawingsAwaitingFocus()``).
    ///
    /// Not under a backdrop's throwaway manager, whose focus never lands.
    /// Bounded by the scrolling views drawn before the focus lands, which the
    /// next move empties.
    package func noteDrawnAwaitingFocus(_ identity: ViewIdentity, takingFocusWithin within: Bool) {
        guard !isBackdrop else { return }
        drawnAwaitingFocus[identity] = within
    }

    /// Drops the cached drawings of the views noted by
    /// ``noteDrawnAwaitingFocus(_:takingFocusWithin:)`` that were wrong about
    /// where the focus now is, and those containing them: at once, as a focus
    /// move's own drop is, so a memo still rendering above one declines to
    /// store what it drew.
    ///
    /// Where the focus has landed is the focused control's identity, where it
    /// last registered. A view it landed in is dropped already, as the move's
    /// destination's ancestor, and one that took it to be elsewhere drew what
    /// is still right; both are left alone. Where the control has not
    /// registered since the last sweep, nothing can say, and every view noted
    /// goes. Not their descendants: what such a view decides from the focus is
    /// its own layout (where its indicators go), and its content drawn for
    /// another layout misses on its size. Nor their sizes kept: the layout is
    /// what changes.
    func dropDrawingsAwaitingFocus() {
        guard !drawnAwaitingFocus.isEmpty else { return }
        let landed = focusedIdentity
        let cache = renderCacheHandle?.cache
        for (identity, within) in drawnAwaitingFocus {
            if let landed, identity == landed || identity.isAncestor(of: landed) || !within { continue }
            cache?.clearAffected(by: identity, includingDescendants: false)
        }
        drawnAwaitingFocus.removeAll(keepingCapacity: true)
    }
}
