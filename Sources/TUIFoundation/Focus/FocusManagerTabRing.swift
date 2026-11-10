//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManagerTabRing.swift
//
//  Tab and Shift-Tab: round the active section, then on to the next section
//  of the ring — the page's sections, or a modal's own and those drawn inside
//  it. The section walk itself is `cycleSection` in `Focus.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Moves focus to the next focusable element.
    ///
    /// When multiple sections exist, Tab navigates within the current section
    /// first. Only when the current element is the last in its section does
    /// Tab switch to the next section.
    /// When only one section exists — or the active one is modal, which is the
    /// same thing from inside — this cycles within it (wrapping).
    public func focusNext() {
        if sections.count > 1, !activeSectionIsModal {
            let moved = moveFocusInSection(direction: .forward, wrap: false)
            if !moved { activateNextSection() }
        } else {
            moveFocusInSection(direction: .forward, wrap: true)
        }
    }

    /// Moves focus to the previous focusable element.
    ///
    /// When multiple sections exist, Shift+Tab navigates within the current
    /// section first. Only when the current element is the first in its section
    /// does Shift+Tab switch to the previous section.
    /// When only one section exists — or the active one is modal — this cycles
    /// within it (wrapping).
    public func focusPrevious() {
        if sections.count > 1, !activeSectionIsModal {
            let moved = moveFocusInSection(direction: .backward, wrap: false)
            if !moved { activatePreviousSection() }
        } else {
            moveFocusInSection(direction: .backward, wrap: true)
        }
    }
}
