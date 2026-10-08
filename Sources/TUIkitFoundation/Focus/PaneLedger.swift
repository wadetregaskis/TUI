//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaneLedger.swift
//
//  What the panes of the screen — the page, and a live sheet docked under it
//  (A19, design C) — post each frame, for the root to lay the page out by.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The focus manager's record of the screen's panes, kept frame by frame: the
/// dock each live sheet's presenter posts (`FocusManager.notePresentationDock`),
/// this walk's and the last frame's, and which pane each focus section is in
/// (`FocusManager.activePaneID`).
///
/// One value, rotated and emptied by the focus manager's pass hooks, with the
/// same current-and-previous shape as `presentationDismissals`.
struct PaneLedger {
    /// What a live sheet's presenter posts each frame: how many rows its sheet
    /// docked at the bottom of the content area takes from the page, and who
    /// posted it.
    struct PostedDock {
        /// The presenter's identity — to ask, should a frame docked by it not
        /// draw it, whether its own dock windowed it out
        /// (``noteDocksLeftUndrawn(windowedOut:)``).
        let presenter: ViewIdentity
        let resolver: PresentationDockResolver
    }

    /// The dock each sheet docked live posts, by its section: posted this walk.
    var docks: [String: PostedDock] = [:]

    /// ``docks`` as the previous frame left them: what the root asks, BEFORE
    /// the walk, how many rows to lay the page out short.
    private(set) var previousDocks: [String: PostedDock] = [:]

    /// The sections whose sheets docked the page this frame: the resolvers
    /// that answered rows when the root asked, before the walk
    /// (`FocusManager.presentationDock(in:storage:)`).
    var dockedBeforeTheWalk: Set<String> = []

    /// The sections whose sheet docked the page LAST frame and whose
    /// presenter that frame left out of a lazy container's window, for the
    /// presenters of this one to ask
    /// (`FocusManager.presenterWentUndrawnUnderItsDock(_:)`): what the last
    /// frame's last walk noted (``leftOutUnderTheirDock``), kept for every walk
    /// of this one.
    private(set) var undrawnUnderTheirDock: Set<String> = []

    /// The same, as THIS frame's walks note it after each walk
    /// (``noteDocksLeftUndrawn(windowedOut:)``) — the last walk's answer being
    /// the frame's, since it is the walk drawn. Apart from
    /// ``undrawnUnderTheirDock`` so that a frame walked twice does not answer
    /// its second walk's presenters with what its first walk noted about
    /// this frame: the presenter was drawn again in that walk alone, and
    /// asked too late.
    private var leftOutUnderTheirDock: Set<String> = []

    /// The pane whose content is rendering now, if any — see
    /// `FocusManager.beginPane(id:)`.
    var current: String?

    /// The pane each section registered in the last walk belongs to, a
    /// pane's own section included.
    var sectionPanes: [String: String] = [:]

    /// Keeps the frame before's posts as the previous frame's — at the start
    /// of a render pass, before the walk empties them.
    mutating func beginFrame() {
        previousDocks = docks
        if !dockedBeforeTheWalk.isEmpty { dockedBeforeTheWalk.removeAll() }
        if !undrawnUnderTheirDock.isEmpty || !leftOutUnderTheirDock.isEmpty {
            undrawnUnderTheirDock = leftOutUnderTheirDock
            leftOutUnderTheirDock.removeAll()
        }
    }

    /// Notes, after the walk, which of the sheets that docked the page this
    /// frame had their presenter pushed out by the dock: not drawn, so their
    /// docks were not posted again, and left out of a lazy container's window
    /// (`windowedOut`, asked of the presenter's identity) — which the page
    /// laid out short is what does.
    ///
    /// Only that. A presenter can post nothing for other reasons, and none of
    /// them says that docking again would push it out again: drawn into the
    /// throwaway backdrop of a `.modal`, a `.contextMenu` or a `.dimmed()`,
    /// which posts nothing; or not drawn at all for a frame — a tab, a
    /// navigation destination, a branch switched away and back between two
    /// frames, a disclosure group collapsed and opened again — inside a
    /// `List` or a lazy stack as much as anywhere else, which is why the
    /// question is about the presenter's ROW, not its ancestry. Counted, any
    /// of them held a live sheet off the dock for the rest of its
    /// presentation.
    mutating func noteDocksLeftUndrawn(windowedOut: (ViewIdentity) -> Bool) {
        guard !dockedBeforeTheWalk.isEmpty || !leftOutUnderTheirDock.isEmpty else { return }
        leftOutUnderTheirDock = dockedBeforeTheWalk.filter { id in
            guard docks[id] == nil, let posted = previousDocks[id] else { return false }
            return windowedOut(posted.presenter)
        }
    }

    /// Empties what a walk posts, before the walk re-posts it.
    mutating func beginWalk() {
        docks.removeAll()
        if !sectionPanes.isEmpty { sectionPanes.removeAll() }
        current = nil
    }

    /// Records that section `id`, registered now, is in the pane rendering
    /// now — if any is.
    mutating func noteSection(_ id: String) {
        if let current { sectionPanes[id] = current }
    }
}
