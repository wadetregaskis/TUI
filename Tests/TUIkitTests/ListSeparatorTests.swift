//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListSeparatorTests.swift
//
//  A list's separators as a rule line between rows (decisions A47, option 2):
//  `listRowSeparator`, `listRowSeparatorTint`, `listSectionSeparator`,
//  `listSectionSeparatorTint` and the two separator guides. None by default
//  (A-D6L-2); drawn where asked; never below the last row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("List separators")
struct ListSeparatorTests {

    private func buffer(_ view: some View, height: Int = 14) -> FrameBuffer {
        renderToBuffer(view.listStyle(.plain), context: makeRenderContext(width: 24, height: height))
    }

    /// The list's lines, stripped, with the blank fill below the rows dropped.
    private func lines(_ view: some View) -> [String] {
        let drawn = buffer(view).lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        return Array(drawn.prefix { !$0.isEmpty })
    }

    private static let rule = "rule"

    /// `lines`, each rule line spelled `rule`.
    private func shape(_ view: some View) -> [String] {
        lines(view).map { $0.allSatisfy { $0 == "─" } ? Self.rule : $0 }
    }

    private static let names = ["a", "b", "c"]

    @Test("A list draws no separators by default")
    func noneByDefault() {
        #expect(shape(List { ForEach(Self.names, id: \.self) { Text($0) } }) == ["a", "b", "c"])
    }

    @Test("A row asking for its separator draws a rule under it, and the last row none")
    func rowsDrawRulesBetween() {
        let list = List {
            ForEach(Self.names, id: \.self) { Text($0).listRowSeparator(.visible) }
        }
        #expect(shape(list) == ["a", Self.rule, "b", Self.rule, "c"])
    }

    @Test("Written on the list, it is every row's; a row's own still wins")
    func listWideDefaultAndRowOverride() {
        let list = List {
            ForEach(Self.names, id: \.self) { name in
                Text(name).listRowSeparator(name == "b" ? .hidden : .automatic)
            }
        }
        .listRowSeparator(.visible)
        #expect(shape(list) == ["a", Self.rule, "b", "c"])
    }

    @Test("A row's top edge is the style's to decline")
    func topEdgeDeclined() {
        let list = List {
            ForEach(Self.names, id: \.self) { Text($0).listRowSeparator(.visible, edges: .top) }
        }
        #expect(shape(list) == ["a", "b", "c"])
    }

    @Test("A hand-written row's separator is its own")
    func staticRows() {
        let list = List {
            Text("a").listRowSeparator(.visible)
            Text("b")
            Text("c")
        }
        #expect(shape(list) == ["a", Self.rule, "b", "c"])
    }

    @Test("A tint colours the rule")
    func tint() {
        func ruleLine(_ list: some View) -> String {
            buffer(list).lines.first { $0.stripped.contains("─") } ?? ""
        }
        let plain = ruleLine(
            List { ForEach(Self.names, id: \.self) { Text($0) } }.listRowSeparator(.visible))
        let tinted = ruleLine(
            List { ForEach(Self.names, id: \.self) { Text($0).listRowSeparatorTint(.red) } }
                .listRowSeparator(.visible))
        #expect(!plain.isEmpty && !tinted.isEmpty)
        #expect(plain != tinted, "the tint changed nothing: \(tinted.debugDescription)")
        let red = ANSIRenderer.colorize("x", foreground: Color.red.opaqueSpelling).components(separatedBy: "x")[0]
        #expect(tinted.contains(red + "─"), "\(tinted.debugDescription) has no \(red.debugDescription)")
    }

    @Test("A section's separators are the lines under its header and under its last row")
    func sections() {
        let list = List {
            Section("A") { ForEach(["a1", "a2"], id: \.self) { Text($0) } }
            Section("B") { ForEach(["b1"], id: \.self) { Text($0) } }
        }
        #expect(shape(list.listSectionSeparator(.visible)) == ["A", Self.rule, "a1", "a2", Self.rule, "B", Self.rule, "b1"])
        let bottomOnly = List {
            Section("A") { ForEach(["a1", "a2"], id: \.self) { Text($0) } }
                .listSectionSeparator(.visible, edges: .bottom)
            Section("B") { ForEach(["b1"], id: \.self) { Text($0) } }
        }
        #expect(shape(bottomOnly) == ["A", "a1", "a2", Self.rule, "B", "b1"])
    }

    @Test("The separator guide moves the rule's leading end")
    func leadingGuide() {
        func column(_ line: String?) -> Int? {
            guard let line, let index = line.firstIndex(of: "─") else { return nil }
            return line.distance(from: line.startIndex, to: index)
        }
        let plain = buffer(
            List { ForEach(Self.names, id: \.self) { Text($0) } }.listRowSeparator(.visible)
        ).lines.map(\.stripped).first { $0.contains("─") }
        let guided = buffer(
            List {
                ForEach(Self.names, id: \.self) { name in
                    HStack(spacing: 1) {
                        Text("•")
                        Text(name).alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    }
                }
            }
            .listRowSeparator(.visible)
        ).lines.map(\.stripped).first { $0.contains("─") }
        let from = column(plain)
        let to = column(guided)
        #expect(from != nil && to != nil)
        #expect((to ?? 0) - (from ?? 0) == 2, "plain \(String(describing: plain)), guided \(String(describing: guided))")
    }

    @Test("A separator is a line of the row's height: the window holds fewer rows")
    func separatorsCostHeight() {
        let rows = (0..<10).map { "r\($0)" }
        let drawn = buffer(
            List { ForEach(rows, id: \.self) { Text($0) } }.listRowSeparator(.visible), height: 6
        ).lines.map(\.stripped)
        let shown = drawn.filter { $0.contains("r") && !$0.contains("more") }
        #expect(shown.count <= 3, "\(drawn)")
    }
}
