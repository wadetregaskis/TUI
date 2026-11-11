//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffDemoTests.swift
//
//  The Terminal page's hand-off demo: how it shows an editor's end,
//  and the section on the page.
//
//  Created by Wade Tregaskis
//  License: MIT

// Only where the package can depend on the app (see Package.swift).
#if canImport(Example)

import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Example's hand-off demo")
struct HandOffDemoTests {
    @Test("An editor's ending reads as a shell's status: a signal as 128 plus its number")
    func endingAsStatus() {
        #expect(HandOffDemo.describe(.exit(3)) == "3")
        #expect(HandOffDemo.describe(.uncaughtSignal(15)) == "143", "128 plus SIGTERM's 15")
    }

    @Test("The Terminal page has the section, its button named for the editor")
    func section() {
        let app = TestApp(width: 100, height: 200) { TerminalPage() }
        #expect(app.screen.contains(L("page.terminal.handOffEdit")))
        #expect(app.screen.contains(L("page.terminal.handOffDefault")))
    }
}

#endif
