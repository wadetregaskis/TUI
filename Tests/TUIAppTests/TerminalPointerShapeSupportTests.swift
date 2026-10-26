//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalPointerShapeSupportTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUITerminalHost

/// Which hosts are spoken to in OSC 22, in whose names, and how the answer is
/// reached — read from each host's documentation and source, 2026-10-19 (see
/// `Documentation/Terminals/Terminal compatibility survey.md`, "Pointer
/// shapes (OSC 22)"). Everything is asked on its inputs: nothing here reads
/// or sets the process's environment.
@Suite("Terminal pointer shape support")
struct TerminalPointerShapeSupportTests {

    @Test(
        "The documented hosts are found by the environment they set, at a version that takes OSC 22",
        arguments: [
            (["TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": "1.3.1"], PointerShapeHost.ghostty),
            (["TERM_PROGRAM": "ghostty"], .ghostty),
            (["TERM": "xterm-ghostty"], .ghostty),
            (["TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.6.11"], .iTerm2),
            (["TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.5.0"], .iTerm2),
            (["LC_TERMINAL": "iTerm2", "LC_TERMINAL_VERSION": "3.5.2"], .iTerm2),
            (["TERM": "xterm-kitty"], .kitty),
            (["TERM": "xterm-256color", "KITTY_WINDOW_ID": "1"], .kitty),
            (["TERM": "foot"], .foot),
            (["TERM": "foot-extra"], .foot),
            (["TERM": "xterm-256color", "XTERM_VERSION": "XTerm(390)"], .xterm),
            (["TERM": "xterm-256color", "XTERM_VERSION": "XTerm(367)"], .xterm),
            (["TERM": "xterm-kitty", "TERM_PROGRAM": "vscode"], .kitty),
        ] as [([String: String], PointerShapeHost)])
    func documentedHosts(environment: [String: String], host: PointerShapeHost) {
        #expect(PointerShapeHost.detect(environment: environment) == host)
    }

    @Test(
        "Every other terminal is left alone: tmux, Apple Terminal, Warp, an unnamed one, and a release too old",
        arguments: [
            ["TERM_PROGRAM": "tmux", "TMUX": "/tmp/tmux-501/default,1,0", "KITTY_WINDOW_ID": "1"],
            ["TMUX": "/tmp/tmux-501/default,1,0", "TERM": "xterm-kitty"],
            ["TERM_PROGRAM": "Apple_Terminal"],
            ["TERM_PROGRAM": "WarpTerminal"],
            ["TERM": "xterm-256color"],
            [:],
            ["TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": "0.9.0"],
            ["TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.4.23"],
            ["LC_TERMINAL": "iTerm2", "LC_TERMINAL_VERSION": "3.4.0"],
            ["XTERM_VERSION": "XTerm(366)"],
        ])
    func otherTerminals(environment: [String: String]) {
        #expect(PointerShapeHost.detect(environment: environment) == nil)
    }

    @Test(
        "A terminal named beside another's inherited variables, or a screen or zellij session, is left alone",
        arguments: [
            ["TERM_PROGRAM": "vscode", "TERM": "xterm-256color", "KITTY_WINDOW_ID": "1"],
            ["TERM_PROGRAM": "WezTerm", "TERM": "xterm-256color", "XTERM_VERSION": "XTerm(390)"],
            ["TERM_PROGRAM": "ghostty", "TERM": "screen.xterm-256color", "STY": "4242.pts-0.host"],
            ["TERM_PROGRAM": "iTerm.app", "ZELLIJ": "0", "ZELLIJ_SESSION_NAME": "work"],
            ["TERM": "xterm-kitty", "ZELLIJ_SESSION_NAME": "work"],
        ])
    func inheritedOrMultiplexed(environment: [String: String]) {
        #expect(PointerShapeHost.detect(environment: environment) == nil)
    }

    @Test("A version is compared part by part, a missing part read as 0 and a suffix ignored")
    func versions() {
        func atLeast(_ version: String, _ minimum: [Int]) -> Bool {
            PointerShapeHost.version(
                ["TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": version], program: "ghostty", atLeast: minimum)
        }
        #expect(atLeast("1", [1, 0]))
        #expect(atLeast("1.0.0", [1, 0]))
        #expect(atLeast("1.3.1-main+0abc", [1, 0]))
        #expect(atLeast("10.0", [3, 5]))
        #expect(!atLeast("0.9.9", [1, 0]))
        #expect(!atLeast("3.4.99", [3, 5]))
        #expect(atLeast("tip", [1, 0]), "a version that does not parse is taken to be recent")
    }

    @Test("CSS names on Ghostty, kitty and foot; X11 on xterm; iTerm2's own nineteen on iTerm2")
    func names() {
        #expect(PointerShapeHost.ghostty.name(for: .link) == "pointer")
        #expect(PointerShapeHost.ghostty.name(for: .columnResize) == "ew-resize", "the arrow its macOS app draws")
        #expect(PointerShapeHost.ghostty.name(for: .rowResize) == "ns-resize")
        #expect(PointerShapeHost.ghostty.name(for: .resizeNorthWestSouthEast) == nil, "nothing to draw: its own")
        #expect(PointerShapeHost.ghostty.name(for: .zoomIn) == nil)
        #expect(PointerShapeHost.kitty.name(for: .columnResize) == "col-resize")
        #expect(PointerShapeHost.foot.name(for: .resizeNorthWestSouthEast) == "nwse-resize")
        #expect(PointerShapeHost.xterm.name(for: .link) == "hand2")
        #expect(PointerShapeHost.xterm.name(for: .text) == "xterm")
        #expect(PointerShapeHost.iTerm2.name(for: .arrow) == "arrow")
        #expect(PointerShapeHost.iTerm2.name(for: .rowResizeDown) == "based_arrow_down")
        #expect(PointerShapeHost.iTerm2.name(for: .grab) == nil, "its hand1 is a pointing hand, not an open one")
        #expect(PointerShapeHost.xterm.name(for: .zoomIn) == nil)
    }

