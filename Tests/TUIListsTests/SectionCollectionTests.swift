//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionCollectionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

// MARK: - Fixtures

private struct RankKey: ContainerValueKey {
    static let defaultValue = -1
}

extension ContainerValues {
    fileprivate var rank: Int {
        get { self[RankKey.self] }
        set { self[RankKey.self] = newValue }
    }
}

/// The shape of each section a transform was handed.
private struct Shape: Equatable {
    let headers: Int
    let contents: Int
    let footers: Int
    let rank: Int
}

@MainActor
private final class Captured {
    var shapes: [Shape] = []
    var ids: [SectionConfiguration.ID] = []
}

// MARK: - Suite

/// `Group(sections:transform:)`, `ForEach(sections:content:)` and
/// `SectionConfiguration`, against what was measured on SwiftUI (W05 probes
/// B10–B13 and s8).
@MainActor
@Suite("Sections of a view")
struct SectionCollectionTests {

    private func render(_ view: some View, width: Int = 40, height: Int = 10) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    private func shapes(@ViewBuilder _ content: () -> some View) -> [Shape] {
        let captured = Captured()
        _ = render(
            Group(sections: content()) { sections -> EmptyView in
                captured.shapes = sections.map {
                    Shape(
                        headers: $0.header.count, contents: $0.content.count,
                        footers: $0.footer.count, rank: $0.containerValues.rank)
                }
                return EmptyView()
            })
        return captured.shapes
    }

    @Test("Views around a section form implicit sections of their own")
    func implicitAroundExplicit() {
        let read = shapes {
            Text("x")
            Section {
                Text("a")
                Text("b")
            } header: {
                Text("H")
            } footer: {
                Text("f")
            }
            .containerValue(\.rank, 4)
            Text("y")
        }
        #expect(
            read == [
                Shape(headers: 0, contents: 1, footers: 0, rank: -1),
                Shape(headers: 1, contents: 2, footers: 1, rank: 4),
                Shape(headers: 0, contents: 1, footers: 0, rank: -1),
            ])
    }

    @Test("Two sections without headers are two sections")
    func twoSections() {
        let read = shapes {
            Section { Text("a") }
            Section { Text("b") }
        }
        #expect(read.count == 2)
        #expect(read.map(\.headers) == [0, 0])
    }

    @Test("A view with no sections is one implicit section")
    func noSections() {
        #expect(shapes { Text("a"); Text("b") } == [Shape(headers: 0, contents: 2, footers: 0, rank: -1)])
        #expect(shapes { EmptyView() } == [Shape(headers: 0, contents: 0, footers: 0, rank: -1)])
    }

    @Test("A section nested in a section's content is flattened into it")
    func nestedSectionFlattens() {
        let read = shapes {
            Section {
                Section { Text("a") } header: { Text("inner") }
            } header: {
                Text("outer")
            }
        }
        #expect(read == [Shape(headers: 1, contents: 2, footers: 0, rank: -1)])
    }

    @Test("A ForEach of sections is one section per element")
    func forEachOfSections() {
        let read = shapes {
            ForEach(0..<3) { index in
                Section { Text("\(index)") } header: { Text("h\(index)") }
            }
        }
        #expect(read == Array(repeating: Shape(headers: 1, contents: 1, footers: 0, rank: -1), count: 3))
    }

    @Test("Every section has an id of its own")
    func distinctIDs() {
        let captured = Captured()
        _ = render(
            Group(
                sections: Group {
                    Text("x")
                    Section { Text("a") }
                    Text("y")
                    Section { Text("b") }
                }
            ) { sections -> EmptyView in
                captured.ids = sections.map(\.id)
                return EmptyView()
            })
        #expect(captured.ids.count == 4)
        #expect(Set(captured.ids).count == 4)
    }

    @Test("A custom container draws the parts it is handed")
    func groupDraws() {
        let lines = render(
            Group(
                sections: Group {
                    Section { Text("a"); Text("b") } header: { Text("H") }
                    Text("loose")
                }
            ) { sections in
                ForEach(sections) { section in
                    HStack(spacing: 1) {
                        section.header
                        section.content
                    }
                }
            })
        #expect(lines == ["H a b", "loose"])
    }

    @Test("ForEach(sections:) is one row per section")
    func forEachSections() {
        let content = Group {
            Section { Text("a") } footer: { Text("f") }
            Text("z")
        }
        let lines = render(
            VStack(alignment: .leading) {
                ForEach(sections: content) { section in
                    HStack(spacing: 1) {
                        section.content
                        section.footer
                        section.actions
                    }
                }
            })
        // The stack pads each line to its own width.
        #expect(lines == ["a f", "z  "])
    }
}
