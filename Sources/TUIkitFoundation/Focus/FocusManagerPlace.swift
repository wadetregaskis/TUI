//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerPlace.swift
//
//  Where the focus rests, as a value a window keeps while another is in front
//  of it. Moving the focus back to one is in `Focus.swift`, beside the focus
//  state it sets.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Where the focus rests: the active section and the focused element in
    /// it. What a window keeps while another is in front of it, for
    /// ``move(to:enteringSection:)`` when it comes back.
    package struct Place: Equatable {
        /// The active section's identifier.
        package let sectionID: String?

        /// The focused element's identifier.
        package let focusedID: String?
    }

    /// Where the focus rests now.
    package var place: Place {
        Place(sectionID: activeSectionIdentifier, focusedID: currentFocusedID)
    }
}
