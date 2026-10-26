//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache+Drain.swift
//
//  What a write drops from the render cache: the queue's drain at a pass's
//  start, and the clears it and the synchronous invalidations make.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension RenderCache {
    /// Applies the invalidations enqueued by ``invalidateRender(for:)`` since the
    /// last frame. Runs on the main actor (from ``beginRenderPass()``), where
    /// mutating `entries`/`sizeEntries` is safe.
    func drainPendingInvalidations() {
        let pending = link.drain()
        if pending.clearAll {
            clearAll()
        } else if pending.identities.count == 1, let writer = pending.softOnly.first {
            clearAffected(softlyBy: writer)
        } else if !pending.softOnly.isEmpty {
            clearAffected(byEachOf: pending.identities, softly: pending.softOnly)
        } else if pending.identities.count == 1, let writer = pending.identities.first {
            clearAffected(by: writer)
        } else if !pending.identities.isEmpty {
            clearAffected(byEachOf: pending.identities)
        }
    }

    /// Clears cached entries affected by a state change at the given identity.
    ///
    /// Instead of clearing the entire cache, this removes only entries whose
    /// identity is an ancestor of, a descendant of, or equal to the changed
    /// identity. Sibling subtrees retain their cached buffers.
    ///
    /// - Parameter identity: The identity of the view whose state changed.
    ///
    /// - Parameters:
    ///   - identity: The identity whose ancestors, descendants and self are
    ///     affected.
    ///   - keepingSizes: `true` when the change cannot have moved a cell — a
    ///     paint, a tint — so the memoized SIZES stay and only the buffers go.
    ///     A ramp that rotates every frame re-inks four hundred rows, which is
    ///     the render walk's business; it used to cost the four measure walks
    ///     as well, re-measuring rows a colour cannot resize. `false` for
    ///     anything that can affect layout, which is every other environment
    ///     value and every `@State` write.
    ///   - includingDescendants: `false` when nothing below `identity` can draw
    ///     differently for the change: then only `identity` and the buffers
    ///     that CONTAIN it go. A focus move onto a scroll view, whose content
    ///     learns nothing of its focus, used to drop every row the content had
    ///     measured and drawn, and the next frame rebuilt them all.
    public func clearAffected(
        by identity: ViewIdentity, keepingSizes: Bool = false, includingDescendants: Bool = true
    ) {
        clearEntries(by: identity, keepingSizes: keepingSizes, includingDescendants: includingDescendants)
        // And what is drawn here but cached elsewhere: a subview a container
        // puts in this subtree draws at its declarer's identity, under this
        // subtree's environment (``noteHostedMember(_:host:)``). A worklist, so
        // members hosted under members are followed, each once.
        guard includingDescendants, !hostedMembers.isEmpty else { return }
        var visited: Set<ViewIdentity> = [identity]
        var pending = membersHosted(under: identity)
        while let member = pending.popLast() {
            guard visited.insert(member).inserted else { continue }
            clearEntries(by: member, keepingSizes: keepingSizes, includingDescendants: true)
            pending += membersHosted(under: member)
        }
    }

    /// ``clearAffected(by:keepingSizes:includingDescendants:)`` without the
    /// hosted members.
    private func clearEntries(by identity: ViewIdentity, keepingSizes: Bool, includingDescendants: Bool) {
        if !keepingSizes { sizeClearGeneration &+= 1 }
        stats.subtreeClears += 1
        // The hashes of `identity` and every ancestor of it, so "is the cached
        // identity `identity` or above it" is a set lookup per entry (confirmed
        // structurally on a hit) rather than a climb of `identity`'s chain per
        // entry. "Is it below" still climbs the cached chain to `identity`'s
        // depth, which is one hop per level of difference and a hash compare.
        var chain = Set<Int>()
        var cursor: ViewIdentity? = identity
        while let node = cursor {
            chain.insert(node.structuralHash)
            cursor = node.parent
        }
        func affects(_ cached: ViewIdentity) -> Bool {
            // Raw-rooted identities (tests, the empty default root) have no
            // chain to index: ancestry is a path prefix, and only the walk
            // sees it.
            if identity.isRawRooted || cached.isRawRooted {
                return cached == identity
                    || cached.isAncestor(of: identity)
                    || (includingDescendants && identity.isAncestor(of: cached))
            }
            if cached.depth <= identity.depth {
                return chain.contains(cached.structuralHash)
                    && (cached == identity || cached.isAncestor(of: identity))
            }
            return includingDescendants && identity.isAncestor(of: cached)
        }
        // `affects` reads `depth`, `isRawRooted`, `structuralHash`, `==` and
        // `isAncestor(of:)` — all structural, none of it available from a hash.
        stats.clearVisits += entries.count + (keepingSizes ? 0 : sizeEntries.count)
        var staleKeys: [Int] = []
        for (key, entry) in entries where affects(entry.identity) { staleKeys.append(key) }
        for key in staleKeys { entries.removeValue(forKey: key) }
        if !keepingSizes {
            var staleSizeKeys: [SizeKey] = []
            for (key, entry) in sizeEntries where affects(entry.identity) { staleSizeKeys.append(key) }
            for key in staleSizeKeys { sizeEntries.removeValue(forKey: key) }
        }
        logDebug("CLEAR AFFECTED by \(identity.path): \(staleKeys.count) of \(entries.count + staleKeys.count) entries")
    }

    /// What ``clearAffected(byEachOf:softly:)`` does for one soft writer, the
    /// usual drain — one `@State` written, or one body's read — as cheaply as
    /// ``clearAffected(by:keepingSizes:includingDescendants:)`` does it for a
    /// hard one: `writer` and its ancestors go, and below it, an entry that
    /// recorded what it was drawn from and under is kept, a suspect, and one
    /// that did not goes.
    func clearAffected(softlyBy writer: ViewIdentity) {
        sizeClearGeneration &+= 1
        stats.subtreeClears += 1
        var chain = Set<Int>()
        var cursor: ViewIdentity? = writer
        while let node = cursor {
            chain.insert(node.structuralHash)
            cursor = node.parent
        }
        func verdict(_ cached: ViewIdentity, stamped: Bool) -> DrainVerdict {
            let atOrAbove: Bool
            let below: Bool
            if writer.isRawRooted || cached.isRawRooted {
                atOrAbove = cached == writer || cached.isAncestor(of: writer)
                below = !atOrAbove && writer.isAncestor(of: cached)
            } else if cached.depth <= writer.depth {
                atOrAbove = chain.contains(cached.structuralHash) && (cached == writer || cached.isAncestor(of: writer))
                below = false
            } else {
                atOrAbove = false
                below = writer.isAncestor(of: cached)
            }
            if atOrAbove { return .drop }
            guard below else { return .keep }
            return stamped ? .suspect : .dropUnrecorded
        }
        stats.clearVisits += entries.count + sizeEntries.count
        var staleKeys: [Int] = []
        for (key, entry) in entries {
            switch verdict(entry.identity, stamped: entry.revalidation != nil) {
            case .keep: continue
            case .drop: staleKeys.append(key)
            case .dropUnrecorded:
                staleKeys.append(key)
                revalidation.counts.unstampedDropped += 1
            case .suspect:
                if !entry.isSuspect { revalidation.counts.suspectsMarked += 1 }
                entry.isSuspect = true
            }
        }
        for key in staleKeys { entries.removeValue(forKey: key) }
        var staleSizeKeys: [SizeKey] = []
        for (key, entry) in sizeEntries {
            switch verdict(entry.identity, stamped: entry.revalidation != nil) {
            case .keep: continue
            case .drop, .dropUnrecorded: staleSizeKeys.append(key)
            case .suspect: entry.isSuspect = true
            }
        }
        for key in staleSizeKeys { sizeEntries.removeValue(forKey: key) }
        logDebug("CLEAR SOFTLY by \(writer.path): \(staleKeys.count) of \(entries.count + staleKeys.count) entries")
    }

    /// What ``clearAffected(by:keepingSizes:includingDescendants:)`` would
    /// drop for each of `writers` in turn, sizes and descendants included, in
    /// ONE walk of each table.
    ///
    /// Called once per writer, as the drain was, each clear walked both
    /// tables: a frame after W writes cost W × the tables, and a frame in
    /// which many rows' readers fired paid it in full. Here each entry is
    /// asked once whether it is a writer or above one — every writer's chain,
    /// indexed by hash and confirmed structurally — or below one, which is the
    /// question the prune asks of retained roots, so it is asked the same way
    /// (``RetainedSubtreeIndex``: one climb of the entry's chain, sharing the
    /// verdicts of the ancestors already climbed, which it keys by hash — the
    /// 64-bit bargain the tables' own keys take). An entry is dropped exactly
    /// when some writer's clear would have dropped it, and the order of the
    /// writers never mattered: each clear only removes.
    ///
    /// The counters move as the pairwise clears moved them — the generation
    /// and ``Stats/subtreeClears`` once per writer — so a holder comparing
    /// ``sizeClearGeneration`` reads what it always read. Raw-rooted
    /// identities have no chain to index, so while one is among the writers
    /// every entry takes the pairwise test against each writer, which is what
    /// the pairwise clears asked of it.
    func clearAffected(byEachOf writers: Set<ViewIdentity>, softly soft: Set<ViewIdentity> = []) {
        sizeClearGeneration &+= writers.count
        stats.subtreeClears += writers.count
        let anyRawWriter = writers.contains(where: \.isRawRooted)
        // Every writer and every ancestor of one, by hash. A chain stops where
        // it meets one already indexed, whose ancestors are indexed too.
        var atOrAbove: [Int: [ViewIdentity]] = [:]
        for writer in writers where !anyRawWriter {
            var cursor: ViewIdentity? = writer
            while let node = cursor, atOrAbove[node.structuralHash]?.contains(node) != true {
                atOrAbove[node.structuralHash, default: []].append(node)
                cursor = node.parent
            }
        }
        // Below a soft writer — a parent's write (Option C, §2.2) — an entry
        // that recorded what it was drawn from and under is kept, a suspect,
        // to be re-checked when it is looked up; one that did not is dropped.
        // Below a hard writer, everything goes, as below every writer before.
        let hard = soft.isEmpty ? writers : writers.subtracting(soft)
        var belowHard = RetainedSubtreeIndex(roots: Array(hard))
        var belowSoft = RetainedSubtreeIndex(roots: Array(soft))
        func verdict(_ cached: ViewIdentity, stamped: Bool) -> DrainVerdict {
            if anyRawWriter || cached.isRawRooted {
                if writers.contains(where: { cached == $0 || cached.isAncestor(of: $0) }) { return .drop }
                if hard.contains(where: { $0.isAncestor(of: cached) }) { return .drop }
                guard soft.contains(where: { $0.isAncestor(of: cached) }) else { return .keep }
                return stamped ? .suspect : .dropUnrecorded
            }
            if atOrAbove[cached.structuralHash]?.contains(cached) == true || belowHard.retains(cached) { return .drop }
            guard !soft.isEmpty, belowSoft.retains(cached) else { return .keep }
            return stamped ? .suspect : .dropUnrecorded
        }
        stats.clearVisits += entries.count + sizeEntries.count
        var staleKeys: [Int] = []
        for (key, entry) in entries {
            switch verdict(entry.identity, stamped: entry.revalidation != nil) {
            case .keep: continue
            case .drop:
                staleKeys.append(key)
            case .dropUnrecorded:
                staleKeys.append(key)
                revalidation.counts.unstampedDropped += 1
            case .suspect:
                if !entry.isSuspect { revalidation.counts.suspectsMarked += 1 }
                entry.isSuspect = true
            }
        }
        for key in staleKeys { entries.removeValue(forKey: key) }
        var staleSizeKeys: [SizeKey] = []
        for (key, entry) in sizeEntries {
            switch verdict(entry.identity, stamped: entry.revalidation != nil) {
            case .keep: continue
            case .drop, .dropUnrecorded: staleSizeKeys.append(key)
            case .suspect: entry.isSuspect = true
            }
        }
        for key in staleSizeKeys { sizeEntries.removeValue(forKey: key) }
        logDebug("CLEAR AFFECTED by \(writers.count) writers: \(staleKeys.count) of \(entries.count + staleKeys.count) entries")
    }
}

/// What a drain does with one entry.
private enum DrainVerdict {
    /// Nothing written reaches it.
    case keep
    /// A write at it, above it or hard above it: it goes.
    case drop
    /// Only parents' writes above it, and it recorded nothing to re-check it
    /// by: it goes, as everything below a writer did before.
    case dropUnrecorded
    /// Only parents' writes above it, and it recorded what to re-check it by.
    case suspect
}
