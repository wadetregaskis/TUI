//  🖥️ TUI — A Terminal UI framework for Swift
//  DragAndDropSession+HeldDrop.swift
//
//  A drop that waits for the frame that gathers a list's selection, and a
//  release that never came: how a pointer drag ends when its input does not
//  arrive in the order a frame at a time would see it. Its own file to keep
//  `DragAndDropSession.swift` within its length.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension DragAndDropSession {
    /// A pointer drag whose drop waits for the frame that may gather its
    /// selection (``awaitSelectionGathering()``).
    enum HeldDrop {
        /// No frame has been drawn since the drag began, and no release has
        /// come.
        case awaitingFrame

        /// The release came before that frame, and waits for it.
        case release(MouseEvent)

        /// The release waiting, if it has come.
        var release: MouseEvent? {
            if case .release(let event) = self { return event }
            return nil
        }
    }

    /// Marks the drag in flight as one a container may gather a selection for
    /// on the frame after it began — a `.draggable` drawn in a `List` row —
    /// so a drop that comes before that frame waits for it (``performDrop()``).
    ///
    /// A list learns its selected rows' payloads only by drawing them, and the
    /// run loop reads every input waiting before it draws: a drag read in one
    /// batch with its release, on a slow frame or a link that delivers the
    /// reports together, dropped the grabbed row alone and left the rest of
    /// the selection, against the owner's ruling DRAG-SELECTION (hunt DND-6).
    /// A `Table` gathers as the drag begins and needs no wait.
    package func awaitSelectionGathering() {
        guard active != nil else { return }
        heldDrop = .awaitingFrame
    }

    /// Holds the release of `drag`, at ``lastAbsoluteEvent``, if its drop waits
    /// for the frame that gathers its selection: one marked
    /// (``awaitSelectionGathering()``) that has gathered nothing yet, and a
    /// pointer's — a carry's drop is the keyboard's, read a key at a time.
    ///
    /// - Returns: Whether the release is held.
    func holdsRelease(of drag: ActiveDrag) -> Bool {
        guard heldDrop != nil, !drag.carriesSelection, carry == nil, !isDroppingCarry,
            let release = lastAbsoluteEvent
        else { return false }
        heldDrop = .release(release)
        return true
    }

    /// Drops a release held for the frame that gathers its drag's selection,
    /// now that a frame has been drawn: at the end of every frame, as its
    /// regions are published (``MouseEventDispatcher/setRegions(_:)``). After
    /// that frame no drop of the drag waits.
    ///
    /// - Returns: Whether a held drop was performed, so the frame that draws
    ///   it is owed.
    package func dropHeldRelease() -> Bool {
        guard let held = heldDrop else { return false }
        heldDrop = nil
        guard active != nil, let release = held.release else { return false }
        drop(at: release)
        return true
    }

    /// Ends a pointer drag whose release was lost, as a press arrives with it
    /// in flight (`MouseEventDispatcher.supersedeLostDrag()`): a release held
    /// for its gathering frame did arrive, and drops now, ahead of the press;
    /// any other ends as a release over nothing does
    /// (``cancelForLostMouseReporting()``).
    package func supersedeLostRelease() {
        if heldDrop?.release != nil {
            _ = dropHeldRelease()
        } else {
            cancelForLostMouseReporting()
        }
    }
}
