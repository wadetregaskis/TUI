//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffTerminalActionRunningTests.swift
//
//  `handOffTerminal(running:arguments:)`: the program started inside the
//  hand-off, found in PATH or at a path, its ending reported as a value, a
//  failure to start thrown, and its signals at their defaults. The terminal
//  side, and ⌃Z, are the PTY smoke's (`Tools/Smoke/hand_off_smoke.py`).
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

    import Testing

    @testable import TUIFoundation

    #if canImport(Darwin)
        import Darwin
    #elseif canImport(Glibc)
        import Glibc
    #elseif canImport(Musl)
        import Musl
    #endif

    @MainActor
    @Suite("HandOffTerminalAction running a program")
    struct HandOffTerminalActionRunningTests {
        private let shell = HandOffTerminalAction.Executable.path("/bin/sh")

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
            #expect(try action(running: shell, arguments: ["-c", "exit 3"]) == .exit(3))
            #expect(log == ["out", "back"])
            #expect(try action(running: shell, arguments: ["-c", "true"]) == .exit(0))
        }

        @Test("A name is looked up in PATH, and the arguments follow it")
        func nameInPath() throws {
            let action = HandOffTerminalAction(handOff: nil)
            #expect(try action(running: .name("sh"), arguments: ["-c", "exit $#", "sh", "a", "b"]) == .exit(2))
        }

        @Test("A program ended by a signal says which")
        func uncaughtSignal() throws {
            let action = HandOffTerminalAction(handOff: nil)
            #expect(try action(running: shell, arguments: ["-c", "kill -TERM $$"]) == .uncaughtSignal(SIGTERM))
        }

        @Test("A program that cannot be started is thrown, not reported as an ending")
        func cannotStart() {
            let action = HandOffTerminalAction(handOff: nil)
            #expect(throws: HandOffTerminalAction.LaunchError.couldNotStart(errno: ENOENT)) {
                try action(running: .path("/nonexistent/tui-hand-off-test"))
            }
            #expect(throws: HandOffTerminalAction.LaunchError.couldNotStart(errno: ENOENT)) {
                try action(running: .name("tui-hand-off-test-no-such-program"))
            }
        }

        @Test("The program gets its signals at their defaults, whatever the app ignores")
        func signalsAtTheirDefaults() throws {
            // The app ignores SIGINT and SIGQUIT during a hand-off; SIGUSR2 stands
            // in here, which nothing else in the tests uses. Ignored by this
            // process, it would be ignored by a program spawned without the
            // defaults, which would then exit 0.
            let previous = signal(SIGUSR2, SIG_IGN)
            defer { signal(SIGUSR2, previous) }
            let action = HandOffTerminalAction(handOff: nil)
            #expect(try action(running: shell, arguments: ["-c", "kill -USR2 $$; exit 0"]) == .uncaughtSignal(SIGUSR2))
        }
    }

#endif
