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
/// this walk's and the last frame's.
///
/// One value, rotated and emptied by the focus manager's pass hooks, with the
/// same current-and-previous shape as `presentationDismissals`.
struct PaneLedger {
    /// How many rows each sheet docked live at the bottom of the content area
    /// takes from the page, by its section: posted this walk.
    var docks: [String: PresentationDockResolver] = [:]

    /// ``docks`` as the previous frame left them: what the root asks, BEFORE
    /// the walk, how many rows to lay the page out short.
    private(set) var previousDocks: [String: PresentationDockResolver] = [:]

    /// Keeps the frame before's posts as the previous frame's — at the start
    /// of a render pass, before the walk empties them.
    mutating func beginFrame() {
        previousDocks = docks
    }

    /// Empties what a walk posts, before the walk re-posts it.
    mutating func beginWalk() {
        docks.removeAll()
    }
}
