//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppColorDepthTests.swift
//
//  A TestApp's colours do not depend on where its tests run: `swift test` sets
//  NO_COLOR whenever its output is not a terminal, and TERM and COLORTERM
//  differ from one machine to the next. No `@testable`, as a client's tests.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

@MainActor
@Suite("A TestApp draws in the same colours wherever its tests run")
struct TestAppColorDepthTests {
    /// One word in pure red, which 24-bit colour sends as `38;2;255;0;0`.
    private static func redWord() -> TestApp {
        TestApp(width: 10, height: 1) { Text("red").foregroundStyle(Color(red: 1, green: 0, blue: 0)) }
    }

    #if !os(WASI)  // Exit tests need a child process, which WASI cannot start.
        @Test("It draws in 24-bit colour, though the process's own depth is no colour, as NO_COLOR makes it")
        func ignoresTheProcessDepth() async {
            await #expect(processExitsWith: .success) {
                await MainActor.run {
                    // An exit test's child, where no other test runs: the process's
                    // depth is this test's to set, as a piped `swift test`'s
                    // NO_COLOR sets it for an app's tests.
                    // swiftlint:disable:next process_wide_write_in_tests
                    ColorDepth.current = .noColor
                    #expect(Self.redWord().screen.styledLines[0].contains("38;2;255;0;0"))
                }
            }
        }
    #endif

    @Test("A depth the test pins is the depth it draws in")
    func honoursTheTestsPin() {
        ColorDepth.withCurrent(.noColor) {
            let screen = Self.redWord().screen
            #expect(screen.lines[0] == "red")
            #expect(!screen.styledLines[0].contains("38;"))
        }
        ColorDepth.withCurrent(.palette256) {
            #expect(Self.redWord().screen.styledLines[0].contains("38;5;"))
        }
    }
}
