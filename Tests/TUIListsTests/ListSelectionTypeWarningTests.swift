//  🖥️ TUI — A Terminal UI framework for Swift
//  ListSelectionTypeWarningTests.swift
//
//  A debug build says so when a `List`'s selection can hold none of its rows'
//  ids: the rows select nothing, as in SwiftUI, and the one line on stderr
//  saves the hunt (tuiarcade's feedback, 2026-11-17).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
import TUITesting

/// A game whose id is its raw value, a `String`, not itself.
private enum WarnedGame: String, CaseIterable, Identifiable, Sendable {
    case strata, comet
    var id: String { rawValue }
}

/// The same, identified by itself.
private enum NamedGame: String, CaseIterable, Identifiable, Sendable {
    case strata, comet
    var id: Self { self }
}

private struct WrongSelection: View {
    @State private var selection: WarnedGame?
    var body: some View {
        List(WarnedGame.allCases, selection: $selection) { Text($0.rawValue) }
    }
}

private struct RightSelection: View {
    @State private var selection: NamedGame?
    var body: some View {
        List(NamedGame.allCases, selection: $selection) { Text($0.rawValue) }
    }
}

private struct NoSelection: View {
    var body: some View {
        List(WarnedGame.allCases) { Text($0.rawValue) }
    }
}

private func warnings(about selection: Any.Type) -> Int {
    SoftTrap.recorded.count { $0.hasPrefix("List's selection holds \(selection),") }
}

@MainActor
@Suite("A List whose selection can name none of its rows")
struct ListSelectionTypeWarningTests {
    #if DEBUG
        @Test("A debug build warns once, and the rows are drawn and select nothing")
        func warnsOnce() {
            let app = TestApp(width: 30, height: 6) { WrongSelection() }
            #expect(app.screen.contains("strata"))
            app.press(.down)
            app.press(.space)
            #expect(warnings(about: WarnedGame.self) == 1)
            let message = _ListCore<WarnedGame, EmptyView, EmptyView>.selectionNamesNoRowMessage(idType: String.self)
            #expect(SoftTrap.recorded.contains(message))
            #expect(message.contains("identified by String"))
        }
    #endif

    @Test("A list whose selection holds its rows' ids, or that has no selection, says nothing")
    func quietOtherwise() {
        let right = TestApp(width: 30, height: 6) { RightSelection() }
        #expect(right.screen.contains("strata"))
        let none = TestApp(width: 30, height: 6) { NoSelection() }
        #expect(none.screen.contains("comet"))
        #expect(warnings(about: NamedGame.self) == 0)
        #expect(warnings(about: Never.self) == 0)
    }
}
