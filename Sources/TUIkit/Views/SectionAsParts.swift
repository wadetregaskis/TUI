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

// MARK: - Whether a Section Can Be Among a View's Children

/// A provider that knows from its TYPE whether a `Section` can be among the
/// children it hands its container — see ``mayHandOverSections(_:)``.
@MainActor
protocol SectionMembershipKnowing {
    /// Whether an instance of this type can hand its container a `Section`,
    /// asking each type it holds once (`visited`).
    static func mayHandOverSections(visited: inout Set<ObjectIdentifier>) -> Bool
}

/// Whether a `Section` can be among the children a view of type `type` hands
/// the container resolving it: `false` only where the type proves there is
/// none, so a container that treats sections specially — a lazy grid drawing
/// them section by section, a lazy stack keeping them whole, a menu styling
/// them — can skip the walk that would look for one, which is every child of
/// its content.
///
/// A view that is no provider is one child, and no section — unless it is a
/// view of the app's own whose body is taken apart (`compositeMembers`), which
/// hands over what its body does. A `Section` (or a section under modifiers
/// that reach its parts) is one. The providers whose content is spelled in
/// their type — a tuple, a `Group`, an `if`, a `ForEach`'s row, a modifier on
/// several views — answer for their content. Any other provider — an
/// `AnyView`, the subview and section APIs, one added later — may hand over
/// anything, and is answered `true`: the walk finds out.
///
/// A view type met again on the way down — a tree view whose body loops over
/// rows of its own type — answers `false` the second time: what it can hand
/// over is already being asked of it.
@MainActor
func mayHandOverSections<V: View>(_ type: V.Type) -> Bool {
    var visited: Set<ObjectIdentifier> = []
    return mayHandOverSections(type, visited: &visited)
}

/// ``mayHandOverSections(_:)``, carrying the types already asked.
@MainActor
func mayHandOverSections<V: View>(_ type: V.Type, visited: inout Set<ObjectIdentifier>) -> Bool {
    if type is any SectionPartsProviding.Type { return true }
    guard type is any ChildViewProvider.Type else {
        guard V._handsOverChildren, isCompositeHandingOverChildren(type),
            visited.insert(ObjectIdentifier(type)).inserted
        else { return false }
        return mayHandOverSections(V.Body.self, visited: &visited)
    }
    if let known = type as? any SectionMembershipKnowing.Type {
        guard visited.insert(ObjectIdentifier(type)).inserted else { return false }
        return known.mayHandOverSections(visited: &visited)
    }
    if let wrapper = type as? any ContentRewrapping.Type {
        return wrappedMayHandOverSections(wrapper, visited: &visited)
    }
    return true
}

/// ``mayHandOverSections(_:visited:)`` of a wrapper's content, the existential
/// opened.
@MainActor
private func wrappedMayHandOverSections<W: ContentRewrapping>(
    _: W.Type, visited: inout Set<ObjectIdentifier>
) -> Bool {
    mayHandOverSections(W.WrappedContent.self, visited: &visited)
}

extension TupleView: SectionMembershipKnowing {
    static func mayHandOverSections(visited: inout Set<ObjectIdentifier>) -> Bool {
        var found = false
        func check<T: View>(_: T.Type) {
            if !found, TUIkit.mayHandOverSections(T.self, visited: &visited) { found = true }
        }
        repeat check((each V).self)
        return found
    }
}

extension ConditionalView: SectionMembershipKnowing {
    static func mayHandOverSections(visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOverSections(TrueContent.self, visited: &visited)
            || TUIkit.mayHandOverSections(FalseContent.self, visited: &visited)
    }
}

extension Optional: SectionMembershipKnowing where Wrapped: View {
    static func mayHandOverSections(visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOverSections(Wrapped.self, visited: &visited)
    }
}

extension ModifiedView: SectionMembershipKnowing where Content: ChildViewProvider {
    static func mayHandOverSections(visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOverSections(Content.self, visited: &visited)
    }
}

extension Group: SectionMembershipKnowing where Content: View {
    static func mayHandOverSections(visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOverSections(Content.self, visited: &visited)
    }
}

/// A loop's rows are its children, so its row type answers.
extension ForEach: SectionMembershipKnowing where Content: View {
    static func mayHandOverSections(visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOverSections(Content.self, visited: &visited)
    }
}
