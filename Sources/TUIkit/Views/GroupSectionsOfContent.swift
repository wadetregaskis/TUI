//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GroupSectionsOfContent.swift
//
//  `Group(sections:transform:)` and `ForEach(sections:content:)`: a view's
//  sections, handed to a custom container.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Group(sections:transform:)

extension Group {
    /// Constructs a group from the sections of the given view.
    ///
    /// `transform` receives `view`'s sections as a ``SectionCollection``: each
    /// ``Section`` among its members is one, and the members between them form
    /// implicit sections, so there is always at least one.
    ///
    /// ```swift
    /// Group(sections: content) { sections in
    ///     ForEach(sections) { section in
    ///         VStack(alignment: .leading) {
    ///             section.header
    ///             section.content
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - view: The view to extract the sections of.
    ///   - transform: A closure that constructs a view from the collection of
    ///     sections.
    public init<Base: View, Result: View>(
        sections view: Base,
        @ViewBuilder transform: @escaping (SectionCollection) -> Result
    ) where Content == GroupSectionsOfContent<Base, Result> {
        self.content = GroupSectionsOfContent(base: view, transform: transform)
    }
}

// MARK: - Group Sections Of Content

/// Transforms the sections of a given view into a resulting content view.
///
/// You don't use this type directly: ``Group/init(sections:transform:)``
/// creates it.
public struct GroupSectionsOfContent<Sections: View, Content: View>: View {
    /// The view whose sections are handed to ``transform``.
    let base: Sections

    /// Builds the content from the sections.
    let transform: (SectionCollection) -> Content

    public var body: some View {
        _GroupSectionsCore(sections: self)
    }
}

extension GroupSectionsOfContent: ChildViewProvider {
    /// The views ``transform`` builds, as the enclosing container's children —
    /// with the sections and the result in scopes of their own, for the reason
    /// ``GroupElementsOfContent`` gives.
    public func childViews(context: RenderContext) -> [ChildView] {
        let sections = SectionCollection(
            resolving: base, in: context.withChildIdentity(type: Sections.self, index: 0))
        let result = transform(sections)
        let resultScope = context.withChildIdentity(type: Content.self, index: 1)
        return resolveChildViews(from: result, context: resultScope).map {
            $0.pinningIdentity(to: resultScope.identity)
        }
    }

    /// Remembered for the pass, as ``GroupElementsOfContent``'s are.
    public var childViewsAreWorthMemoising: Bool { true }
}

/// The transform's views stacked vertically, for where nothing above lays them
/// out.
private struct _GroupSectionsCore<Sections: View, Content: View>: View, Renderable, Layoutable {
    let sections: GroupSectionsOfContent<Sections, Content>

    var body: Never {
        fatalError("_GroupSectionsCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureStackedVertically(
            resolveChildViews(from: sections, context: context), proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderStackedVertically(resolveChildViews(from: sections, context: context), context: context)
    }
}

// MARK: - ForEach(sections:content:)

extension ForEach {
    /// Creates an instance that uniquely identifies and creates views across
    /// updates based on the sections of a given view.
    ///
    /// One row per section of `view` — the sections
    /// ``Group/init(sections:transform:)`` hands its transform — each
    /// identified by its ``SectionConfiguration/id``. Like
    /// ``ForEach/init(subviews:content:)``, the sections are resolved where the
    /// loop is laid out as views, and a `List`, `Picker`, `TabView`, `Form` or
    /// suggestion list sees the loop as empty.
    ///
    /// - Parameters:
    ///   - view: The view to extract the sections of.
    ///   - content: The view builder that creates views from sections.
    public init<V: View>(
        sections view: V, @ViewBuilder content: @escaping (SectionConfiguration) -> Content
    ) where Data == ForEachSectionCollection<Content>, ID == SectionConfiguration.ID {
        self.init(ForEachSectionCollection(source: view), id: \.id, content: content)
    }
}

/// A collection which allows a view to be treated as a collection of its
/// sections in a for each loop.
///
/// You don't use this type directly: ``ForEach/init(sections:content:)``
/// creates it.
@MainActor
public struct ForEachSectionCollection<Content: View> {
    /// The view whose sections this iterates.
    let source: any View

    /// The sections, once resolved; none until then.
    let sections: [SectionConfiguration]

    init(source: some View) {
        self.source = source
        self.sections = []
    }

    private init(source: any View, sections: [SectionConfiguration]) {
        self.source = source
        self.sections = sections
    }
}

extension ForEachSectionCollection: @MainActor RandomAccessCollection {
    public typealias Element = SectionConfiguration
    public typealias Index = Int
    public typealias Indices = Range<Int>

    public var startIndex: Int { sections.startIndex }

    public var endIndex: Int { sections.endIndex }

    public subscript(position: Int) -> SectionConfiguration {
        sections[position]
    }
}

extension ForEachSectionCollection: ContextResolvedCollection {
    /// The source's sections, resolved under a step of their own below the
    /// loop — see ``ForEachSubviewCollection``.
    func resolved(in context: RenderContext) -> Self {
        func resolve<V: View>(_ source: V) -> [SectionConfiguration] {
            SectionCollection(resolving: source, in: context.withChildIdentity(type: V.self, index: 0))
                .sections
        }
        return Self(source: source, sections: resolve(source))
    }
}
