//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionConfiguration.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Section Configuration

/// Specifies the contents of a section.
///
/// A configuration represents either an explicit ``Section``, or a run of
/// sibling views that are not wrapped in one — an implicit section. Its
/// ``header``, ``content`` and ``footer`` are each a ``SubviewsCollection``,
/// because each can be several views: place one in a container to lay its
/// members out together.
///
/// ```swift
/// ForEach(sections: content) { section in
///     VStack {
///         HStack { section.header }
///         section.content
///         HStack { section.footer }
///     }
/// }
/// ```
///
/// The section is taken as written: no list styling is applied to its header
/// or footer, which is the custom container's to decide.
public struct SectionConfiguration: Identifiable {
    /// A unique identifier for a section.
    public struct ID: Hashable, Sendable, CustomStringConvertible {
        /// The identity the section resolved to — for an implicit section,
        /// its first member's.
        let identity: ViewIdentity

        public var description: String { identity.description }
    }

    /// The type-erased actions of a section.
    ///
    /// The view `.sectionActions(content:)` gave the section, and an empty view
    /// for a section given none — every implicit section among them.
    nonisolated public struct Actions: View {
        /// The actions, or `nil` for none.
        let content: AnyView?

        init(_ content: (any View)? = nil) {
            self.content = content.map { AnyView($0) }
        }

        @MainActor public var body: some View {
            content ?? AnyView(EmptyView())
        }
    }

    /// A unique identifier representing the section.
    public let id: ID

    /// The contents of the section header.
    public let header: SubviewsCollection

    /// The contents of the section body.
    public let content: SubviewsCollection

    /// The contents of the section footer.
    public let footer: SubviewsCollection

    /// The container values associated with the given section — those written
    /// on the `Section` itself. Only an explicit section can have any, so an
    /// implicit section's are empty.
    public let containerValues: ContainerValues

    /// Custom actions associated with a section — those
    /// `.sectionActions(content:)` wrote on it.
    public let actions: Actions
}

// MARK: - Section Collection

/// An opaque collection representing the sections of a view.
///
/// Each explicit ``Section`` among the view's members is one section; a run of
/// members between them that no section wraps forms an implicit section; and
/// there is always at least one, so a view with no sections at all is one
/// implicit section of everything.
public struct SectionCollection: RandomAccessCollection {
    public typealias Element = SectionConfiguration
    public typealias Index = Int
    public typealias Indices = Range<Int>

    package let sections: [SectionConfiguration]

    public var startIndex: Int { sections.startIndex }

    public var endIndex: Int { sections.endIndex }

    public subscript(position: Int) -> SectionConfiguration {
        sections[position]
    }
}

// MARK: - The Walk

extension SectionCollection {
    /// The sections of `base`, resolved under `scope` and pinned there.
    ///
    /// A member that is a `Section` — through modifiers that reach its parts,
    /// and through `ForEach`'s row memo — is an explicit section, its parts
    /// each resolved under a step of their own below it; a section nested in
    /// a part's content is flattened into that content. Every other member
    /// joins the implicit section the members around it form. A section is
    /// taken apart here rather than drawn, so a header gets none of the
    /// styling a `List` gives one.
    @MainActor
    package init(resolving base: some View, in scope: RenderContext) {
        // Sections whole, to be read as sections (`RenderContext.keepsSectionsWhole`).
        let children = resolveChildViews(from: base, context: scope.keepingSectionsWhole())
        let rowIDs =
            children.contains { $0.identityChildKey != nil }
            ? FlattenedRowIDs<AnyHashable>(content: base, children: children, sectionsWhole: true) : nil
        var sections: [SectionConfiguration] = []
        var loose: [SubviewMembers.Member] = []

        func closeImplicitSection() {
            guard let first = loose.first?.child.pinnedIdentity else { return }
            sections.append(
                SectionConfiguration(
                    id: SectionConfiguration.ID(identity: first),
                    header: SubviewsCollection(members: .empty),
                    content: SubviewsCollection(members: SubviewMembers(loose)),
                    footer: SubviewsCollection(members: .empty),
                    containerValues: ContainerValues(),
                    actions: SectionConfiguration.Actions()))
            loose = []
        }

        for (index, child) in children.enumerated() {
            if isEmptyMember(child) { continue }
            guard let parts = sectionParts(of: child) else {
                loose.append(
                    SubviewMembers.Member(
                        child: child.pinningIdentity(to: scope.identity), rowIDs: rowIDs,
                        rowIndex: index))
                continue
            }
            closeImplicitSection()
            let sectionScope = pinnedScope(of: child, in: scope)
            let collections = parts.scopedParts(in: sectionScope).map { part in
                var members: [SubviewMembers.Member] = []
                appendMembers(of: part.view, in: part.scope, flatteningSections: true, into: &members)
                return SubviewsCollection(members: SubviewMembers(members))
            }
            sections.append(
                SectionConfiguration(
                    id: SectionConfiguration.ID(identity: sectionScope.identity),
                    header: collections[0],
                    content: collections[1],
                    footer: collections[2],
                    containerValues: ContainerValues(
                        of: child, implicitTag: rowIDs?.elementID(ofChildAt: index)),
                    actions: SectionConfiguration.Actions(parts.actions)))
        }
        closeImplicitSection()
        if sections.isEmpty {
            sections.append(
                SectionConfiguration(
                    id: SectionConfiguration.ID(identity: scope.identity),
                    header: SubviewsCollection(members: .empty),
                    content: SubviewsCollection(members: .empty),
                    footer: SubviewsCollection(members: .empty),
                    containerValues: ContainerValues(),
                    actions: SectionConfiguration.Actions()))
        }
        self.sections = sections
    }
}
