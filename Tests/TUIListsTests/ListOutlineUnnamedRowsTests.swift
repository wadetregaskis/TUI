//  🖥️ TUI — A Terminal UI framework for Swift
//  ListOutlineUnnamedRowsTests.swift
//
//  An outline `List` whose selection cannot name its rows draws them, and they
//  select nothing, as a flat list's rows do (`List`'s documentation). It drew
//  nothing: the windowed outline declined rows the selection could not name,
//  and the eager path it handed them to left every one out.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
import TUITesting

/// A node identified by a `String`.
private struct UnnamedNode: Identifiable, Hashable, Sendable {
    let id: String
    var children: [Self]?
}

private let unnamedTree = [
    UnnamedNode(id: "Sources", children: [UnnamedNode(id: "Views", children: nil)]),
    UnnamedNode(id: "README", children: nil),
]

/// A selection type that is not the nodes' id type, nor an `Int` that would
/// name them by place.
private enum UnnamedChoice: Hashable, Sendable {
    case one
}

@MainActor
private final class UnnamedChosen {
    var one: UnnamedChoice?
    var many: Set<UnnamedChoice> = []
}

@MainActor
@Suite("An outline List whose selection cannot name its rows")
struct ListOutlineUnnamedRowsTests {
    @Test("The rows are drawn, and select nothing", arguments: [false, true])
    func drawsTheRows(multi: Bool) {
        let chosen = UnnamedChosen()
        let app = TestApp(width: 30, height: 8) {
            if multi {
                List(
                    unnamedTree, children: \.children, selection: Binding(get: { chosen.many }, set: { chosen.many = $0 })
                ) { Text($0.id) }
            } else {
                List(
                    unnamedTree, children: \.children, selection: Binding(get: { chosen.one }, set: { chosen.one = $0 })
                ) { Text($0.id) }
            }
        }
        #expect(app.screen.contains("Sources"), "\(app.screen)")
        #expect(app.screen.contains("README"))
        app.press(.tab)
        app.press(.down)
        app.press(.space)
        #expect(chosen.one == nil)
        #expect(chosen.many.isEmpty)
    }

    @Test("An outline in a section, alone or beside a row, draws its rows too")
    func inASection() {
        let chosen = UnnamedChosen()
        let selection = Binding(get: { chosen.one }, set: { chosen.one = $0 })
        let alone = TestApp(width: 30, height: 8) {
            List(selection: selection) {
                Section("Files") { OutlineGroup(unnamedTree, children: \.children) { Text($0.id) } }
            }
        }
        #expect(alone.screen.contains("Sources"), "\(alone.screen)")
        #expect(alone.screen.contains("README"))
        let beside = TestApp(width: 30, height: 8) {
            List(selection: selection) {
                Section("Files") {
                    Text("Pinned")
                    OutlineGroup(unnamedTree, children: \.children) { Text($0.id) }
                }
            }
        }
        #expect(beside.screen.contains("Pinned"), "\(beside.screen)")
        #expect(beside.screen.contains("Sources"))
        #expect(beside.screen.contains("README"))
    }

    #if DEBUG
        @Test("A debug build warns, naming the nodes' id type")
        func warns() {
            let chosen = UnnamedChosen()
            let app = TestApp(width: 30, height: 8) {
                List(unnamedTree, children: \.children, selection: Binding(get: { chosen.one }, set: { chosen.one = $0 })) {
                    Text($0.id)
                }
            }
            #expect(app.screen.contains("Sources"))
            let message = _ListCore<UnnamedChoice, EmptyView, EmptyView>.selectionNamesNoRowMessage(idType: String.self)
            #expect(SoftTrap.recorded.contains(message))
        }
    #endif
}
