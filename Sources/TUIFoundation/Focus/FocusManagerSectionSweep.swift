//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManagerSectionSweep.swift
//
//  Keeps the per-section focus memory and revert targets to the sections that
//  still exist.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// The smallest ``sectionSweepThreshold``: an app with a few dozen
    /// sections never sweeps at all.
    static let minimumSectionSweepThreshold = 64

    /// How far down a chain of revert targets a sweep keeps sections that no
    /// longer register: deeper than any navigation a person keeps in their
    /// head, and short enough that Tab cycling through sections that have
    /// gone cannot keep them all.
    static let sectionSweepRevertDepth = 32

    /// Drops the remembered focus and revert targets of sections that have
    /// gone, once the two tables have doubled since the last sweep — then
    /// waits for them to double again, so the cost per entry written is
    /// constant.
    ///
    /// Both are keyed by section id and written on every activation, and
    /// before this only ``clear()`` emptied the memory, and only a dismissal a
    /// revert target: an app whose sections come and go — one per row of
    /// churning data, a sheet per document — kept an entry for every section
    /// the focus ever left. Swept at the write that grows them, so a frame that
    /// activates nothing pays nothing.
    ///
    /// A section still exists if it registered this pass or the last, is the
    /// active one, or is where one of those reverts to, up to
    /// ``sectionSweepRevertDepth`` steps down. That last keeps what the tables
    /// are for: a `NavigationStack` renders only its root and its top screen,
    /// so the screens between register no section, and their memory is found
    /// again by walking down the revert targets as each is popped.
    ///
    /// The walk is bounded because every activation writes a revert target,
    /// Tab cycling included, so a chain can lead back through every section
    /// the focus was ever in. Kept whole, it would keep them all.
    func sweepSectionTablesIfGrown() {
        guard sectionFocusMemory.count + sectionRevertTarget.count >= sectionSweepThreshold else { return }
        let kept = sectionsStillPresent()
        for section in Array(sectionFocusMemory.keys) where !kept.contains(section) {
            sectionFocusMemory[section] = nil
        }
        for section in Array(sectionRevertTarget.keys) where !kept.contains(section) {
            sectionRevertTarget[section] = nil
        }
        sectionSweepThreshold = max(
            Self.minimumSectionSweepThreshold, (sectionFocusMemory.count + sectionRevertTarget.count) * 2)
    }

    /// The sections ``sweepSectionTablesIfGrown()`` keeps the entries of.
    private func sectionsStillPresent() -> Set<String> {
        var kept: Set<String> = [Self.defaultSectionID]
        if let activeSectionIdentifier { kept.insert(activeSectionIdentifier) }
        for section in sections { kept.insert(section.id) }
        for section in previousSections { kept.insert(section.id) }
        // Down each chain of revert targets. Stopping at a section already
        // kept also ends a cycle.
        for root in Array(kept) {
            var section = root
            var remaining = Self.sectionSweepRevertDepth
            while remaining > 0, let below = sectionRevertTarget[section], kept.insert(below).inserted {
                section = below
                remaining -= 1
            }
        }
        return kept
    }
}
