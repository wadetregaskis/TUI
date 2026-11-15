//  🖥️ TUI — A Terminal UI framework for Swift
//  CopyToClipboardTests.swift
//
//  `\.copyToClipboard`: an app's own command puts text on the clipboard the
//  way `.copyable`'s ⌃C does, and a test reads what it put there from
//  `TestApp.clipboard` (tuitree's feedback, Milestone 2 item 5). Written as an
//  app's tests are, with no `@testable`, so the API is shown to be public.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

private struct PathCopier: View {
    @Environment(\.copyToClipboard) private var copyToClipboard

    var body: some View {
        Button("Copy Path") { copyToClipboard(".a[1]") }
    }
}

@MainActor
@Suite("Copying from an app's own command")
struct CopyToClipboardTests {
    @Test("The action puts the text on the clipboard, and a test reads it")
    func copies() {
        let app = TestApp(width: 30, height: 4) { PathCopier() }
        #expect(app.clipboard == nil)
        app.press(.space)
        #expect(app.clipboard == ".a[1]")
    }
}
