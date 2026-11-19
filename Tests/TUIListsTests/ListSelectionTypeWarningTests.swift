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

/// An id of its own, so a list over it whose selection matches says nothing
/// whatever other suites warned about.
private struct ShelfMark: Hashable, Sendable {
    let name: String
}

/// A node of an outline, or a row of a section, identified by `ID`.
private struct Node<ID: Hashable & Sendable>: Identifiable, Sendable {
    let id: ID
    var children: [Self]?
}

/// Selections no row's id is: one for each arrangement, each warned about once.
private enum OutlineChoice: Hashable, Sendable { case one }
private enum SectionChoice: Hashable, Sendable { case one }

private struct WrongOutlineSelection: View {
    @State private var selection: OutlineChoice?
    var body: some View {
        List([Node(id: "strata", children: [Node(id: "comet")])], children: \.children, selection: $selection) {
            Text($0.id)
        }
    }
}

private struct WrongSectionSelection: View {
    @State private var selection: SectionChoice?
    var body: some View {
        List(selection: $selection) {
            ForEach([Node(id: "Arcade", children: [Node(id: "strata")])]) { shelf in
                Section(shelf.id) { ForEach(shelf.children ?? []) { Text($0.id) } }
            }
        }
    }
}

private struct RightOutlineAndSections: View {
    @State private var selection: ShelfMark?
    private let nodes = [Node(id: ShelfMark(name: "strata"), children: [Node(id: ShelfMark(name: "comet"))])]
    var body: some View {
        VStack {
            List(nodes, children: \.children, selection: $selection) { Text($0.id.name) }.frame(height: 3)
            List(selection: $selection) {
                ForEach(nodes) { shelf in
                    Section(shelf.id.name) { ForEach(shelf.children ?? []) { Text($0.id.name) } }
                }
            }
            .frame(height: 3)
        }
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

        @Test("An outline's rows, and a ForEach of Sections' rows, are warned about too")
        func outlinesAndSections() {
            // The outline's rows are not drawn at all (the eager path leaves
            // out a row it cannot name), so the screen is not checked here.
            let outline = TestApp(width: 30, height: 6) { WrongOutlineSelection() }
            outline.press(.down)
            #expect(warnings(about: OutlineChoice.self) == 1)
            #expect(
                SoftTrap.recorded.contains(
                    _ListCore<OutlineChoice, EmptyView, EmptyView>.selectionNamesNoRowMessage(idType: String.self)))
            let sections = TestApp(width: 30, height: 6) { WrongSectionSelection() }
            #expect(sections.screen.contains("strata"))
            sections.press(.down)
            #expect(warnings(about: SectionChoice.self) == 1)
            #expect(
                SoftTrap.recorded.contains(
                    _ListCore<SectionChoice, EmptyView, EmptyView>.selectionNamesNoRowMessage(idType: String.self)))
        }
    #endif

    @Test("An outline or a ForEach of Sections whose rows the selection names says nothing")
    func outlinesAndSectionsQuietOtherwise() {
        let app = TestApp(width: 30, height: 8) { RightOutlineAndSections() }
        #expect(app.screen.contains("strata"))
        #expect(warnings(about: ShelfMark.self) == 0)
    }

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