    /// The names iTerm2 3.5.0 to 3.6.11 read (`PTYSession.screenSetPointerShape`):
    /// one outside them would be read as a reset.
    @Test("Every name spoken to iTerm2 is one its table has")
    func iTerm2NamesAreItsOwn() {
        let table: Set<String> = [
            "X_cursor", "arrow", "based_arrow_down", "based_arrow_up", "cross", "cross_reverse", "crosshair",
            "hand1", "hand2", "left_ptr", "left_side", "right_side", "sb_h_double_arrow", "sb_left_arrow",
            "sb_right_arrow", "sb_up_arrow", "sb_v_double_arrow", "tcross", "xterm",
        ]
        for shape in PointerShape.allCases {
            if let name = PointerShapeHost.iTerm2.name(for: shape) { #expect(table.contains(name), "\(shape)") }
        }
    }

    /// CSS's `cursor` keywords as Ghostty reads them (its `mouse.zig`), kitty's
    /// thirty a subset of them.
    @Test("Every CSS name is one Ghostty's table has")
    func cssNamesAreGhosttys() {
        let table: Set<String> = [
            "default", "context-menu", "help", "pointer", "progress", "wait", "cell", "crosshair", "text",
            "vertical-text", "alias", "copy", "move", "no-drop", "not-allowed", "grab", "grabbing", "all-scroll",
            "col-resize", "row-resize", "n-resize", "e-resize", "s-resize", "w-resize", "ne-resize", "nw-resize",
            "se-resize", "sw-resize", "ew-resize", "ns-resize", "nesw-resize", "nwse-resize", "zoom-in", "zoom-out",
        ]
        for shape in PointerShape.allCases {
            #expect(PointerShapeHost.cssNames[shape].map(table.contains) == true, "\(shape) has no CSS name")
        }
    }

    /// The keywords Ghostty 1.3.1's macOS app gives a cursor
    /// (`SurfaceView.setCursorShape`): any other it ignores, and the pointer
    /// keeps the shape it had, which the owner saw on the card (2026-10-19).
    @Test("Every name spoken to Ghostty is one its macOS app draws")
    func ghosttyNamesAreDrawn() {
        let drawn: Set<String> = [
            "default", "text", "vertical-text", "grab", "grabbing", "pointer", "w-resize", "e-resize",
            "n-resize", "s-resize", "ns-resize", "ew-resize", "context-menu", "crosshair", "not-allowed",
        ]
        for shape in PointerShape.allCases {
            if let name = PointerShapeHost.ghostty.name(for: shape) { #expect(drawn.contains(name), "\(shape)") }
        }
    }

    @Test("No style mid-run is `default` on Ghostty, which ignores an empty name in older releases, and empty elsewhere")
    func unsetNames() {
        #expect(PointerShapeHost.ghostty.unsetName == "default")
        for host in [PointerShapeHost.kitty, .foot, .iTerm2, .xterm, .unnamed] { #expect(host.unsetName.isEmpty) }
        #expect(PointerShapeHost.reset == "\u{1B}]22;\u{1B}\\")
        #expect(PointerShapeHost.sequence(naming: "pointer") == "\u{1B}]22;pointer\u{1B}\\")
    }

    @Test("The override, then TUIKIT_POINTER_SHAPES, then the table")
    func ladder() {
        let ghostty = ["TERM_PROGRAM": "ghostty"]
        let unnamed = ["TERM": "xterm-256color"]
        #expect(TerminalClient.pointerShapeHost(override: nil, environment: ghostty) == .ghostty)
        #expect(TerminalClient.pointerShapeHost(override: nil, environment: unnamed) == nil)
        #expect(TerminalClient.pointerShapeHost(override: false, environment: ghostty) == nil)
        #expect(TerminalClient.pointerShapeHost(override: true, environment: unnamed) == .unnamed)
        #expect(
            TerminalClient.pointerShapeHost(override: nil, environment: ghostty.merging(["TUIKIT_POINTER_SHAPES": "0"]) { $1 })
                == nil)
        #expect(
            TerminalClient.pointerShapeHost(override: nil, environment: unnamed.merging(["TUIKIT_POINTER_SHAPES": "1"]) { $1 })
                == .unnamed)
        #expect(
            TerminalClient.pointerShapeHost(
                override: false, environment: ghostty.merging(["TUIKIT_POINTER_SHAPES": "all"]) { $1 }) == nil,
            "the app's override beats the environment")
    }

    @Test("TUI's own controls set shapes where a host's reset is measured, iTerm2 so far, or where TUIKIT_POINTER_SHAPES=all asks")
    func builtInShapes() {
        #expect(TerminalClient.builtInPointerShapes(host: .iTerm2, environment: [:]), "its reset read by the owner")
        for host: PointerShapeHost in [.ghostty, .kitty, .foot, .xterm, .unnamed] {
            #expect(!TerminalClient.builtInPointerShapes(host: host, environment: [:]), "\(host): reset unread")
        }
        #expect(TerminalClient.builtInPointerShapes(host: .ghostty, environment: ["TUIKIT_POINTER_SHAPES": "all"]))
        #expect(!TerminalClient.builtInPointerShapes(host: nil, environment: ["TUIKIT_POINTER_SHAPES": "all"]))
    }
}
