//  🖥️ TUI — A Terminal UI framework for Swift
//  SegmentedPickerPointerTests.swift
//
//  A segmented picker under the pointer: every segment shows the hover, as a
//  button does, and with the focus following the pointer a move onto any
//  segment focuses the picker — not only onto the one its cursor is on. The
//  owner met both in the Settings panel's tab strip (2026-11-10).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("A segmented picker answers the pointer on every segment")
struct SegmentedPickerPointerTests {
    private struct Page: View {
        @State private var size = 2

        var body: some View {
            VStack(alignment: .leading) {
                Button("Go") {}.focusID("go")
                Picker("Size", selection: $size) {
                    Text("Small").tag(1)
                    Text("Medium").tag(2)
                    Text("Large").tag(3)
                }
                .focusID("size")
                .pickerStyle(.segmented)
                Spacer()
            }
        }
    }

    private struct FollowingApp: App {
        var body: some Scene {
            WindowGroup { Page() }
                .focusFollowsPointer()
        }
    }

    /// The styled cells of `text` where it shows: what is drawn there, colours
    /// and all, from its first column to the end of its row.
    private func styledRow(_ app: TestApp, containing text: String) throws -> String {
        let y = try #require(app.screen.lines.firstIndex { $0.contains(text) })
        return app.screen.styledLines[y]
    }

    @Test("A segment the cursor is not on shows the pointer over it", arguments: ["Small", "Large"])
    func hoverShows(_ segment: String) throws {
        let app = TestApp(width: 50, height: 6) { Page() }
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "go")
        let resting = try styledRow(app, containing: segment)
        try app.hover(over: segment)
        let hovered = try styledRow(app, containing: segment)
        #expect(hovered != resting, "the pointer over \(segment) changed nothing drawn")
        app.hover(at: CellPoint(x: 40, y: 4))
        #expect(try styledRow(app, containing: segment) == resting, "the hover outlived the pointer")
    }

    @Test("With the focus following the pointer, a move onto any segment focuses the picker", arguments: ["Small", "Medium", "Large", "│"])
    func pointerFocuses(_ segment: String) throws {
        let app = TestApp(FollowingApp(), width: 50, height: 6)
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "go")
        try app.hover(over: segment)
        #expect(app.focusedID == "size", "a move onto \(segment) left the focus on \(app.focusedID ?? "nothing")")
    }

    private struct RadioPage: View {
        @State private var size = 2

        var body: some View {
            VStack(alignment: .leading) {
                Button("Go") {}.focusID("go")
                Picker("Size", selection: $size) {
                    Text("Small").tag(1)
                    Text("Medium").tag(2)
                    Text("Large").tag(3)
                }
                .focusID("size")
                .pickerStyle(.radioGroup)
                Spacer()
            }
        }
    }

    private struct FollowingRadioApp: App {
        var body: some Scene {
            WindowGroup { RadioPage() }
                .focusFollowsPointer()
        }
    }

    /// The radio group is one focus stop drawn as several regions, as the
    /// segmented picker is, and had the same fault: only the option under its
    /// cursor named the group.
    @Test("With the focus following the pointer, a move onto any option of a radio group focuses it", arguments: ["Small", "Medium", "Large"])
    func radioPointerFocuses(_ option: String) throws {
        let app = TestApp(FollowingRadioApp(), width: 50, height: 8)
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "go")
        try app.hover(over: option)
        #expect(app.focusedID == "size", "a move onto \(option) left the focus on \(app.focusedID ?? "nothing")")
    }
}
