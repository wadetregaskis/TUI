//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentedContent.swift
//
//  A modal surface's content as one keyboard owner: the focus sections drawn
//  inside a sheet, an alert or a popover — a `.focusSection`, a pushed
//  navigation screen, a split view's columns — are the surface's own.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension RenderContext {
    /// Draws the content of the modal surface whose focus section is
    /// `sectionID`, with every section registered while it draws counted as the
    /// surface's (`FocusManager.presentationRoot(of:)`), and the handlers
    /// registered in those sections hearing the keys the surface holds
    /// (`KeyEventDispatcher.extendGrab(of:to:)`).
    ///
    /// Around the content alone: the page drawn beneath has a focus manager of
    /// its own. A measure registers nothing, and draws as it is.
    ///
    /// Without it, a section inside a sheet was a section of the page's: the
    /// sheet took the focus back from it on every frame, Tab inside the sheet
    /// never reached it, and its key handlers were silenced by the sheet's grab.
    /// A navigation stack in a sheet pushed a screen the keyboard could not
    /// reach, and Escape closed the sheet instead of going back.
    @MainActor
    package func drawingPresentedContent<Drawn>(sectionID: String, _ draw: () -> Drawn) -> Drawn {
        guard !isMeasuring, let focusManager = environment.focusManager else { return draw() }
        focusManager.beginPresentedContent(sectionID: sectionID)
        let drawn = draw()
        focusManager.endPresentedContent()
        environment.keyEventDispatcher?.extendGrab(
            of: sectionID, to: focusManager.sectionIDs(drawnInside: sectionID))
        return drawn
    }
}

extension EnvironmentValues {
    /// The focus section a keyboard shortcut declared here belongs to: the
    /// modal's own inside a modal's content, where only the modal's shortcuts
    /// fire (`KeyboardShortcutRegistry.Scope`), whichever section of it the
    /// shortcut is in; otherwise the section it is in.
    @MainActor
    package var shortcutSectionID: String? {
        focusManager?.presentationRoot(of: activeFocusSectionID) ?? activeFocusSectionID
    }
}
