//  🖥️ TUI — A Terminal UI framework for Swift
//  NoTerminalTests.swift
//
//  What an app is told when it has no terminal to draw on. Real descriptors:
//  what `isatty` and `fstat` say of them is the point. The whole path, from a
//  launch to its exit status, is `Tools/Smoke/no_terminal_smoke.py`'s.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

@Suite("NoTerminal")
struct NoTerminalTests {
    /// A pseudo-terminal's two ends, closed at the end of `body`.
    private func withTerminal(_ body: (Int32) throws -> Void) throws {
        var controller: Int32 = -1
        var device: Int32 = -1
        try #require(openpty(&controller, &device, nil, nil, nil) == 0)
        defer {
            close(controller)
            close(device)
        }
        try body(device)
    }

    /// A pipe's two ends, closed at the end of `body`.
    private func withPipe(_ body: (_ read: Int32, _ write: Int32) throws -> Void) throws {
        var ends: [Int32] = [-1, -1]
        try #require(pipe(&ends) == 0)
        defer {
            close(ends[0])
            close(ends[1])
        }
        try body(ends[0], ends[1])
    }

    private let colour = ["TERM": "xterm-256color"]

    @Test("A terminal for both is no situation at all")
    func terminalForBoth() throws {
        try withTerminal { terminal in
            #expect(NoTerminal.current(input: terminal, output: terminal, environment: colour) == nil)
        }
    }

    @Test("Stdout down a pipe: output is what lacks, and the pipe is kept to write to")
    func stdoutAPipe() throws {
        try withTerminal { terminal in
            try withPipe { read, write in
                let situation = try #require(NoTerminal.current(input: terminal, output: write, environment: colour))
                #expect(situation.input == .terminal)
                #expect(situation.output == .pipe)
                #expect(situation.lacksOutput)
                #expect(!situation.lacksInput)
                #expect(situation.pipedInput == nil)

                // Another descriptor for the same pipe, so it outlives a redirect.
                let kept = try #require(situation.pipedOutput)
                #expect(kept.fileDescriptor != write)
                kept.write(Data("kept".utf8))
                var bytes = [UInt8](repeating: 0, count: 4)
                #expect(readBytes(read, &bytes) == 4)
                #expect(String(bytes: bytes, encoding: .utf8) == "kept")
            }
        }
    }

    @Test("Stdin /dev/null: a device, with nothing to keep")
    func stdinDevNull() throws {
        let null = open("/dev/null", O_RDONLY)
        defer { close(null) }
        try withTerminal { terminal in
            let situation = try #require(NoTerminal.current(input: null, output: terminal, environment: colour))
            #expect(situation.input == .device)
            #expect(situation.output == .terminal)
            #expect(situation.lacksInput)
            #expect(!situation.lacksOutput)
            #expect(situation.pipedInput == nil)
        }
    }

    @Test("A regular file, and a closed stream")
    func fileAndClosed() throws {
        let path = NSTemporaryDirectory() + "tui-no-terminal-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = open(path, O_RDONLY)
        defer { close(file) }
        var closed = dup(file)
        close(closed)
        defer { closed = -1 }
        let situation = try #require(NoTerminal.current(input: file, output: closed, environment: colour))
        #expect(situation.input == .file)
        #expect(situation.output == .closed)
        #expect(situation.pipedInput != nil)
        #expect(situation.pipedOutput == nil)
    }

    @Test("TERM=dumb: a terminal to read keys from, but not to draw on")
    func dumbTerminal() throws {
        try withTerminal { terminal in
            let situation = try #require(
                NoTerminal.current(input: terminal, output: terminal, environment: ["TERM": "dumb"]))
            #expect(situation.input == .terminal)
            #expect(situation.output == .dumbTerminal)
            #expect(situation.lacksOutput)
            #expect(!situation.lacksInput)
            #expect(!situation.canDrawOnControllingTerminal)
        }
    }

    @Test("An unset TERM is not a dumb one: it is no evidence of anything")
    func unsetTERM() throws {
        try withTerminal { terminal in
            #expect(NoTerminal.current(input: terminal, output: terminal, environment: [:]) == nil)
        }
    }

    @Test("Each situation has its own one line")
    func messages() throws {
        try withTerminal { terminal in
            try withPipe { read, write in
                let noOutput = try #require(NoTerminal.current(input: terminal, output: write, environment: colour))
                let noInput = try #require(NoTerminal.current(input: read, output: terminal, environment: colour))
                let neither = try #require(NoTerminal.current(input: read, output: write, environment: colour))
                let dumb = try #require(
                    NoTerminal.current(input: terminal, output: terminal, environment: ["TERM": "dumb"]))
                let lines = [noOutput.message, noInput.message, neither.message, dumb.message]
                #expect(Set(lines).count == 4)
                #expect(lines.allSatisfy { !$0.isEmpty && !$0.contains("\n") })
            }
        }
    }

    @Test("An integer literal is an exit status")
    func outcomeLiteral() {
        let outcome: NoTerminal.Outcome = 3
        #expect(outcome == .exit(3))
    }

    /// `read(2)`, named apart from the closure parameters above.
    private func readBytes(_ descriptor: Int32, _ bytes: inout [UInt8]) -> Int {
        bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
    }
}
