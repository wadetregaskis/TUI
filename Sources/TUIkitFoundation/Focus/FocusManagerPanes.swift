//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerPanes.swift
//
//  Panes: parts of the screen that share the keyboard, each holding it while
//  the focus is inside it — a live sheet docked under the page it was
//  presented over (A19, design C). The channels the framework once assumed
//  were the whole screen's — `.keyboardShortcut`, the claim on Escape — are
//  the active pane's.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// The pane whose content is rendering now, if any — see
    /// ``beginPane(id:)``.
    package var currentPaneID: String? { panes.current }

    /// Starts rendering the content of pane `id`: the sections registered
    /// until ``endPane(restoring:)`` are the pane's, and so are the claims on
    /// Escape made meanwhile (`StatusBarState.claimEscape(_:)`).
    ///
    /// - Returns: The pane this one is rendered inside, if any, to hand back
    ///   to ``endPane(restoring:)``.
    package func beginPane(id: String) -> String? {
        let outer = panes.current
        panes.current = id
        panes.sectionPanes[id] = id
        return outer
    }

    /// Ends the pane ``beginPane(id:)`` began, back in `outer`.
    package func endPane(restoring outer: String?) {
        panes.current = outer
    }

    /// The pane the focus is in: the one the active section belongs to, or
    /// `nil` while it is on the page outside every pane — always, where no
    /// pane is drawn.
    ///
    /// A section's pane is known from the walk that registered it, so this is
    /// the last walk's answer between frames, when keys arrive.
    package var activePaneID: String? {
        guard !panes.sectionPanes.isEmpty, let activeSectionID = activeSectionIdentifier else { return nil }
        return panes.sectionPanes[activeSectionID]
    }
}

// The ledger's docks, for the presentation dock that TUIkitChrome lays the
// page out by (its FocusManagerPresentationDock.swift). Methods, not `panes`
// itself: a class's stored property that another module can see keeps a
// run-time exclusivity check on every access, and a `package` accessor over
// the whole ledger would copy its dictionaries at each write through it
// (CONTRIBUTING.md, "Crossing a module boundary").
extension FocusManager {
    /// Posts the dock of the sheet presented in section `id`, for this walk:
    /// the ledger's ``PaneLedger/docks``.
    package func postDock(
        inSection id: String, presenter: ViewIdentity, resolver: @escaping PresentationDockResolver
    ) {
        panes.docks[id] = PaneLedger.PostedDock(presenter: presenter, resolver: resolver)
    }

    /// Forgets every dock posted, for a loop that has drawn its last frame.
    ///
    /// A dock's resolver is kept for the frame after the one that posted it,
    /// and it holds what its sheet's presenter handed it: the presentation's
    /// binding and the closure that builds its content. Every sheet posts
    /// one, dismissed or not, and a binding or a content closure may reach
    /// the environment — a scene presenter's binding does — and so this focus
    /// manager: after the last frame, nothing replaced them, and the focus
    /// manager, and every service the environment reaches, outlived the app.
    package func forgetPresentationDocks() {
        panes.forgetDocks()
    }

    /// The docks this walk posted (``PaneLedger/docks``).
    package var postedDocks: [String: PaneLedger.PostedDock] { panes.docks }

    /// The docks the last frame posted (``PaneLedger/previousDocks``).
    package var previouslyPostedDocks: [String: PaneLedger.PostedDock] { panes.previousDocks }

    /// Notes that the sheet of section `id` docked the page before this walk
    /// (``PaneLedger/dockedBeforeTheWalk``).
    package func noteDockedBeforeTheWalk(_ id: String) {
        panes.dockedBeforeTheWalk.insert(id)
    }

    /// Whether any sheet docked the page before this walk.
    package var anyDockedBeforeTheWalk: Bool { !panes.dockedBeforeTheWalk.isEmpty }

    /// The ledger's ``PaneLedger/noteDocksLeftUndrawn(windowedOut:)``.
    package func noteDocksLeftUndrawn(windowedOut: (ViewIdentity) -> Bool) {
        panes.noteDocksLeftUndrawn(windowedOut: windowedOut)
    }

    /// Whether the sheet of section `id` docked the page last frame and that
    /// frame left its presenter out of a lazy container's window
    /// (``PaneLedger/undrawnUnderTheirDock``).
    package func isUndrawnUnderItsDock(_ id: String) -> Bool {
        panes.undrawnUnderTheirDock.contains(id)
    }
}
