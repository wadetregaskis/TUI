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

    /// The system's setting is one of the things TUI would otherwise do, so the
    /// variable beats it each way, and the scene can only add to what's left.
    @Test("Each accessibility variable beats the system's setting, each way")
    func accessibilityOverSystem() {
        for (preference, name, _) in AccessibilityPreferences.named {
            func applies(_ variable: String?, system: Bool) -> Bool {
                let environment = Self.environment(name, variable)
                let host: AccessibilityPreferences = system ? preference : []
                return TerminalClient.accessibilityRequested(environment: environment)
                    .union(host.subtracting(TerminalClient.accessibilityDeclined(environment: environment)))
                    .contains(preference)
            }
            #expect(!applies(nil, system: false), "\(name)")
            #expect(applies(nil, system: true), "\(name)")
            #expect(applies("1", system: false), "\(name)")
            #expect(!applies("0", system: true), "\(name)")
            // A value it doesn't know is ignored, and an empty one is unset.
            #expect(applies("yes", system: true), "\(name)")
            #expect(applies("", system: true), "\(name)")
        }
    }

    @Test("COLUMNS and LINES beat what the terminal measures, and a report beats them")
    func sizeOverTerminal() {
        func size(
            reported: (width: Int, height: Int)? = nil, columns: Int? = nil, lines: Int? = nil,
            measured: (width: Int, height: Int)? = (100, 30)
        ) -> (width: Int, height: Int) {
            Terminal.size(reported: reported, columns: columns, lines: lines, measured: measured)
        }
        #expect(size() == (100, 30))
        #expect(size(measured: nil) == (80, 24))
        // Gospel, each on its own axis, measured or not.
        #expect(size(columns: 60, lines: 20) == (60, 20))
        #expect(size(columns: 60) == (60, 30))
        #expect(size(lines: 20) == (100, 20))
        #expect(size(columns: 60, measured: nil) == (60, 24))
        #expect(size(lines: 20, measured: nil) == (80, 20))
        // The browser page: started with the variables, then reporting each new size.
        #expect(size(reported: (164, 45), columns: 60, lines: 20) == (164, 45))
    }
}
