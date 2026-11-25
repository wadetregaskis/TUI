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

    /// How many of ``focusables`` answer to each focus id: what a registration
    /// is checked against for a duplicate, in place of a scan of the ring.
    ///
    /// The scan compared the new id with every filed one, so filing n controls
    /// cost n²/2 string compares, every frame, served frames included (their
    /// registrations are replayed); and an id is a few hundred bytes of identity
    /// path (274 for a button on Stress's `controls/buttons-200`) shared with
    /// its siblings' up to the tail, so each compare read most of it. At 200
    /// buttons that was 12.7% of the page's CPU. A count, not a set, so it stays
    /// the ring's own answer when two elements answer to one id, which only a
    /// repoint (``reindex()``) can bring about.
    private var filedIDCounts: [String: Int] = [:]

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
        let id = element.focusID
        // Registering fills a place reserved for it, where the reservation put
        // it. Asked only while one is held, which is seldom: the id is long to
        // hash.
        if !reservedIDs.isEmpty { reservedIDs.remove(id) }
        guard claim(id) else { return }
        file(element)
    }

    /// Files `element` in its place now, ahead of what registers before its
    /// owner does, and holds the section's first focus for it until it
    /// registers (``holdsReservation``).
    func reserve(_ element: Focusable) {
        let id = element.focusID
        guard claim(id) else { return }
        file(element)
        reservedIDs.insert(id)
    }

    /// Takes back the elements filed at `range`, and any place reserved for
    /// one of them (`FocusManager.rewindRegistrations(to:)`).
    func unfile(_ range: Range<Int>) {
        let range = range.clamped(to: focusables.indices)
        for element in focusables[range] {
            let id = element.focusID
            reservedIDs.remove(id)
            unclaim(id)
        }
        focusables.removeSubrange(range)
    }

    /// Counts the filed elements' focus ids again, from the ids they answer to
    /// now: what `FocusManager` asks of its sections after a filed handler is
    /// repointed (`FocusRegistration.repointPersistedHandler`), the one way an
    /// element's id changes after it was filed.
    func reindex() {
        filedIDCounts.removeAll(keepingCapacity: true)
        for element in focusables { filedIDCounts[element.focusID, default: 0] += 1 }
    }

    /// Counts `id` as filed, unless an element filed here answers to it
    /// already; whether it did. One hashed access of the table, not a lookup
    /// and then an insert: `subscript(_:default:)` hands `Self.claim` the
    /// count in place, a zero when there is none, and keeps what it writes.
    private func claim(_ id: String) -> Bool {
        Self.claim(&filedIDCounts[id, default: 0])
    }

    private static func claim(_ count: inout Int) -> Bool {
        guard count == 0 else { return false }
        count = 1
        return true
    }

    /// Counts one element answering to `id` fewer.
    private func unclaim(_ id: String) {
        guard let count = filedIDCounts[id] else { return }
        filedIDCounts[id] = count > 1 ? count - 1 : nil
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
        let id = element.focusID
        guard filedIDCounts.removeValue(forKey: id) != nil else { return }
        focusables.removeAll { $0.focusID == id }
    }

    /// Removes all focusable elements from this section.
    func clearFocusables() {
        focusables.removeAll()
        filedIDCounts.removeAll()
    }
}
