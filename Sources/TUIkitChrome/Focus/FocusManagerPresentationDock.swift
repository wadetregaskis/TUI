//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerPresentationDock.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

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
    package func notePresentationDock(
        id: String, presenter: ViewIdentity, resolver: @escaping PresentationDockResolver
    ) {
        postDock(inSection: id, presenter: presenter, resolver: resolver)
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
    ///
    /// Asking is also what makes this manager take docks at all
    /// (``noteDocksAreRead()``): a manager no root asks — a probe's, a
    /// snapshot's, a test host's — is posted none.
    @MainActor
    func presentationDock(in contentHeight: Int, storage: StateStorage?) -> Int {
        noteDocksAreRead()
        let dock = Self.dock(previouslyPostedDocks, in: contentHeight) { noteDockedBeforeTheWalk($0) }
        storage?.notesWindowedRows = anyDockedBeforeTheWalk
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
        Self.dock(postedDocks, in: contentHeight) { _ in }
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
    /// out — and of the drawing the walk kept, where it drew a subtree twice
    /// (a scroll view's band drawn again at the offset the frame settled on),
    /// whose first drawing's docks and row notes `RenderWalkCheckpoint` puts
    /// back. And asked of the ROW, not of the presenter's ancestry: one below a
    /// drawn `List` whose branch was not taken this frame, or whose disclosure
    /// group was collapsed, was not left out of the window, and docking again
    /// would not leave it out.
    @MainActor
    func settlePresentationDock(laidOutBy dock: Int, in contentHeight: Int, storage: StateStorage?) -> Bool {
        noteDocksLeftUndrawn { presenter in storage?.wasLeftOutOfAWindow(presenter) ?? false }
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
    package func presenterWentUndrawnUnderItsDock(_ id: String) -> Bool {
        isUndrawnUnderItsDock(id)
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
