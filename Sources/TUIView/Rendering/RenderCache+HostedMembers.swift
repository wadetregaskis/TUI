//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCache+HostedMembers.swift
//
//  Members drawn away from their own identity, and the clears that follow
//  them there.
//
//  Created by Wade Tregaskis
//  License: MIT

extension RenderCache {
    /// The members drawn under one place, and the last pass one was.
    struct HostedMembers {
        var members: Set<ViewIdentity>
        var lastSeenFrame: UInt64
    }

    /// Records that `member` — an identity cached for a view that draws away
    /// from it — is drawn under `host`, the identity of the place it is put.
    ///
    /// A ``Subview`` draws at the identity it resolved to (its declarer's, a
    /// `ForEach` row's say) under the context of the place a container puts
    /// it. A change of environment there is noted there, and its clear
    /// (``clearAffected(by:keepingSizes:includingDescendants:)``) drops what is
    /// cached below the place — not the member, whose entries are below its own
    /// identity. So a container inking its subviews by its own state
    /// (`subviews[i].foregroundStyle(i == chosen ? .red : .green)`) was served
    /// each in its old ink, and a segmented picker's selected segment stayed
    /// in its resting colour when the picker took the focus. With the record,
    /// a clear that reaches the place reaches the member too.
    ///
    /// One set insertion a draw, where comparing the environment itself at
    /// every member (a stamp a draw) cost a picker row a quarter of its frame.
    package func noteHostedMember(_ member: ViewIdentity, host: ViewIdentity) {
        if var record = hostedMembers[host] {
            guard record.lastSeenFrame != frameCounter || !record.members.contains(member) else { return }
            record.members.insert(member)
            record.lastSeenFrame = frameCounter
            hostedMembers[host] = record
        } else {
            hostedMembers[host] = HostedMembers(members: [member], lastSeenFrame: frameCounter)
            var cursor: ViewIdentity? = host
            while let node = cursor {
                hostsByAncestor[node.structuralHash, default: []].append(host)
                cursor = node.parent
            }
        }
    }

    /// Drops `host`'s record and its places in ``hostsByAncestor``.
    func forgetHost(_ host: ViewIdentity) {
        hostedMembers.removeValue(forKey: host)
        var cursor: ViewIdentity? = host
        while let node = cursor {
            let key = node.structuralHash
            if var hosts = hostsByAncestor[key] {
                hosts.removeAll { $0 == host }
                hostsByAncestor[key] = hosts.isEmpty ? nil : hosts
            }
            cursor = node.parent
        }
    }

    /// The members drawn at `identity` or below it whose own identity is not
    /// there too — which the clear at `identity` has already reached.
    ///
    /// Looked up by `identity`'s structural hash (``hostsByAncestor``), each
    /// host confirmed structurally: a scan of every host on every clear was a
    /// fiftieth of a `pickers` frame, its rows' segments each a host and each
    /// re-inked segment a clear.
    func membersHosted(under identity: ViewIdentity) -> [ViewIdentity] {
        guard let hosts = hostsByAncestor[identity.structuralHash] else { return [] }
        var found: [ViewIdentity] = []
        for host in hosts where host == identity || identity.isAncestor(of: host) {
            guard let record = hostedMembers[host] else { continue }
            for member in record.members where member != identity && !identity.isAncestor(of: member) {
                found.append(member)
            }
        }
        return found
    }
}
