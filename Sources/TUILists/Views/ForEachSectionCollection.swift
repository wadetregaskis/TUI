//  🖥️ TUI — A Terminal UI framework for Swift
//  ForEachSectionCollection.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - ForEach(sections:content:)

extension ForEach where Content: View {
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
nonisolated public struct ForEachSectionCollection<Content: View> {
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

@MainActor extension ForEachSectionCollection: @MainActor RandomAccessCollection {
    public typealias Element = SectionConfiguration
    public typealias Index = Int
    public typealias Indices = Range<Int>

    public var startIndex: Int { sections.startIndex }

    public var endIndex: Int { sections.endIndex }

    public subscript(position: Int) -> SectionConfiguration {
        sections[position]
    }
}

@MainActor extension ForEachSectionCollection: ContextResolvedCollection {
    /// The source's sections, resolved under a step of their own below the
    /// loop — see ``ForEachSubviewCollection``.
    package func resolved(in context: RenderContext) -> Self {
        func resolve<V: View>(_ source: V) -> [SectionConfiguration] {
            SectionCollection(resolving: source, in: context.withChildIdentity(type: V.self, index: 0))
                .sections
        }
        return Self(source: source, sections: resolve(source))
    }
}
