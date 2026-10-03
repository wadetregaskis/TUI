//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SubviewResolution.swift
//
//  How a view is taken apart into the members `Group(subviews:)`,
//  `ForEach(subviews:)` and the section APIs hand out.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Members

/// The members of a view, resolved in one scope and pinned there.
///
/// Backed lazily for the shape that matters at scale — a lone `ForEach`, whose
/// count and ids come straight from its data without building a row — and by
/// an array otherwise. Shared by a collection and every slice and proxy taken
/// from it, so a member resolves to the same identity however it is reached.
@MainActor
struct SubviewMembers {
    private enum Storage {
        /// Resolved members, each with where its implicit tag comes from.
        case eager([Member])
        /// A lone loop's rows, built and pinned per subscript.
        case lazy(ChildViewCollection, scope: ViewIdentity)
    }

    /// One resolved member.
    @MainActor
    struct Member {
        /// The member, its identity pinned.
        let child: ChildView
        /// The row ids of the container it was resolved from, when any of its
        /// siblings was a `ForEach` row — asked for its implicit tag only.
        let rowIDs: FlattenedRowIDs<AnyHashable>?
        /// Its index among that container's resolved children.
        let rowIndex: Int

        /// The element id this member is tagged with by default, if it is a
        /// `ForEach` row.
        var implicitTag: AnyHashable? { rowIDs?.elementID(ofChildAt: rowIndex) }
    }

    private let storage: Storage

    /// How many members there are. Never builds a row.
    let count: Int

    /// No members.
    static let empty = Self(storage: .eager([]))

    private init(storage: Storage) {
        self.storage = storage
        switch storage {
        case .eager(let members): count = members.count
        case .lazy(let collection, _): count = collection.count
        }
    }

    /// Already-resolved members.
    init(_ members: [Member]) {
        self.init(storage: .eager(members))
    }

    /// The members of `base`, resolved under `scope` and pinned there.
    ///
    /// A `Section` among them is flattened into its header's, content's and
    /// footer's members (SwiftUI counts `Section { a; b } header: { h }
    /// footer: { f }` as four), an `EmptyView` contributes none, and every
    /// other child is one member — including a container, whose own children
    /// stay inside it.
    init(resolving base: some View, in scope: RenderContext) {
        if let loop = base as? any SubviewsLoop, loop.rowsAreSingleMembers {
            self.init(
                storage: .lazy(
                    resolveChildViewCollection(from: base, context: scope), scope: scope.identity))
            return
        }
        var members: [Member] = []
        appendMembers(of: base, in: scope, flatteningSections: true, into: &members)
        self.init(storage: .eager(members))
    }

    /// The member at `index`, pinned.
    func child(at index: Int) -> ChildView {
        switch storage {
        case .eager(let members): members[index].child
        case .lazy(let collection, let scope): collection[index].pinningIdentity(to: scope)
        }
    }

    /// The element id the member at `index` is tagged with by default.
    func implicitTag(at index: Int) -> AnyHashable? {
        switch storage {
        case .eager(let members): members[index].implicitTag
        case .lazy(let collection, _): collection.anyID(at: index)
        }
    }

    /// The members in `range`, as a container's child collection: lazily for a
    /// lone loop's rows, so a lazy stack placed around them still builds only
    /// the rows it draws.
    func childViewCollection(_ range: Range<Int>) -> ChildViewCollection {
        switch storage {
        case .eager(let members):
            return ChildViewCollection(eager: members[range].map(\.child))
        case .lazy(let collection, let scope):
            let lower = range.lowerBound
            return ChildViewCollection(
                count: range.count,
                key: { collection.key(at: lower + $0) ?? "" },
                anyID: { collection.anyID(at: lower + $0) },
                build: { collection[lower + $0].pinningIdentity(to: scope) })
        }
    }

    /// The members in `range`, built.
    func children(_ range: Range<Int>) -> [ChildView] {
        range.map(child(at:))
    }
}

/// A provider whose children can be handed out lazily as members — a
/// `ForEach` whose rows are each one member, never a `Section` to flatten nor
/// an `EmptyView` to drop.
@MainActor
protocol SubviewsLoop {
    /// Whether every row is exactly one member — a static property of the row
    /// type, so no row is built to answer it.
    var rowsAreSingleMembers: Bool { get }
}

extension ForEach: SubviewsLoop {
    var rowsAreSingleMembers: Bool {
        !(Content.self is any SectionPartsProviding.Type) && Content.self != EmptyView.self
    }
}

// MARK: - The Walk

