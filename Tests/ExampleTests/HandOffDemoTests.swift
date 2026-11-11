//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffDemoTests.swift
//
//  The Terminal page's hand-off demo: how its helper reports a program's end,
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
    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
        @Test("A program's exit status comes back, and a signal that ends it as 128 plus its number")
        func foregroundCommandStatus() {
            #expect(ForegroundCommand.run(["/bin/sh", "-c", "exit 3"]) == 3)
            #expect(ForegroundCommand.run(["/bin/sh", "-c", "kill -TERM $$"]) == 143, "128 plus SIGTERM's 15")
            #expect(ForegroundCommand.run(["/no/such/program"]) == nil, "a program that cannot start says so")
        }
    #endif

    @Test("The Terminal page has the section, its button named for the editor")
    func section() {
        let app = TestApp(width: 100, height: 200) { TerminalPage() }
        #expect(app.screen.contains(L("page.terminal.handOffEdit")))
        #expect(app.screen.contains(L("page.terminal.handOffDefault")))
    }
}

#endif
