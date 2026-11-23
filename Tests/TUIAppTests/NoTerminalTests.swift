//  🖥️ TUI — A Terminal UI framework for Swift
//  NoTerminalTests.swift
//
//  What an app is told when it has no terminal to draw on. Real descriptors:
//  what `isatty` and `fstat` say of them is the point. The whole path, from a
//  launch to its exit status, is `Tools/Smoke/no_terminal_smoke.py`'s.
//
//  Created by Wade Tregaskis
//  License: MIT

// What wasip1's streams are is the host's to say, so `NoTerminal` asks nothing
// there (no `current`), and the tests' terminals and pipes do not exist.
// Pipes and descriptors as POSIX has them; Windows asks its handles
// (NoTerminal.swift's Windows arm), measured under ConPTY: Windows port.md.
#if !canImport(WASILibc) && !os(Windows)

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

/// An app that says it reached its launch by the status it exits with.
private struct LaunchReachedApp: App {
    var body: some Scene { WindowGroup { Text("Not drawn") } }

    static func runWithoutTerminal(_ situation: NoTerminal) async -> NoTerminal.Outcome {
        .exit(23)
    }
}

@Suite("NoTerminal")
struct NoTerminalTests {
    /// An exit test's standard streams are no terminal. On a terminal, `run()` is `main()`'s last two lines.
    @Test("An app run from an instance asks what to do without a terminal, as main() does")
    func instanceRunAsks() async {
        await #expect(processExitsWith: .exitCode(23)) {
            await LaunchReachedApp().run()
        }
    }

    /// A pseudo-terminal's two ends, closed at the end of `body`.
    private func withTerminal(_ body: (Int32) throws -> Void) throws {
        var controller: Int32 = -1
        var device: Int32 = -1
        try unsafe #require(openpty(&controller, &device, nil, nil, nil) == 0)
        defer {
            close(controller)
            close(device)
        }
        try body(device)
    }

    /// A pipe's two ends, closed at the end of `body`.
    private func withPipe(_ body: (_ read: Int32, _ write: Int32) throws -> Void) throws {
        var ends: [Int32] = [-1, -1]
        try unsafe #require(pipe(&ends) == 0)
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
        let null = unsafe open("/dev/null", O_RDONLY)
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
        _ = FileManager.default.createFile(atPath: path, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = unsafe open(path, O_RDONLY)
        defer { close(file) }
        // -1, not a descriptor opened and closed here: tests run in parallel, and another
        // test's pipe can be handed the number just freed, which then reads as a pipe.
        let closed: Int32 = -1
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

    /// An exit test, for a session and a controlling terminal of its own: the
    /// test process's are the runner's, and `setsid` is not undone.
    @Test("Pointed at the controlling terminal, stdin is a terminal the notifier can wait on, not input at its end")
    func pointedAtControllingTerminal() async {
        await #expect(processExitsWith: .exitCode(0)) {
            exit(stdinPointedAtControllingTerminal())
        }
    }

    @Test("An integer literal is an exit status")
    func outcomeLiteral() {
        let outcome: NoTerminal.Outcome = 3
        #expect(outcome == .exit(3))
    }

    /// `read(2)`, named apart from the closure parameters above.
    private func readBytes(_ descriptor: Int32, _ bytes: inout [UInt8]) -> Int {
        bytes.withUnsafeMutableBytes { unsafe read(descriptor, $0.baseAddress, $0.count) }
    }
}

/// In an exit test's own process: a session of its own with a pseudo-terminal
/// for its controlling terminal, stdin a pipe at its end and stdout the
/// terminal, as in `cat data | app`; then what ``NoTerminal/Outcome/drawOnControllingTerminal``
/// does. Returns 0 when stdin is then a terminal that `poll` can wait on and the
/// stdin notifier does not take for input at its end, or the step that failed.
///
/// On Darwin, stdin pointed at `/dev/tty` failed both: `poll` answered
/// `POLLNVAL`, which `isAtEndOfInput` took for readable with nothing to read,
/// so the run loop watched nothing and never heard ⌃Q (18). A free function,
/// as an exit test's body cannot capture the suite.
private func stdinPointedAtControllingTerminal() -> Int32 {
    guard setsid() >= 0 else { return 10 }
    var controller: Int32 = -1
    var device: Int32 = -1
    guard unsafe openpty(&controller, &device, nil, nil, nil) == 0 else { return 11 }
    #if canImport(Glibc) || canImport(Musl)
        let makesControlling = ioctl(device, UInt(TIOCSCTTY), 0)
    #else
        let makesControlling = ioctl(device, TIOCSCTTY, 0)
    #endif
    guard makesControlling == 0 else { return 12 }
    var ends: [Int32] = [-1, -1]
    guard unsafe pipe(&ends) == 0 else { return 13 }
    close(ends[1])
    guard dup2(ends[0], STDIN_FILENO) >= 0 else { return 14 }
    guard let situation = NoTerminal.current(output: device, environment: ["TERM": "xterm-256color"]),
        situation.lacksInput, !situation.lacksOutput
    else { return 15 }
    guard situation.pointStandardStreamsAtControllingTerminal() else { return 16 }
    guard isatty(STDIN_FILENO) == 1 else { return 17 }
    // Nothing typed: not ready, where `/dev/tty` on Darwin answered POLLNVAL at once.
    var probe = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    guard unsafe poll(&probe, 1, 0) == 0 else { return 18 }
    return StdinArrivalNotifier.isAtEndOfInput(STDIN_FILENO) ? 19 : 0
}

#endif
