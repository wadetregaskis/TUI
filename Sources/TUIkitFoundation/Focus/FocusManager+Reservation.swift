//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManager+Reservation.swift
//
//  A place in a focus section kept for a control that registers late in its
//  own drawing — a list, whose rows' controls are drawn before it registers.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Reserves `element`'s place in a section ahead of what registers before
    /// it does — a container whose content draws controls of its own before
    /// the container registers — without focusing anything: the section's
    /// first focus waits for the element's own ``register(_:inSection:)``.
    ///
    /// - Parameters:
    ///   - element: The element to place.
    ///   - sectionID: Its section, as ``register(_:inSection:)`` takes it.
    package func reservePlace(_ element: Focusable, inSection sectionID: String?) {
        let targetID = sectionID ?? Self.defaultSectionID
        if !sections.contains(where: { $0.id == targetID }) {
            registerSection(id: targetID)
        }
        section(id: targetID)?.reserve(element)
    }
}
