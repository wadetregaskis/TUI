//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusStateResignTests.swift
//
//  An app's `@FocusState = nil` (or `false`) is honoured: nothing is focused
//  until Tab, an arrow or a click, as in SwiftUI, where the probe's field
//  resigned and nothing took the focus until the next Tab
//  (`Tools/SwiftUIProbes/Default focus priority (H-70)/`). The owner's ruling
//  O-12 (a), 2026-11-21, narrowing the automatic first focus (I5); hunt
//  FOCUS-6.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIFoundation
import TUITesting
import TUITextInput

/// What the views under test saw, in order.
private final class Log: @unchecked Sendable {
    var entries: [String] = []
}

/// A name field that resigns the focus on Return, as SwiftUI's idiom does,
/// with a button ahead of it unless `fieldFirst`.
private struct SubmitPage: View {
    let log: Log
    var fieldFirst = true
    @State private var name = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack {
            if !fieldFirst { Button("Top") {}.focusID("top") }
            TextField("Name", text: $name)
                .focusID("name")
                .focused($isEditing)
                .onSubmit { isEditing = false }
            Button("OK") {}.focusID("ok")
        }
        .onChange(of: isEditing) { _, editing in log.entries.append("\(editing)") }
    }
}

@MainActor
@Suite("@FocusState resigning the focus")
struct FocusStateResignTests {

    @Test("Writing false in onSubmit leaves nothing focused; Tab then focuses the first stop")
    func resignInOnSubmit() {
        let log = Log()
        let app = TestApp(width: 40, height: 8) { SubmitPage(log: log) }
        #expect(app.focusedID == "name")
        let before = log.entries.count
        app.press(.enter)
        // Read after the frames the resignation asked for: none gave it back.
        #expect(app.focusedID == nil, "no later frame gives the field the focus back")
        #expect(Array(log.entries.dropFirst(before)) == ["false"], "one resignation, and no focus regained")
        app.press(.tab)
        #expect(app.focusedID == "name")
    }

    @Test("A field that is not first resigns to nothing, not to the top of the page")
    func resignDoesNotJumpToTop() {
        let log = Log()
        let app = TestApp(width: 40, height: 8) { SubmitPage(log: log, fieldFirst: false) }
        #expect(app.focusedID == "top")
        app.press(.tab)
        #expect(app.focusedID == "name")
        app.press(.enter)
        #expect(app.focusedID == nil)
        app.press(.down)
        #expect(app.focusedID != nil, "an arrow puts the focus back in the ring")
    }
}
