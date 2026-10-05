//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionAsParts.swift
//
//  A `Section` in a container is its header's, content's and footer's views,
//  laid out as the container's own children — except in the containers that
//  read a section as a section.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

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
extension Section: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        // Whole, for a caller that asks a provider for its children without
        // asking first whether it stays whole.
        guard !staysWhole(in: context) else { return [ChildView(self)] }
        return sectionPartChildren(header, part: 0, in: context)
            + (showsContent ? sectionPartChildren(content, part: 1, in: context) : [])
            + sectionPartChildren(footer, part: 2, in: context)
    }

    public func staysWhole(in context: RenderContext) -> Bool {
        sectionStaysWhole(in: context)
    }
}

/// A section with actions is its section's parts in a container — the actions
/// belong to a `List`, which keeps the section whole, as do the section APIs,
/// which hand them to a custom container.
extension _SectionActionsView: ChildViewProvider where Content: ChildViewProvider {
    func childViews(context: RenderContext) -> [ChildView] {
        guard !staysWhole(in: context) else { return [ChildView(self)] }
        // A step inside this view, where drawing it through its `body` puts
        // the section.
        let sectionScope = context.withChildIdentity(type: Content.self)
        return resolveChildViews(from: content, context: sectionScope).map {
            $0.pinningIdentity(to: sectionScope.identity)
        }
    }

    func staysWhole(in context: RenderContext) -> Bool {
        content.staysWhole(in: context)
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

extension Section {
    /// Whether the content is shown: always, unless the section is collapsible
    /// and collapsed.
    var showsContent: Bool { isExpanded?.wrappedValue ?? true }
}
