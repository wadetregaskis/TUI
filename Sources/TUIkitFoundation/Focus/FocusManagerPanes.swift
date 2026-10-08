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
