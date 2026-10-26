//  🖥️ TUI — A Terminal UI framework for Swift
//  ListEdgeRevealTests.swift
//
//  Home and End go to the top and the bottom of a list, showing the rows the
//  cursor cannot land on beyond the first and last rows it can — a section's
//  header and footer, a hand-written row the selection cannot name — not
//  only the row the cursor lands on.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

@MainActor
@Suite("Home and End show the list's edges")
struct ListEdgeRevealTests {
    enum Shape: String, CaseIterable {
        /// A sidebar section, whose header is not pinned, with a footer.
        case section
        /// Rows the selection cannot name around a loop it can.
        case unnamed
    }

    @ViewBuilder
    private func list(_ shape: Shape) -> some View {
        switch shape {
        case .section:
            List(selection: .constant(Int?.none)) {
                Section {
                    ForEach(0..<30, id: \.self) { Text(verbatim: "row \($0)") }
                } header: {
                    Text("HEAD")
                } footer: {
                    Text("FOOT")
                }
            }
            .listStyle(.sidebar)
        case .unnamed:
            List(selection: .constant(String?.none)) {
                Text("HEAD")
                ForEach((0..<30).map { "row \($0)" }, id: \.self) { Text(verbatim: $0) }
                Text("FOOT")
            }
        }
    }

    @Test("End shows what is below the last row the cursor can land on, and Home what is above the first", arguments: Shape.allCases)
    func edgesAreShown(_ shape: Shape) {
        let context = makeRenderContext(width: 30, height: 8)
        let view = list(shape)
        func lines() -> String { renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n") }
        let top = lines()
        #expect(top.contains("HEAD") && !top.contains("FOOT"), "\(shape): \(top)")
        guard let manager = context.environment.focusManager else {
            Issue.record("no focus manager")
            return
        }
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .end)))
        let end = lines()
        #expect(end.contains("FOOT") && end.contains("row 29"), "\(shape): \(end)")
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .home)))
        let home = lines()
        #expect(home.contains("HEAD") && home.contains("row 0"), "\(shape): \(home)")
    }
}
