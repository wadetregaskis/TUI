//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerPresentedSection.swift
//
//  How a presented surface keeps its focus section active from frame to frame
//  without taking the focus back from a surface presented on top of it. The
//  transition itself lives in `Focus.swift`, beside the focus state it moves.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Activates a presented surface's focus section — a sheet's, an alert's, a
    /// popover's, an open menu's — which its presenter asks for on EVERY frame
    /// the surface is up.
    ///
    /// `activateSection(id:focusBoundary:)` is a transition, not an assertion:
    /// it remembers the section it leaves, drops the focus, and restores this
    /// section's memory. Asked for every frame, that is harmless only while this
    /// section is already the active one — true of a single presentation, and
    /// false the moment a second surface is presented from INSIDE the first: an
    /// alert confirming a button in a sheet, a sheet or menu opened in a
    /// popover. The outer presenter renders first. It found the inner surface's
    /// section active from the frame before and transitioned back to itself;
    /// its section had not been re-populated yet this pass, so nothing was
    /// restored and the focus went to nil. The inner presenter then transitioned
    /// back again, and its first control re-registered into that empty focus and
    /// took it. Tab inside the inner surface could never leave its first
    /// control, a text field in it was torn down and restarted every frame,
    /// dismissing it left the outer surface on its FIRST control rather than
    /// the one that opened it, and each transition's `onFocusChange` asked for
    /// another frame, so the loop never idled while both were up.
    ///
    /// Not "activate once, on presentation", which is how `NavigationStack`
    /// answers the same defect on a push. A presenter has no reliable "just
    /// presented": one whose binding turned true while an alert on the same view
    /// was up rendered into that alert's throwaway backdrop focus manager, and
    /// must claim the real one on the frame the alert goes. So everything
    /// holding the active section is still overridden, as before — a presented
    /// surface owns the focus — EXCEPT a surface presented on top of this one,
    /// directly or through a chain of surfaces each presented from inside the
    /// last. That surface hands the focus back down itself when it is dismissed
    /// (`deactivateSection(id:)` reverts to exactly the section it was activated
    /// over), so taking it back here is only ever wrong.
    ///
    /// ## Only through presented surfaces
    ///
    /// The chain is `sectionRevertTarget`, walked down from the active section —
    /// but that table records EVERY activation, not only presentations: Tab
    /// cycling between sections and a `NavigationStack` push write it too.
    /// Followed through those, a Tab that wrapped out of a screen pushed inside a
    /// sheet onto a control beside the sheet's presenter left a chain leading
    /// back to the sheet, the sheet stopped reclaiming its section, and the focus
    /// stayed behind the modal for good. So the walk passes only through sections
    /// that were marked modal, which every presenter does every frame, and stops
    /// at the first that was not.
    ///
    /// Marked on the PREVIOUS frame (``previousModalSectionIDs``): the surface on
    /// top renders later in this pass than its presenter, so its mark for this
    /// frame does not exist yet. One that left the tree without being dismissed
    /// is dropped by `endRenderPass` as a vanished active section, and this
    /// presenter reclaims the section on the next frame if that fallback chose
    /// another.
    ///
    /// NOT fixed by this: a non-modal section activated INSIDE a presented
    /// surface — a push, a split view's column click — is still taken back by
    /// the surface's presenter on the next frame.
    func activatePresentedSection(id: String) {
        if var section = activeSectionIdentifier, section != id {
            // Bounded by the table's size rather than by reaching a root: the
            // table is pruned only on dismissal, and nothing stops it holding a
            // cycle of modal sections an unbounded walk would never leave.
            var remaining = sectionRevertTarget.count
            while remaining > 0, previousModalSectionIDs.contains(section),
                let below = sectionRevertTarget[section]
            {
                if below == id { return }
                section = below
                remaining -= 1
            }
        }
        activateSection(id: id)
    }

    /// Posts how to close the surface presented in section `id` — asked by a
    /// presenter every frame it draws the surface, as it marks the section
    /// modal.
    ///
    /// For the frame after one where it was NOT drawn: its presenter went
    /// undrawn — a row a lazy stack or a list left out of its window, when a
    /// document arrived above it — so its section vanished and
    /// ``endRenderPass()`` handed the focus back to the page. The surface has to
    /// close then, as well. Its open state lives with the presenter, which
    /// nothing drew to close it, so it came back when the row did, taking the
    /// keyboard from wherever it had gone.
    func notePresentation(id: String, dismiss: @escaping () -> Void) {
        presentationDismissals[id] = dismiss
    }

    /// Closes the surface presented in section `id` last frame and not drawn
    /// in this one (see ``notePresentation(id:dismiss:)``). Called by
    /// ``endRenderPass()`` for the active section it finds gone.
    func closeUndrawnPresentation(id: String) {
        guard presentationDismissals[id] == nil, let dismiss = previousPresentationDismissals[id] else { return }
        previousPresentationDismissals[id] = nil
        dismiss()
    }
}

// MARK: - The dock

/// How many rows a sheet docked live at the bottom of a content area
/// `contentHeight` rows tall takes from the page, or `nil` while it is not
/// docked — dismissed, or presented as a modal over the whole page.
///
/// Asked outside the walk, so it reads what decides the answer — the
/// presentation binding, the detent the sheet rests at — when it is called,
/// not when it was posted: a key that moves the sheet between two frames is
/// answered by last frame's resolver already, and never draws late.
typealias PresentationDockResolver = @MainActor (_ contentHeight: Int) -> Int?

