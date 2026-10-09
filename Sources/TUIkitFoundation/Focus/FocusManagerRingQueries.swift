//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerRingQueries.swift
//
//  What the focus ring holds, asked of the manager: the active section's ids,
//  and a one-line summary for diagnostics. Read-only queries over state kept in
//  `Focus.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// How many sections are registered so far this frame.
    package var sectionCount: Int { sections.count }

    /// The active section's registered focus IDs in ring order — the
    /// per-frame enumeration (§5d of "Locating things without drawing
    /// them"). Internal: tests assert exactly what the last walk registered.
    func registeredFocusIDsInActiveSection() -> [String] {
        activeSection?.focusables.map(\.focusID) ?? []
    }

    /// The active section's focus IDs that can actually BE focused, in ring
    /// order — what an arrow or a jump key walks.
    ///
    /// Distinct from ``registeredFocusIDsInActiveSection()``, which reports
    /// everything that registered: a disabled row registers but declines focus,
    /// and a menu that overflows also registers its `ScrollView`. Either would
    /// make "jump to the last item" land somewhere that is not an item.
    func focusableIDsInActiveSection() -> [String] {
        activeSection?.focusables.filter(\.canBeFocused).map(\.focusID) ?? []
    }

    /// Diagnostic one-line summary of the focus manager's section
    /// state. Used by the gated logging across the framework when
    /// `TUIKIT_DEBUG_FOCUS=1`; not part of the public API.
    internal func debugSectionsSummary() -> String {
        let parts = sections.map { section -> String in
            let active = section.id == activeSectionIdentifier ? "*" : ""
            let ids = section.focusables.map(\.focusID).joined(separator: ",")
            return "\(active)\(section.id)[\(ids)]"
        }
        return parts.joined(separator: " | ")
    }

    /// All registered section IDs in render order.
    var sectionIDs: [String] {
        sections.map(\.id)
    }

    /// Every registered focusable's id, in render order across all sections —
    /// the ring as it actually stands this frame. Used by tests that assert
    /// what is (and is not) reachable.
    var focusableIDs: [String] {
        sections.flatMap { $0.focusables.map(\.focusID) }
    }
}