/// Appends the members `base` resolves to under `scope`, pinned there.
///
/// - Parameter flatteningSections: Whether a `Section` among them becomes its
///   parts' members. The section APIs keep the top level's sections whole and
///   flatten only those nested inside a section's content.
@MainActor
func appendMembers(
    of base: some View, in scope: RenderContext, flatteningSections: Bool,
    into members: inout [SubviewMembers.Member]
) {
    let children = resolveChildViews(from: base, context: scope)
    // Only a `ForEach` makes a keyed child, so a container of hand-written
    // views has no implicit tags to place.
    let rowIDs =
        children.contains { $0.identityChildKey != nil }
        ? FlattenedRowIDs<AnyHashable>(content: base, children: children) : nil
    for (index, child) in children.enumerated() {
        if isEmptyMember(child) { continue }
        if flatteningSections, let section = sectionParts(of: child) {
            let sectionScope = pinnedScope(of: child, in: scope)
            for part in section.scopedParts(in: sectionScope) {
                appendMembers(of: part.view, in: part.scope, flatteningSections: true, into: &members)
            }
            continue
        }
        members.append(
            SubviewMembers.Member(
                child: child.pinningIdentity(to: scope.identity), rowIDs: rowIDs, rowIndex: index))
    }
}

/// `scope` moved to the identity `child` pins to in it — where a section's
/// parts resolve.
@MainActor
func pinnedScope(of child: ChildView, in scope: RenderContext) -> RenderContext {
    var pinned = scope
    pinned.identity = child.pinningIdentity(to: scope.identity).pinnedIdentity ?? scope.identity
    return pinned
}

/// Whether `child` is an `EmptyView`, which SwiftUI does not count as a
/// subview — `if false { … }` contributes nothing either, but that is already
/// gone by the time a child exists.
@MainActor
func isEmptyMember(_ child: ChildView) -> Bool {
    throughWrappers(child.wrappedView, as: EmptyView.self) != nil
}

// MARK: - Sections as Members

/// A section's three parts, each a view.
@MainActor
struct SectionParts {
    let header: any View
    let content: any View
    let footer: any View

    /// The parts with a view applied to each — how a modifier written on a
    /// section reaches its parts, as one written on a `Group` reaches its
    /// members.
    func map(_ transform: (any View) -> any View) -> Self {
        Self(header: transform(header), content: transform(content), footer: transform(footer))
    }

    /// Each part with the scope its members resolve in: a step of its own
    /// under the section, so a header's `Text` and a content `Text` never
    /// share an identity.
    func scopedParts(in section: RenderContext) -> [(view: any View, scope: RenderContext)] {
        [header, content, footer].enumerated().map { index, part in
            (part, section.withChildIdentity(erasedType: type(of: part), index: index))
        }
    }
}

/// A view that is a `Section`, or a section with modifiers on it that reach
/// its parts.
@MainActor
protocol SectionPartsProviding {
    /// The section's header, content and footer.
    var sectionParts: SectionParts { get }
}

extension Section: SectionPartsProviding {
    var sectionParts: SectionParts {
        SectionParts(header: header, content: content, footer: footer)
    }
}

/// A modified section is still a section, its modifier on each part — the
/// `GridRowProviding` rule.
extension ModifiedView: SectionPartsProviding where Content: SectionPartsProviding {
    var sectionParts: SectionParts {
        content.sectionParts.map { part in
            @MainActor
            func modified<V: View>(_ view: V) -> any View {
                ModifiedView<V, Modifier>(content: view, modifier: modifier)
            }
            return modified(part)
        }
    }
}

extension SectionPartsProviding where Self: ContentRewrapping, WrappedContent: SectionPartsProviding {
    var sectionParts: SectionParts {
        wrappedContent.sectionParts.map { rewrapping($0) }
    }
}

/// Body deliberately empty: ``SectionPartsProviding`` has the whole
/// implementation for a ``ContentRewrapping`` wrapper.
extension _ContainerValueView: SectionPartsProviding where Content: SectionPartsProviding {}

/// Body deliberately empty, as above.
extension EnvironmentModifier: SectionPartsProviding where Content: SectionPartsProviding {}

/// Body deliberately empty, as above.
extension TransformEnvironmentModifier: SectionPartsProviding where Content: SectionPartsProviding {}

/// Body deliberately empty, as above.
extension ObjectEnvironmentModifier: SectionPartsProviding where Content: SectionPartsProviding {}

/// The parts of `child` if it is a section — through `ForEach`'s row memo,
/// whose TYPE is asked first so only a section row is built.
@MainActor
func sectionParts(of child: ChildView) -> SectionParts? {
    let view = child.wrappedView
    if let provider = view as? SectionPartsProviding { return provider.sectionParts }
    guard child.identityChildKey != nil, let memo = view as? any _ValueMemoWrapping,
        memo.memoizedContentType is any SectionPartsProviding.Type,
        let provider = memo.memoizedContent as? SectionPartsProviding
    else { return nil }
    return provider.sectionParts
}
