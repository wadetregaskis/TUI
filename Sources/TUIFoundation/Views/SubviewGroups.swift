//  🖥️ TUI — A Terminal UI framework for Swift
//  SubviewGroups.swift
//
//  A view's members grouped by the sections they are in, as a picker shows its
//  options: a section's under its header, and a run outside any section on
//  its own.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// One group of a view's members: a top-level `Section`'s — its header's
/// members, and its content's — or a run of members outside any section.
@MainActor
package struct SubviewGroup {
    /// The section header's members; none for a run outside any section, or
    /// for a section with no header.
    package let header: [Subview]
    /// The members, each a proxy that draws its view and answers its
    /// ``Subview/containerValues``: its tag through any modifier written
    /// after `.tag(_:)`, and the element id a `ForEach` row is tagged with.
    package let members: [Subview]
    /// Whether these are a `Section`'s, with a header or without one — where
    /// a run outside any section is not.
    package let isSection: Bool
}

/// The members of `base`, resolved in `scope` as ``Group/init(subviews:transform:)``
/// resolves them, grouped by the top-level sections they are in.
///
/// What a container that reads its options rather than drawing them — a
/// ``Picker`` — needs, to find them wherever SwiftUI finds them: inside a view
/// of the app's own, a `Group`, an `AnyView` or an `if`, and behind a modifier
/// written after the tag. A section nested inside a section's content is
/// flattened into it, as ``Group/init(subviews:transform:)`` flattens one; a
/// section's footer is not a member of either.
@MainActor
package func subviewGroups(of base: some View, in scope: RenderContext) -> [SubviewGroup] {
    var top: [SubviewMembers.Member] = []
    appendMembers(of: base, in: scope, flatteningSections: false, into: &top)

    var groups: [SubviewGroup] = []
    var run: [SubviewMembers.Member] = []
    func endRun() {
        guard !run.isEmpty else { return }
        groups.append(SubviewGroup(header: [], members: proxies(run), isSection: false))
        run = []
    }
    for member in top {
        guard let section = sectionParts(of: member.child) else {
            run.append(member)
            continue
        }
        endRun()
        let parts = section.scopedParts(in: pinnedScope(of: member.child, in: scope))
        var header: [SubviewMembers.Member] = []
        appendMembers(of: parts[0].view, in: parts[0].scope, flatteningSections: true, into: &header)
        var content: [SubviewMembers.Member] = []
        appendMembers(of: parts[1].view, in: parts[1].scope, flatteningSections: true, into: &content)
        groups.append(SubviewGroup(header: proxies(header), members: proxies(content), isSection: true))
    }
    endRun()
    return groups
}

/// A proxy for each of `members`, sharing one collection so each answers its
/// implicit tag from the container it was resolved in.
@MainActor
private func proxies(_ members: [SubviewMembers.Member]) -> [Subview] {
    let collection = SubviewMembers(members)
    return members.indices.map { Subview(members: collection, index: $0) }
}

@MainActor extension Subview {
    /// Whether this member is a ``Divider``, seen through any modifier on it —
    /// a rule between a picker's options, not one of them.
    package var isDivider: Bool {
        throughWrappers(child.wrappedView, as: Divider.self) != nil
    }
}
