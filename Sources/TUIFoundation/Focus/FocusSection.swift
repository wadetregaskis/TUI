//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusSection.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A named, focusable area of the UI.
///
/// A focus section groups interactive children (buttons, menus, etc.)
/// into a navigable unit. Users cycle between sections with Tab/Shift+Tab,
/// and each section can declare its own StatusBar items.
///
/// Focus sections are registered during rendering by the
/// `FocusSectionModifier`. The `FocusManager` tracks all sections
/// and manages which one is currently active.
package final class FocusSection {
    /// The unique identifier for this section.
    let id: String

    /// The focusable elements registered within this section.
    private(set) var focusables: [Focusable] = []

    /// The focus ids of places reserved in ``focusables`` whose owners have
    /// not registered yet this walk (``reserve(_:)``).
    private(set) var reservedIDs: Set<String> = []

    /// Where the next element registered is filed: at the end, or — while a
    /// container draws rows that stand above rows it has already drawn
    /// (`FocusManager.registering(at:_:)`) — at this place, which moves on
    /// past each element filed there.
    var registrationPlace: Int?

    /// Creates a new focus section with the given identifier.
    ///
    /// - Parameter id: A unique identifier for this section.
    init(id: String) {
        self.id = id
    }
}

// MARK: - Internal API

extension FocusSection {
    /// Registers a focusable element in this section.
    ///
    /// Duplicate registrations (same `focusID`) are ignored.
    ///
    /// - Parameter element: The element to register.
    func register(_ element: Focusable) {
        // Registering fills a place reserved for it, where the reservation put it.
        reservedIDs.remove(element.focusID)
        guard !focusables.contains(where: { $0.focusID == element.focusID }) else { return }
        file(element)
    }

    /// Files `element` in its place now, ahead of what registers before its
    /// owner does, and holds the section's first focus for it until it
    /// registers (``holdsReservation``).
    func reserve(_ element: Focusable) {
        guard !focusables.contains(where: { $0.focusID == element.focusID }) else { return }
        file(element)
        reservedIDs.insert(element.focusID)
    }

    /// Takes back the elements filed at `range`, and any place reserved for
    /// one of them (`FocusManager.rewindRegistrations(to:)`).
    func unfile(_ range: Range<Int>) {
        let range = range.clamped(to: focusables.indices)
        for element in focusables[range] { reservedIDs.remove(element.focusID) }
        focusables.removeSubrange(range)
    }

    /// Files `element` at ``registrationPlace``, or at the end.
    private func file(_ element: Focusable) {
        guard let place = registrationPlace, place < focusables.count else {
            focusables.append(element)
            if registrationPlace != nil { registrationPlace = focusables.count }
            return
        }
        focusables.insert(element, at: place)
        registrationPlace = place + 1
    }

    /// Whether a place is reserved here for an element that has not registered
    /// yet: a section's first focus waits for it, as it would had the element
    /// registered in its place.
    var holdsReservation: Bool { !reservedIDs.isEmpty }

    /// Unregisters a focusable element from this section.
    ///
    /// - Parameter element: The element to remove.
    func unregister(_ element: Focusable) {
        focusables.removeAll { $0.focusID == element.focusID }
    }

    /// Removes all focusable elements from this section.
    func clearFocusables() {
        focusables.removeAll()
    }
}
