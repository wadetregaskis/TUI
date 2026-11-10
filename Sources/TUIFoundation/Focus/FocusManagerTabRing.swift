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
    ///
    /// A modal's ring is its own section and the sections drawn inside it — a
    /// `.focusSection`, a split view's columns, a pushed navigation screen — and
    /// Tab goes round those as it goes round a page's.
    public func focusNext() {
        let ring = activeModalSectionID.map { sections(presentedIn: $0) } ?? sections
        if ring.count > 1 {
            let moved = moveFocusInSection(direction: .forward, wrap: false)
            if !moved { cycleSection(direction: .forward, in: ring) }
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
        let ring = activeModalSectionID.map { sections(presentedIn: $0) } ?? sections
        if ring.count > 1 {
            let moved = moveFocusInSection(direction: .backward, wrap: false)
            if !moved { cycleSection(direction: .backward, in: ring) }
        } else {
            moveFocusInSection(direction: .backward, wrap: true)
        }
    }
}