extension FocusManager {
    /// Posts how many rows the sheet presented in section `id` docks at the
    /// bottom of the content area — asked by its presenter every frame it is
    /// drawn.
    ///
    /// The page behind a live sheet is laid out in the rows above it (the
    /// owner's split-view reading of A19's design C), so the page's height
    /// depends on a presentation declared INSIDE the page. Learnt by walking
    /// the tree, that is the circularity a piece of chrome must not have: the
    /// walk that learns it was laid out at the wrong height, and has to be
    /// thrown away. So the presenter posts a resolver instead, and the root
    /// asks LAST frame's resolvers, before it lays the page out
    /// (``presentationDock(in:storage:)``) — one walk, at a height known in advance.
    /// The same current-and-previous shape as ``notePresentation(id:dismiss:)``.
    ///
    /// - Parameters:
    ///   - id: The sheet's focus section.
    ///   - presenter: The presenter's identity, for the frame after one that
    ///     docked it and did not draw it to ask why
    ///     (``settlePresentationDock(laidOutBy:in:storage:)``).
    ///   - resolver: The rows the sheet docks, asked before the next walk.
    func notePresentationDock(
        id: String, presenter: ViewIdentity, resolver: @escaping PresentationDockResolver
    ) {
        panes.docks[id] = PaneLedger.PostedDock(presenter: presenter, resolver: resolver)
    }

    /// The rows a content area `contentHeight` rows tall gives up at its
    /// bottom, by the resolvers LAST frame posted: what the root lays the page
    /// out short by, before the walk.
    ///
    /// The most any one sheet asks for: two docked sheets overlap on the bottom
    /// edge, and the taller decides how much of the page is covered.
    ///
    /// Asked on EVERY walk of a frame, before its content — a `.global`
    /// reader's correction walks twice — and the same each time: it reads
    /// last frame's posts, which no walk of this one touches.
    ///
    /// Notes which sheets docked it (``PaneLedger/dockedBeforeTheWalk``), for
    /// ``settlePresentationDock(laidOutBy:in:storage:)`` to find the ones whose
    /// presenters the frame then did not draw — and, when any did, has the
    /// walk's windowing containers note which rows they draw (`storage`'s
    /// ``StateStorage/notesWindowedRows``), for the settle to ask whether a
    /// presenter it did not draw was left out of a window.
    @MainActor
    func presentationDock(in contentHeight: Int, storage: StateStorage?) -> Int {
        let dock = Self.dock(panes.previousDocks, in: contentHeight) { panes.dockedBeforeTheWalk.insert($0) }
        storage?.notesWindowedRows = !panes.dockedBeforeTheWalk.isEmpty
        return dock
    }

    /// The same, by the resolvers posted THIS frame: what the root compares
    /// with ``presentationDock(in:storage:)`` after the walk.
    ///
    /// Different when the dock was learnt late — a presenter's first drawn
    /// frame, a sheet presented for an item whose content was unknown until
    /// it opened — and that frame was laid out at the old dock, the sheet
    /// drawn over the page's bottom rows; or when a sheet's presenter was not
    /// drawn, its page gone or its row out of a lazy window. The root then
    /// asks for the next frame, which settles: one frame late, not a
    /// discarded walk.
    @MainActor
    func postedPresentationDock(in contentHeight: Int) -> Int {
        Self.dock(panes.docks, in: contentHeight) { _ in }
    }

    /// After the walk, whether the next frame must be laid out at another
    /// dock than this one was (`dock`): see ``postedPresentationDock(in:)``.
    ///
    /// And notes the sheets that docked this frame whose presenters it left
    /// out of a lazy container's window, for their presenters to find on the
    /// next (``presenterWentUndrawnUnderItsDock(_:)``): a presenter that
    /// posted nothing in this walk, lying in a row that a container windowing
    /// its rows did not draw in it (`storage`'s
    /// ``StateStorage/wasLeftOutOfAWindow(_:)``, which this walk's containers
    /// noted because a sheet docked it — ``presentationDock(in:storage:)``).
    ///
    /// Asked of THIS walk: a frame walked twice draws only its last, so a
    /// presenter an earlier walk drew and the drawn walk left out was left
    /// out. And asked of the ROW, not of the presenter's ancestry: one below a
    /// drawn `List` whose branch was not taken this frame, or whose disclosure
    /// group was collapsed, was not left out of the window, and docking again
    /// would not leave it out.
    @MainActor
    func settlePresentationDock(laidOutBy dock: Int, in contentHeight: Int, storage: StateStorage?) -> Bool {
        panes.noteDocksLeftUndrawn { presenter in storage?.wasLeftOutOfAWindow(presenter) ?? false }
        return postedPresentationDock(in: contentHeight) != dock
    }

    /// Whether the sheet presented in section `id` docked the page last
    /// frame and that frame left its presenter out of a lazy container's
    /// window.
    ///
    /// A presenter drawn now that was windowed out then was pushed out by the
    /// frame it docked — a row of a lazy stack or a list that the page, laid
    /// out short by the sheet, left out of its window. Docked again, the row
    /// would leave the window again, the sheet with it, and the page would
    /// grow back: the two alternated every frame, the app never idled, and the
    /// sheet lost the focus for good.
    func presenterWentUndrawnUnderItsDock(_ id: String) -> Bool {
        panes.undrawnUnderTheirDock.contains(id)
    }

    /// The most `resolvers` dock in a content area `contentHeight` rows tall,
    /// each section that docks any handed to `docked`.
    @MainActor
    private static func dock(
        _ resolvers: [String: PaneLedger.PostedDock], in contentHeight: Int, docked: (String) -> Void
    ) -> Int {
        // The common frame: no live sheet anywhere.
        guard !resolvers.isEmpty, contentHeight > 0 else { return 0 }
        var dock = 0
        for (id, posted) in resolvers {
            guard let rows = posted.resolver(contentHeight) else { continue }
            dock = max(dock, rows)
            docked(id)
        }
        return min(dock, contentHeight)
    }
}
