//  🖥️ TUI — A Terminal UI framework for Swift
//  EnvironmentVariablePrecedenceTests.swift
//
//  The rule at the top of the Environment Variables article, asked of every setting that
//  has both a variable and a global setting in code, all in one place: code, then the
//  variable, then what TUI would do anyway. Each ladder has tests of its own beside it;
//  these say that they all follow one rule, and pin the one that deliberately doesn't.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUITerminalHost

@Suite("Code, then the variable, then the default")
@MainActor
struct EnvironmentVariablePrecedenceTests {
    /// One setting's ladder, asked on its inputs, with what it does by default `defaulted`.
    private typealias Ladder = (_ code: Bool?, _ variable: String?, _ defaulted: Bool) -> Bool

    private static func environment(_ name: String, _ value: String?) -> [String: String] {
        value.map { [name: $0] } ?? [:]
    }

    /// Asks `ladder` the whole of the rule.
    private func expectTheRule(_ name: String, _ ladder: Ladder) {
        // The default, with nothing stated.
        #expect(ladder(nil, nil, true), "\(name)")
        #expect(!ladder(nil, nil, false), "\(name)")
        // The variable beats the default, each way.
        #expect(ladder(nil, "1", false), "\(name)")
        #expect(!ladder(nil, "0", true), "\(name)")
        // A value it doesn't know is ignored, and an empty one is unset.
        #expect(ladder(nil, "yes", true), "\(name)")
        #expect(!ladder(nil, "yes", false), "\(name)")
        #expect(ladder(nil, "", true), "\(name)")
        // Code beats the variable, each way.
        #expect(ladder(true, "0", false), "\(name)")
        #expect(!ladder(false, "1", true), "\(name)")
    }

    @Test("Pictures")
    func graphics() {
        expectTheRule("TUI_GRAPHICS") { code, variable, defaulted in
            TerminalClient.graphicsSupported(
                override: code, environment: Self.environment("TUI_GRAPHICS", variable), detected: defaulted)
        }
    }

    @Test("Hairlines")
    func hairlines() {
        expectTheRule("TUI_HAIRLINES") { code, variable, defaulted in
            TerminalClient.hairlinesSupported(
                override: code, environment: Self.environment("TUI_HAIRLINES", variable), graphics: defaulted,
                program: .ghostty, reportsCellPixels: true)
        }
    }

    @Test("Pictures under text")
    func picturesUnderText() {
        expectTheRule("TUI_PICTURES_UNDER_TEXT") { code, variable, defaulted in
            TerminalClient.picturesUnderTextSupported(
                override: code, environment: Self.environment("TUI_PICTURES_UNDER_TEXT", variable),
                graphics: defaulted, program: .ghostty)
        }
    }

    @Test("Hyperlinks")
    func hyperlinks() {
        expectTheRule("TUI_HYPERLINKS") { code, variable, defaulted in
            TerminalClient.hyperlinksSupported(
                override: code, environment: Self.environment("TUI_HYPERLINKS", variable),
                program: defaulted ? .iTerm2 : .appleTerminal)
        }
    }

    @Test("Copying more than text")
    func mimeClipboard() {
        expectTheRule("TUI_OSC5522") { code, variable, defaulted in
            TerminalClient.mimeClipboard(
                environment: Self.environment("TUI_OSC5522", variable), override: code, detected: defaulted)
        }
    }

    @Test("Pointer shapes: code, then the variable, then what the terminal is")
    func pointerShapes() {
        // `KITTY_WINDOW_ID` is a terminal the table has, with no version to doubt.
        func host(_ code: Bool?, _ variable: String?, knownTerminal: Bool = false) -> Bool {
            var environment = Self.environment("TUI_POINTER_SHAPES", variable)
            if knownTerminal { environment["KITTY_WINDOW_ID"] = "1" }
            return TerminalClient.pointerShapeHost(override: code, environment: environment) != nil
        }
        #expect(!host(nil, nil))
        #expect(host(nil, nil, knownTerminal: true))
        #expect(host(nil, "1"))
        #expect(!host(nil, "0", knownTerminal: true))
        #expect(host(true, "0"))
        #expect(!host(false, "1", knownTerminal: true))
    }

    /// The exception: a person saying "not on this machine" isn't something the
    /// program can know better about.
    @Test("TUI_OPEN_URLS=0 is what code can't undo, and `1` is what code can")
    func openingURLs() {
        func opens(_ code: Bool?, _ variable: String?) -> Bool {
            TerminalClient.urlOpeningEnabled(override: code, environment: Self.environment("TUI_OPEN_URLS", variable))
        }
        #expect(!opens(nil, nil))
        #expect(opens(nil, "1"))
        #expect(opens(true, nil))
        #expect(!opens(false, "1"))
        #expect(!opens(true, "0"))
    }
}
