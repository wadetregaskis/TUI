//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManagerMenuFocus.swift
//
//  Where the focused values are read while a menu is open: at the control
//  focused where the menu was opened, which an open menu takes the keyboard
//  from but not the focus.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIView

extension FocusManager {
    /// Where `@FocusedValue` reads from: the focused control — or, while a
    /// menu holds the keyboard with nothing in it focused, the control that
    /// was focused where the menu was opened.
    ///
    /// An open menu's section holds no focus (`presentMenuPopover`): its rows
    /// report to the menu's highlight, not to the focus ring, so the focus
    /// itself is `nil` while it is open. Read at `nil`, a reader was handed
    /// the scene values alone. A menu bar's command gated on a focused value —
    /// `.disabled(note == nil)`, the pattern `Commands` teaches — drew
    /// disabled the moment its menu opened, and could be chosen only by its
    /// key; a detail pane beside the focused control went blank under any
    /// open menu.
    ///
    /// A menu on macOS tracks without moving the first responder, so the key
    /// window's focused view, and what it publishes, stay as they were while
    /// it is open. So here: from a menu's section — through any menu opened
    /// from inside it — down to the section it was activated over, at the
    /// focus that section remembers, which is the focus ``deactivateSection(id:)``
    /// gives back when the menu closes. A sheet's or a popover's section is no
    /// menu's: a surface the person can focus things in reads at its own focus.
    ///
    /// Read by both halves of a reading — a reader during the walk
    /// (`FocusedValueRegistry.tableAtTheFocus()`) and the end of the pass that
    /// checks it (`endRenderPass()`) — so they agree. The menus marked LAST
    /// frame count too: a reader drawn before this frame's menu re-marks its
    /// section reads as the end of the pass will, rather than at `nil`, which
    /// would ask for a frame every frame the menu is open.
    var focusedValuesIdentity: ViewIdentity? {
        if let focusedIdentity { return focusedIdentity }
        guard currentFocusedID == nil, var section = activeSectionIdentifier else { return nil }
        // Bounded by the table's size, as `activatePresentedSection(id:)`'s
        // walk is: nothing stops the table holding a cycle.
        var remaining = sectionRevertTarget.count
        while remaining > 0, menuSectionIDs.contains(section) || previousMenuSectionIDs.contains(section),
            let below = sectionRevertTarget[section]
        {
            if let remembered = sectionFocusMemory[below] { return renderedIdentity(ofFocusID: remembered) }
            section = below
            remaining -= 1
        }
        return nil
    }
}
