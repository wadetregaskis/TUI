//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCache+PruneWitness.swift
//
//  What the last prune of a render cache decided from, so that a pass that
//  changed none of it skips the walk over every entry the cache keeps.
//
//  The prune asks of every entry whether it is suspect, or neither marked
//  active by the pass nor below a subtree the pass retained. A page served
//  whole from a memo high up marks almost nothing, so every entry kept under
//  that memo is asked, frame after frame, and found live each time: the walk
//  was proportional to what the cache keeps, not to what the frame did. On
//  `app-shapes/settings-form` at rest, a form whose sixty rows each keep a
//  picture and a few sizes, that was 373 retained checks a frame that changed
//  nothing (PERFCASE-F7).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The inputs of a render cache's last prune, and how much has changed since
/// — or of a state storage's, whose values are pruned by the same two tables
/// (`StateStorage.endRenderPass()`).
///
/// An entry's verdict is a function of whether it is suspect, of the set of
/// identities the pass marked active and of the roots it retained, and
/// nothing else: an identity's ancestry never changes. Every entry the last
/// prune kept was live then. So when no entry has been stored or marked
/// suspect since, and the pass marked and retained what the last pruned pass
/// did, every entry is live again and there is nothing to drop. Removing an
/// entry (a clear) changes no other entry's verdict, so it does not count.
///
/// The witness may hold more identities than the pruned pass marked — any
/// marked between that prune and the next pass's start — which is safe: a
/// pass that marks a superset of what was pruned under keeps every entry the
/// prune kept.
struct PruneWitness {
    /// Entries stored, and entries marked suspect, since the last prune.
    var changes = 0
    /// The active identities and retained roots of the last pruned pass:
    /// swapped in at the next pass's start (``adopt(active:roots:)``), so
    /// neither the pass's tables nor these are copied.
    private var active: Set<ViewIdentity> = []
    private var roots: [ViewIdentity] = []
    /// Whether ``active`` and ``roots`` are the last prune's: false until a
    /// prune has run, and from a pass that did not prune to the next prune.
    private var isCurrent = false
    /// Whether a prune ran since the last pass began.
    private var prunedThisPass = false
    /// Whether the last prune walked the entries.
    private var walked = false
    /// The retained checks of the last prune that walked the entries: what
    /// its retained index is sized for, which a prune that skipped the walk
    /// does not reset to nothing.
    private(set) var expectedChecks = 0

    /// Whether a prune now would keep every entry: nothing stored or marked
    /// suspect since the last, and the same identities marked and retained.
    ///
    /// Asked only where the walk it spares costs more than the comparison:
    /// the walk asks the active set about every entry, the comparison about
    /// every active identity.
    func isUnchanged(active: Set<ViewIdentity>, roots: [ViewIdentity], entryCount: Int) -> Bool {
        // A second prune in one pass decides from more than the witness saw.
        guard isCurrent, !prunedThisPass, changes == 0, active.count < entryCount else { return false }
        return roots == self.roots && active == self.active
    }

    /// A prune ran, and walked the entries or not: what the pass marked and
    /// retained is what it decided from.
    mutating func notePrune(walked: Bool) {
        changes = 0
        prunedThisPass = true
        self.walked = walked
    }

    /// The retained checks the prune made: kept as the next one's estimate
    /// only when it walked, since one that did not made none.
    mutating func noteChecks(_ checks: Int) {
        if walked { expectedChecks = checks }
    }

    /// A pass begins: the last pass's tables, if it pruned, become the
    /// witness, and the witness's storage becomes the new pass's (emptied by
    /// the caller, keeping its capacity).
    mutating func adopt(active: inout Set<ViewIdentity>, roots: inout [ViewIdentity]) {
        isCurrent = prunedThisPass
        prunedThisPass = false
        guard isCurrent else { return }
        swap(&self.active, &active)
        swap(&self.roots, &roots)
    }

    /// Forgets the last prune, as after the cache is reset.
    mutating func reset() {
        self = Self()
    }
}

// MARK: - The prune's walk

extension RenderCache {
    /// Counts a stored picture or size: for the frame's statistics, and as a
    /// change the next prune must walk for (``PruneWitness``).
    @inline(__always)
    func noteStore() {
        stats.stores += 1
        pruneWitness.changes += 1
    }

    /// The keys of the pictures and sizes the prune drops: each suspect, or
    /// whose identity `isLive` says is neither marked nor retained. None, and
    /// nothing walked, when the pass changed nothing a verdict reads
    /// (``PruneWitness``).
    ///
    /// Collected, then removed by the caller — the spelling
    /// `AnimationStore.endRenderPass()` uses and for its reason: removing
    /// inside `for … in sizeEntries` COW-copies the whole table on the first
    /// removal, and this table is hundreds of entries on a live page and
    /// thousands on `fanout`.
    func staleEntryKeys(
        active: Set<ViewIdentity>, roots: [ViewIdentity], isLive: (ViewIdentity) -> Bool
    ) -> (render: [Int], sizes: [SizeKey]) {
        let unchanged = pruneWitness.isUnchanged(
            active: active, roots: roots, entryCount: entries.count + sizeEntries.count)
        pruneWitness.notePrune(walked: !unchanged)
        guard !unchanged else { return ([], []) }
        var staleKeys: [Int] = []
        for (key, entry) in entries where unsafe entry.isSuspect || !isLive(entry.identity) { staleKeys.append(key) }
        var staleSizeKeys: [SizeKey] = []
        for (key, entry) in sizeEntries where unsafe entry.isSuspect || !isLive(entry.identity) {
            staleSizeKeys.append(key)
        }
        return (staleKeys, staleSizeKeys)
    }
}
