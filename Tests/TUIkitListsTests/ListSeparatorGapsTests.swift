//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListSeparatorGapsTests.swift
//
//  The separator cases decisions B-D6L-3 left open: a `Section` a `ForEach`
//  makes draws its section separators as a hand-written one does; the
//  separator guides are found through the modifiers that draw their content
//  unchanged (`.onTapGesture`, `.tint`); and a row of several views reads the
//  guide its views state.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
import TUIkitLists
@testable import TUIkitTestSupport

@MainActor
@Suite("List separators: the cases B-D6L-3 left open")
struct ListSeparatorGapsTests {
    private struct Region: Identifiable {
        let id: String
        let items: [String]
    }

    private static let regions = [Region(id: "A", items: ["a1", "a2"]), Region(id: "B", items: ["b1"])]
    private static let names = ["a", "b", "c"]
    private static let rule = "rule"

    private func buffer(_ view: some View, height: Int = 14) -> FrameBuffer {
        renderToBuffer(view.listStyle(.plain), context: makeRenderContext(width: 24, height: height))
    }

    /// The list's lines, stripped, the blank fill below dropped and each rule
    /// spelled `rule`.
    private func shape(_ view: some View) -> [String] {
        let drawn = buffer(view).lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        return Array(drawn.prefix { !$0.isEmpty }).map { $0.allSatisfy { $0 == "─" } ? Self.rule : $0 }
    }

    /// The column the first rule starts at.
    private func ruleColumn(_ view: some View) -> Int? {
        guard let line = buffer(view).lines.map(\.stripped).first(where: { $0.contains("─") }),
            let index = line.firstIndex(of: "─")
        else { return nil }
        return line.distance(from: line.startIndex, to: index)
    }

    @Test("A Section a ForEach makes draws its section separators as a hand-written one does")
    func loopedSections() {
        let handWritten = List {
            Section("A") { ForEach(["a1", "a2"], id: \.self) { Text($0) } }
            Section("B") { ForEach(["b1"], id: \.self) { Text($0) } }
        }
        let looped = List {
            ForEach(Self.regions) { region in
                Section(region.id) { ForEach(region.items, id: \.self) { Text($0) } }
            }
        }
        #expect(shape(looped.listSectionSeparator(.visible)) == shape(handWritten.listSectionSeparator(.visible)))
        #expect(
            shape(looped.listSectionSeparator(.visible)) == ["A", Self.rule, "a1", "a2", Self.rule, "B", Self.rule, "b1"])
    }

    @Test("A Section a ForEach makes keeps its own section separator preference")
    func loopedSectionsOwnPreference() {
        let looped = List {
            ForEach(Self.regions) { region in
                Section(region.id) { ForEach(region.items, id: \.self) { Text($0) } }
                    .listSectionSeparator(region.id == "A" ? .visible : .hidden, edges: .bottom)
            }
        }
        #expect(shape(looped) == ["A", "a1", "a2", Self.rule, "B", "b1"])
    }

    /// Apple's documented row: the guide on a view inside the stack.
    private func row(_ name: String) -> some View {
        HStack(spacing: 1) {
            Text("•")
            Text(name).alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }

    @Test("The guide is found through an onTapGesture and a tint around the row")
    func guideThroughUnchangedDrawers() {
        let plain = ruleColumn(List { ForEach(Self.names, id: \.self) { Text($0) } }.listRowSeparator(.visible))
        let bare = ruleColumn(List { ForEach(Self.names, id: \.self) { row($0) } }.listRowSeparator(.visible))
        let tapped = ruleColumn(
            List { ForEach(Self.names, id: \.self) { row($0).onTapGesture {} } }.listRowSeparator(.visible))
        let tinted = ruleColumn(
            List { ForEach(Self.names, id: \.self) { row($0).tint(.red) } }.listRowSeparator(.visible))
        #expect(bare != nil && bare != plain, "the guide moves the rule: \(String(describing: plain)) \(String(describing: bare))")
        #expect(tapped == bare, "through .onTapGesture: \(String(describing: tapped)), bare \(String(describing: bare))")
        #expect(tinted == bare, "through .tint: \(String(describing: tinted)), bare \(String(describing: bare))")
    }

    /// A row of several views is several list rows (decisions B15); each is
    /// its own row to the separator, and reads the guide its view states.
    @Test("A row of several views reads the guide each of its views states")
    func guideInARowOfSeveralViews() {
        let plain = ruleColumn(List { ForEach(Self.names, id: \.self) { Text($0) } }.listRowSeparator(.visible))
        let several = ruleColumn(
            List {
                ForEach(Self.names, id: \.self) { name in
                    row(name)
                    Text("\(name)!")
                }
            }
            .listRowSeparator(.visible))
        #expect(several != nil && several != plain, "the first view's guide moves its rule: \(String(describing: several))")
    }
}
