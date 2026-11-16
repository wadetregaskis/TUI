//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManager+SectionCycling.swift
//
//  Moving the focus between sections and within one: Tab's section cycle and
//  the walk within the active section. Moved out of Focus.swift, which had
//  reached the 600-line lint limit, reading the section and the focus through
//  their accessors, as the other FocusManager files do.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The direction in which focus moves.
package enum FocusDirection {
    case forward, backward
}

extension FocusManager {
    /// Cycles the active section in the given direction.
    ///
    /// - Returns: Whether another section took the focus: `false` where none
    ///   in the ring has anything focusable.
    @discardableResult
    func cycleSection(direction: FocusDirection, in ring: [FocusSection]? = nil) -> Bool {
        let sections = ring ?? self.sections
        guard sections.count > 1 else { return false }

        let startIndex: Int
        if let activeID = activeSectionIdentifier,
            let currentIndex = sections.firstIndex(where: { $0.id == activeID })
        {
            startIndex = currentIndex
        } else {
            // No active section: enter the ring just "before" the first
            // candidate in the travel direction, so the walk below starts at
            // the first / last section exactly as the old fixed pick did.
            startIndex = direction == .forward ? sections.count - 1 : 0
        }

        // Walk the ring in the travel direction, skipping sections with no
        // currently-focusable element — activating one would strand the app
        // with nothing focused (the boundary entry has nothing to land on),
        // making the focus indicator vanish for a keypress. A section whose
        // controls are all disabled (or all gone this frame) is simply not a
        // Tab stop, matching desktop focus-ring conventions.
        var index = startIndex
        for _ in 1..<sections.count {
            switch direction {
            case .forward:
                index = (index + 1) % sections.count
            case .backward:
                index = index == 0 ? sections.count - 1 : index - 1
            }
            if sections[index].focusables.contains(where: { $0.canBeFocused }) {
                activateSection(id: sections[index].id, focusBoundary: direction)
                return true
            }
        }
        // No other section has anything focusable; stay where we are.
        return false
    }

    /// Moves focus within the active section.
    ///
    /// - Parameters:
    ///   - direction: The direction in which to move focus.
    ///   - wrap: When `true`, focus wraps around from the last element to the
    ///     first (and vice versa). When `false`, focus stops at the boundary
    ///     and the method returns `false`.
    /// - Returns: `true` if focus moved to a new element, `false` if the
    ///   boundary was reached (and `wrap` is `false`) or no element is available.
    @discardableResult
    func moveFocusInSection(direction: FocusDirection, wrap: Bool = true) -> Bool {
        guard let section = activeSection else { return false }
        let ring = section.focusables
        guard ring.contains(where: \.canBeFocused) else { return false }

        // The walk is `nearestFocusable(in:from:_:wrap:)`, shared with recovery.
        if let currentID = currentFocusedID,
            let anchor = ring.firstIndex(where: { $0.focusID == currentID && $0.canBeFocused })
        {
            guard let target = Self.nearestFocusable(in: ring, from: anchor, direction, wrap: wrap)
            else { return false }
            focus(target)
            return true
        }
        let edge = direction == .forward ? ring.first(where: \.canBeFocused) : ring.last(where: \.canBeFocused)
        guard let edge else { return false }
        focus(edge)
        return true
    }
}
