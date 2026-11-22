//  🖥️ TUI — A Terminal UI framework for Swift
//  HelperProcessInputTests.swift
//
//  A helper TUI starts reads none of the person's keys: its standard input is
//  the null device, never the app's own, which is the terminal in raw mode.
//
//  Created by Wade Tregaskis
//  License: MIT

// The helpers are subprocesses, which wasip1 cannot start, and the stand-in is
// `/bin/sh`, which Windows does not have (where the clipboard and the opener
// are the system's API, and `runBounded`'s `/usr/bin/env` is not there).
#if !canImport(WASILibc) && !os(Windows)

import Foundation
import Testing

@testable import TUIApp
@testable import TUITerminalHost

/// Each child asks whether its standard input is the null device itself
/// (`-ef`: the same file). Inherited, it is whatever the test process's is: a
/// terminal or a pipe when the suite is run from a shell, so these fail there
/// without the fix. A runner whose own standard input is already the null
/// device cannot tell the two apart, as no app run that way can either.
@Suite("Helpers read no keys")
struct HelperProcessInputTests {
    private static let script = "[ /dev/stdin -ef /dev/null ] && echo null || echo inherited"

    @Test("A bounded command (tmux's) gets the null device as its input")
    func boundedCommand() {
        #expect(TerminalHost.runBounded(["sh", "-c", Self.script], timeoutMilliseconds: 60_000) == "null\n")
    }

    @Test("A paste helper, which is given no input, gets the null device as its input")
    func pasteHelper() {
        let output = SystemClipboard.run(
            tool: "/bin/sh", arguments: ["-c", Self.script], writing: nil, readsOutput: true, deadline: 60)
        #expect(output.flatMap { String(bytes: $0, encoding: .utf8) } == "null\n")
    }
}

#endif
