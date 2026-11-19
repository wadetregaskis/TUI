//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffTerminalActionRunningWindowsTests.swift
//
//  `handOffTerminal(running:arguments:)` on Windows: the program started with
//  `CreateProcessW` inside the hand-off, its exit status reported as a value,
//  its arguments quoted so that it reads them back whole, and a failure to
//  start thrown.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import Testing
import WinSDK

@testable import TUIFoundation

@MainActor
@Suite("HandOffTerminalAction running a program, on Windows")
struct HandOffTerminalActionRunningWindowsTests {
    @Test("The program runs inside the hand-off, and its exit status comes back as a value")
    func exitStatus() throws {
        var log: [String] = []
        let handOff = TerminalHandOff()
        handOff.handler = { body in
            log.append("out")
            body()
            log.append("back")
        }
        let action = HandOffTerminalAction(handOff: handOff)
        #expect(try action(running: .name("cmd.exe"), arguments: ["/d", "/c", "exit 3"]) == .exit(3))
        #expect(log == ["out", "back"])
        #expect(try action(running: .name("cmd"), arguments: ["/d", "/c", "exit 0"]) == .exit(0))
    }

    @Test("Each argument reaches the program whole: spaces, quotes and backslashes")
    func argumentsArriveWhole() {
        let words = [
            #"C:\Program Files\app.exe"#, "plain", "two words", "", #"a "quoted" word"#, #"C:\trailing\"#,
            #"C:\path with\ space\"#, #"\\"#, "tab\u{9}in", #"\"quote\""#,
        ]
        let line = HandOffTerminalAction.ForegroundProgram.commandLine(words)
        // Windows' own parser, whose rules a program's C runtime follows.
        var count: Int32 = 0
        let parsed: [String] = line.withCString(encodedAs: UTF16.self) { line in
            guard let argv = CommandLineToArgvW(line, &count) else { return [] }
            defer { _ = LocalFree(argv) }
            return (0..<Int(count)).map { String(decodingCString: argv[$0]!, as: UTF16.self) }
        }
        #expect(parsed == words)
    }

    @Test("The command line quotes only what needs it, as the C runtime reads it back")
    func commandLine() {
        let line = HandOffTerminalAction.ForegroundProgram.commandLine
        #expect(line(["edit", "notes.txt"]) == "edit notes.txt")
        #expect(line(["edit", "my notes.txt"]) == #"edit "my notes.txt""#)
        #expect(line(["x", ""]) == #"x """#)
        #expect(line(["x", #"say "hi""#]) == #"x "say \"hi\"""#)
        #expect(line(["x", #"C:\dir with space\"#]) == #"x "C:\dir with space\\""#)
        #expect(line(["x", #"C:\no\space\"#]) == #"x C:\no\space\"#)
    }

    @Test("A program that cannot be started is thrown, not reported as an ending")
    func cannotStart() {
        let action = HandOffTerminalAction(handOff: nil)
        #expect(throws: HandOffTerminalAction.LaunchError.couldNotStart(errno: ENOENT)) {
            try action(running: .path(#"C:\nonexistent\tui-hand-off-test.exe"#))
        }
        #expect(throws: HandOffTerminalAction.LaunchError.couldNotStart(errno: ENOENT)) {
            try action(running: .name("tui-hand-off-test-no-such-program"))
        }
    }
}

#endif
