//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModifiedSectionRowsTests.swift
//
//  A `Section` under an environment write is still a section to its `List`:
//  its header and each of its rows rows of the list. The list drew such a
//  section as ONE row, so `Section { … }.headerProminence(.increased)` lost
//  its rows' badges, their tags and with them the selection.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitFoundation
import TUIkitLists
@testable import TUIkitTestSupport

@MainActor
@Suite("A section under an environment write")
struct ModifiedSectionRowsTests {

    private func lines(_ view: some View) -> [String] {
        renderToBuffer(view.frame(width: 30, height: 6), context: makeRenderContext(width: 30, height: 6))
            .lines.map(\.stripped)
    }

    @Test("Its rows keep their badges", arguments: [false, true])
    func badges(transformed: Bool) {
        let section = Section("Inbox") { Text("Unread").badge(3) }
        let drawn = transformed
            ? lines(List { section.transformEnvironment(\.headerProminence) { $0 = .increased } })
            : lines(List { section.headerProminence(.increased) })
        #expect(drawn.contains { $0.contains("Unread") && $0.contains("3") }, "\(drawn)")
    }

    @Test("Its rows keep their tags, so the selection is drawn on the row it names")
    func tags() throws {
        let buffer = renderToBuffer(
            List(selection: .constant(Optional("b"))) {
                Section("S") {
                    Text("a").tag("a")
                    Text("b").tag("b")
                }
                .headerProminence(.increased)
            }
            .frame(width: 30, height: 6),
            context: makeRenderContext(width: 30, height: 6))
        let row = try #require(buffer.lines.first { $0.stripped.contains("b") && !$0.stripped.contains("S") })
        let other = try #require(buffer.lines.first { $0.stripped.contains("a") && !$0.stripped.contains("S") })
        #expect(row != other.replacingOccurrences(of: "a", with: "b"), "the selected row is drawn as selected")
        #expect(row.stripped.contains("●"), "the selected row carries its mark: \(row.stripped)")
    }
}
