//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionAsParts.swift
//
//  A `Section` in a container is its header's, content's and footer's views,
//  laid out as the container's own children — except in the containers that
//  read a section as a section.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - A Section Is Its Parts

/// A section hands its container its header's, content's and footer's views as
/// the container's own children, as SwiftUI's does, measured on macOS 15.8:
/// `VStack(spacing: 10) { x; Section { a; b } header: { h } footer: { f }; y }`
/// spaces all six ten apart, an `HStack` lays them along its row, a `ZStack`
/// overlaps them, a `Grid` gives each a row of its own and a `Layout` sees four
/// subviews. The header and footer are drawn as written: outside a `List`, a
/// `Form` and a `Table` SwiftUI gives them no styling of its own (decisions
/// B16). A collapsible section contributes its header, and its content only
/// while it is expanded.
///
/// Kept whole (``staysWhole(in:)``) where a section is read as a section: a
/// `List` and the section APIs resolve their content with
/// `RenderContext.keepsSectionsWhole`, and a pinned lazy stack's own sections
/// pin their own headers and footers. A `Form` and a `Table` read their
/// sections through walks of their own, which never ask.
@MainActor extension Section: ChildViewProvider where Parent: View, Content: View, Footer: View {
    public func childViews(context: RenderContext) -> [ChildView] {
        // Whole, for a caller that asks a provider for its children without
        // asking first whether it stays whole.
        guard !staysWhole(in: context) else { return [ChildView(self)] }
        return sectionPartChildren(header, part: 0, in: context)
            + (showsContent ? sectionPartChildren(content, part: 1, in: context) : [])
            + sectionPartChildren(footer, part: 2, in: context)
    }

    /// Whole in a walk that keeps sections whole, and in an unpinned lazy
    /// stack's walk (`SectionWholeness.loopRows`) when its content is a loop
    /// past the lazy stack's threshold in scroll content: taken apart, the
    /// loop's rows were the stack's children, every one built for each
    /// measure of the stack on the first frame (30,035 for one section of
    /// 10,000 rows); kept whole, the section draws its parts as the stack
    /// would and its loop as a lazy stack of its own, pulled
    /// (`_SectionCore.pulledPartsColumn`). Whatever the loop's count when the
    /// section is written out in the stack's content, so its parts keep their
    /// identities as the loop crosses the threshold (the owner's O-14 (c)).
    public func staysWhole(in context: RenderContext) -> Bool {
        guard !sectionStaysWhole(in: context) else { return true }
        guard context.sectionWholeness == .loopRows, showsContent, viewMayBeLoop(Content.self) else { return false }
        let scope = context.environment.pinnedSectionScope
        let anyCount = scope.map { $0.windowsSectionLoops || $0.writesOut(sectionAt: context.identity) } ?? false
        return sectionContentLoopWindows(content, whateverItsCount: anyCount, in: context)
    }
}

/// The children one part of a section contributes: the part's own members,
/// resolved under a step of their own below the section — the scope
/// ``SectionParts/scopedParts(in:)`` gives the section APIs, so a header's
/// `Text` and a content `Text` never share an identity — and pinned there, so
/// a container drawing them keeps them where they were resolved.
///
/// A part that is statically `EmptyView` — a section built without a header —
/// contributes nothing and resolves nothing.
@MainActor
func sectionPartChildren<Part: View>(
    _ part: Part, part index: Int, in context: RenderContext
) -> [ChildView] {
    guard Part.self != EmptyView.self else { return [] }
    let scope = context.withChildIdentity(type: Part.self, index: index)
    return resolveChildViews(from: part, context: scope).map {
        $0.pinningIdentity(to: scope.identity)
    }
}

@MainActor extension Section {
    /// Whether the content is shown: always, unless the section is collapsible
    /// and collapsed.
    package var showsContent: Bool { isExpanded?.wrappedValue ?? true }
}
