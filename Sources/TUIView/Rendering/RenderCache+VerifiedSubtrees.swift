//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCache+VerifiedSubtrees.swift
//
//  What the prune keeps of the suspects below an entry a re-check found
//  unchanged (VIEWR-4, O-21).
//
//  A parent's write marks every entry kept below it suspect (the soft drain).
//  The walk re-checks what it looks up; an entry found unchanged is served, and
//  nothing below it is visited, so what is below it is still suspect when the
//  pass ends. Dropped there, a pane served whole after a page's write lost
//  every memo inside it, and the next change in the pane drew all its rows.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The identities a re-check found unchanged this pass, and the suspects below
/// them the prune may keep.
///
/// **Why a suspect below one is safe to keep.** Before the drain every kept
/// entry was current. The write reaches an entry below a verified root only
/// through that root: a write at the root or between it and the entry drops
/// the root (a writer's ancestors go, `DrainVerdict.drop`), so the root could
/// not have been re-checked; and the root's value and environment compared
/// equal, which is what serving the root's buffer — which holds the entry's
/// drawing — already rests on. What is below it is built from those, from the
/// state between (unwritten) and from what it observes (whose change reports
/// at or below the root, which drops it). So the entry would be drawn as it
/// was. The documented gap of a row's `==` that leaves something out is the
/// gap serving the root already has, no wider.
///
/// **What is not kept.**
/// - A suspect at the root's own identity: kept only if its own lookup
///   re-checks it, as before (the index answers "strictly below").
/// - A root a re-check found changed at any lookup in the pass: not a root.
/// - Everything, once a soft drain runs again in the pass (a walk made again
///   for what effects wrote): it marks afresh, and a root verified before it
///   says nothing of what it marked (``RevalidationState/forgetVerifiedRoots()``).
/// - A member drawn away from its identity (a `Subview`) whose place is not
///   itself below a root, with what is below it: it is drawn under the place's
///   environment, which the root's re-check did not compare. The places of
///   such members are followed in turn, since a place inside an excluded
///   member is drawn under the same unverified environment.
struct VerifiedSubtrees {
    private var roots: RetainedSubtreeIndex
    private var excluded: RetainedSubtreeIndex
    private let excludedMembers: Set<ViewIdentity>

    init(roots verified: [ViewIdentity], hostedMembers: [ViewIdentity: RenderCache.HostedMembers]) {
        var roots = RetainedSubtreeIndex(roots: verified)
        var excludedMembers: Set<ViewIdentity> = []
        var excludedList: [ViewIdentity] = []
        if !verified.isEmpty, !hostedMembers.isEmpty {
            let rootSet = Set(verified)
            // To a fixed point: each round may exclude a place the round
            // before left in.
            var grew = true
            while grew {
                grew = false
                var excluded = RetainedSubtreeIndex(roots: excludedList)
                for (host, record) in hostedMembers {
                    let hostIsVerified =
                        (rootSet.contains(host) || roots.retains(host))
                        && !excludedMembers.contains(host) && !excluded.retains(host)
                    if hostIsVerified { continue }
                    for member in record.members where !excludedMembers.contains(member) && roots.retains(member) {
                        excludedMembers.insert(member)
                        excludedList.append(member)
                        grew = true
                    }
                }
            }
        }
        self.roots = roots
        self.excluded = RetainedSubtreeIndex(roots: excludedList)
        self.excludedMembers = excludedMembers
    }

    /// Whether the suspect at `identity` is below a verified root and outside
    /// every excluded member.
    mutating func keeps(_ identity: ViewIdentity) -> Bool {
        guard roots.retains(identity) else { return false }
        guard !excludedMembers.isEmpty else { return true }
        return !excludedMembers.contains(identity) && !excluded.retains(identity)
    }
}

extension RevalidationState {
    /// Notes a re-check's verdict at `identity` for the prune: unchanged makes
    /// it a verified root unless a re-check there this pass found otherwise,
    /// and changed unmakes it for the rest of the pass.
    func noteVerifiedRoot(_ verdict: RecheckVerdict, at identity: ViewIdentity) {
        switch verdict {
        case .unchanged:
            if verifiedRoots[identity] == nil { verifiedRoots[identity] = true }
        case .valueChanged, .environmentChanged:
            verifiedRoots[identity] = false
        case .off:
            break
        }
    }

    /// Forgets the pass's verified roots: at the pass's start and end, and when
    /// a soft drain marks suspects afresh mid-pass.
    func forgetVerifiedRoots() {
        if !verifiedRoots.isEmpty { verifiedRoots.removeAll(keepingCapacity: true) }
    }

    /// The identities every re-check this pass found unchanged.
    var verifiedRootList: [ViewIdentity] {
        verifiedRoots.compactMap { $0.value ? $0.key : nil }
    }
}
