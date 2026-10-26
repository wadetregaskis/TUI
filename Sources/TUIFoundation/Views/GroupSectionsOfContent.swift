//  🖥️ TUI — A Terminal UI framework for Swift
//  GroupSectionsOfContent.swift
//
//  `Group(sections:transform:)`: a view's sections, handed to a custom
//  container. `ForEach(sections:content:)` is in `ForEachSectionCollection.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Group(sections:transform:)

@MainActor
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
    /// The view whose sections are handed to `transform`.
    let base: Sections

    /// Builds the content from the sections.
    let transform: (SectionCollection) -> Content

    public var body: some View {
        _GroupSectionsCore(sections: self)
    }
}

extension GroupSectionsOfContent: ChildViewProvider {
    /// The views `transform` builds, as the enclosing container's children —
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
