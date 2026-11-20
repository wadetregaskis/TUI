//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderLoopLineStylesTests.swift
//
//  The line styles a frame's root environment says the terminal draws are
//  read once, when the render loop is made, not at every frame: the read
//  is of the whole process environment (`TerminalHost.program`), which was
//  5.9% of a frame of `session/case:timeline-tiles` (B-TLCTRL-6).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

private struct LineStylesApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("lines") }
    }
}

@MainActor
@Suite("The render loop reads the terminal's line styles once")
struct RenderLoopLineStylesTests {
    #if !os(WASI)  // Exit tests need a child process, which WASI cannot start.
        @Test("A frame's line styles are what the loop read when it was made, whatever the environment says later")
        func lineStylesReadOnce() async {
            await #expect(processExitsWith: .success) {
                await MainActor.run {
                    // Off tmux, where the program is named by `TUI_TERM_PROGRAM`:
                    // `TerminalHost.isTmux` latches on its first read, which in
                    // this child is the loop's.
                    ProcessWideState.setEnvironment("TMUX", to: nil)
                    ProcessWideState.setEnvironment("TUI_TERM_PROGRAM", to: "iTerm.app")
                    let loop = RenderLoopHarness().loop(LineStylesApp())
                    let made = loop.buildEnvironment().lineStyleSupport
                    #expect(made == .all, "iTerm2 draws every line style")

                    ProcessWideState.setEnvironment("TUI_TERM_PROGRAM", to: "Apple_Terminal")
                    // A read now would answer otherwise, so the frame's answer
                    // below is the loop's own.
                    #expect(TerminalHost.lineStyles == .plain)
                    #expect(loop.buildEnvironment().lineStyleSupport == made)
                }
            }
        }
    #endif
}
