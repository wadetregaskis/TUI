//  🖥️ TUI — A Terminal UI framework for Swift
//  KeptItemContents.swift
//
//  The content an `item:` presentation keeps for the items it was presented
//  for before the one it shows, for as long as it stays presented: the owner's
//  ruling SHEET-ITEM-STATE (2026-11-16).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// What a `sheet(item:)`, `fullScreenCover(item:)` or `popover(item:)` keeps
/// of the items it showed before the one it shows now, while it stays
/// presented: each one's content subtree, kept out of the pass's prune, and
/// where the focus was in it.
///
/// The item's id is its content's identity, so each item's content has its
/// own `@State`, scroll positions, selections and `@FocusState`. Switched from
/// item A to item B, A's content is no longer drawn — its `onDisappear` runs,
/// and B's starts fresh — but its state stays, so switched back, A is as it
/// was left, its `onAppear` and `task` run again as a tab's do when it comes
/// back into view, and the focus goes back to where it was in it. Dismissed
/// (the item `nil`), the presentation drops every item's state, so presented
/// again an item starts fresh. That is neither macOS's behaviour (one state
/// for every item: the content is handed the new item) nor what TUI did
/// before (each switch threw the item left behind away); the owner chose it.
///
/// Bounded by ``capacity``: past it, the item shown longest ago goes.
package struct KeptItemContents {
    /// How many items left behind keep their content's state.
    ///
    /// Each is retained every frame the presentation is up — a subtree root
    /// the prune index walks — and holds a whole content's state: an editor's
    /// text, a list's selection, a scroll position, an object a view made. A
    /// sheet following a list's selection as the arrow keys walk a thousand
    /// rows would otherwise keep a thousand editors. Sixteen covers going back
    /// and forth between a handful of items, which is what keeping them is
    /// for; one shown longer ago than that starts fresh, as every switched-to
    /// item did before the ruling.
    package static let capacity = 16

    /// An item left behind: its key, where its content was drawn, and the
    /// focus id of the control in it that held the focus when it was left.
    private struct Kept {
        let itemKey: String
        let identity: ViewIdentity
        let focusedID: String?
    }

    /// The items left behind, the one left longest ago first.
    private var kept: [Kept] = []

    package init() {}
}

@MainActor extension KeptItemContents {
    /// Notes that the presentation leaves the item it showed — `itemKey`,
    /// whose content was drawn at `identity` — for `next`, keeping that
    /// content's state and where the focus was in it; and, where `next` was
    /// left before and kept, sends the focus back to where it was in it.
    ///
    /// The render path only, at the start of the presenter's frame — before
    /// the content is drawn, while the focus manager still knows which
    /// control in the content left behind held the focus. Past ``capacity``,
    /// the item left longest ago goes, its state with it.
    ///
    /// - Parameters:
    ///   - itemKey: The key of the item left, or `nil` where none was shown.
    ///   - identity: Where the content of the item left was drawn, or `nil`
    ///     where it never was.
    ///   - next: The key of the item shown from this frame.
    ///   - context: The presenter's render context.
    package mutating func leave(
        _ itemKey: String?, drawnAt identity: ViewIdentity?, for next: String, context: RenderContext
    ) {
        let returning = kept.firstIndex { $0.itemKey == next }.map { kept.remove(at: $0) }
        if let itemKey, let identity {
            let focusManager = context.environment.focusManager
            kept.append(Kept(itemKey: itemKey, identity: identity, focusedID: Self.focus(in: identity, focusManager)))
            if kept.count > Self.capacity {
                context.stateStorage?.invalidateDescendants(of: kept.removeFirst().identity, includingItself: true)
            }
        } else if let identity {
            context.stateStorage?.invalidateDescendants(of: identity, includingItself: true)
        }
        // Asked for by id: the control registers later this frame, and the
        // focus manager takes it then (`FocusManager.focus(id:)`).
        if let focusedID = returning?.focusedID, let focusManager = context.environment.focusManager {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            focusManager.focus(id: focusedID)
        }
    }

    /// Keeps every item left behind out of this pass's prune: each content's
    /// own identity as well as what is below it, as a hidden tab's is kept
    /// (`StateStorage.retainSubtree(_:)` keeps only a root's strict
    /// descendants). Every frame the presentation is drawn, on the render
    /// path; a frame it is not drawn — its presenter gone from the tree —
    /// they are pruned with it.
    package func retain(in storage: StateStorage?) {
        guard let storage, !kept.isEmpty else { return }
        for item in kept {
            storage.markActive(item.identity)
            storage.retainSubtree(item.identity)
        }
    }

    /// Drops every item left behind, and its content's state: the
    /// presentation was dismissed, and presented again an item starts fresh.
    package mutating func dropAll(in storage: StateStorage?) {
        guard !kept.isEmpty else { return }
        for item in kept {
            storage?.invalidateDescendants(of: item.identity, includingItself: true)
        }
        kept.removeAll()
    }

    /// The focus id of the control holding the focus, where it is drawn in
    /// the content at `identity`.
    private static func focus(in identity: ViewIdentity, _ focusManager: FocusManager?) -> String? {
        guard let focusManager, let focused = focusManager.focusedIdentity,
            focused == identity || identity.isAncestor(of: focused)
        else { return nil }
        return focusManager.currentFocusedID
    }
}
