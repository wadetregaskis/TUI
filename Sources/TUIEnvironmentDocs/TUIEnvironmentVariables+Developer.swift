//  🖥️ TUI — A Terminal UI framework for Swift
//  TUIEnvironmentVariables+Developer.swift
//
//  The variables for someone building an app, and those that nobody needs to set
//  because a terminal, a multiplexer or ssh does.
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftlint:disable line_length

extension TUIEnvironmentVariables {
    /// What someone building an app can set while they test and debug it.
    static let developer: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_RECORD_SNAPSHOTS", .developer, .testing,
            values: "`1`",
            effect: "`compareToSnapshot(_:filePath:)` writes each snapshot rather than comparing with it. Run this way when a change to the screen is what you meant.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_VERIFY_RENDER_MEMO", .developer, .diagnostics,
            values: "Any value, even `0`, or a path with a `/` in it to log to",
            effect: "Renders again every picture the render cache serves, draws the fresh one, and reports any that differ. For finding a view that doesn't update.",
            code: .overrides("Assign `RenderCache.verifiesRenderMemo`.")),
        TUIEnvironmentVariable(
            "TUI_VERIFY_MEASURE_MEMO", .developer, .diagnostics,
            values: "Any value, even `0`, or a path with a `/` in it to log to",
            effect: "Measures again every size the render cache serves, uses the fresh one, and reports any that differ.",
            code: .overrides("Assign `RenderCache.verifiesMeasureMemo`.")),
        TUIEnvironmentVariable(
            "TUI_DEBUG_RENDER", .developer, .diagnostics,
            values: "`1`",
            effect: "Writes the render cache's statistics to stderr each frame. Redirect stderr, or it lands on the screen."),
        TUIEnvironmentVariable(
            "TUI_DIAGNOSE_BODY_MUTATION", .developer, .diagnostics,
            values: "`1`",
            effect: "Reports a view whose `body` changes state as it draws, naming where it is in the tree."),
        TUIEnvironmentVariable(
            "TUI_DIAGNOSTICS_FILE", .developer, .diagnostics,
            values: "A file",
            effect: "Appends TUI's diagnostics to this file, rather than writing them to stderr, where they'd land on the screen."),
        TUIEnvironmentVariable(
            "TUI_DEBUG_FRAME_DUMP", .developer, .diagnostics,
            values: "`1`",
            effect: "Arms the backtick key, which writes the raw bytes of the last frame to a file in the working directory."),
        TUIEnvironmentVariable(
            "TUI_MAX_ALIGNMENT_PUSH", .developer, .limits,
            values: "A whole number of cells above 0, held to 1073741824",
            effect: "How far one alignment guide may push a view: 1048576 cells by default. A guide past that is taken for a mistake. Raise it for a canvas that really is larger."),
    ]

    /// What a terminal, a multiplexer or ssh sets, and TUI reads to work out where
    /// it's running.
    static let detected: [TUIEnvironmentVariable] = [
        terminalSets("TERM_PROGRAM", .identity, "The terminal's name, set by many terminals. ssh doesn't pass it on. `TUI_TERM_PROGRAM` beats it."),
        terminalSets("TERM_PROGRAM_VERSION", .identity, "The terminal's version, which says whether it can set the pointer's shape."),
        terminalSets("LC_TERMINAL", .identity, "The terminal's name, as iTerm2 sets it. It's what ssh does pass on, by default, being named like a locale variable."),
        terminalSets("LC_TERMINAL_VERSION", .identity, "The version that goes with `LC_TERMINAL`."),
        terminalSets("GNOME_TERMINAL_SCREEN", .identity, "This is GNOME Terminal."),
        terminalSets("GNOME_TERMINAL_SERVICE", .identity, "This is GNOME Terminal."),
        terminalSets("VTE_VERSION", .identity, "This terminal is built on VTE, as GNOME Terminal is."),
        terminalSets("KITTY_WINDOW_ID", .identity, "This is kitty, which takes clipboard writes and pointer shapes."),
        terminalSets("XTERM_VERSION", .identity, "This is xterm, and which version, which says whether it can set the pointer's shape."),
        terminalSets("COLORFGBG", .identity, "The terminal's foreground and background, which say whether it's dark, when the terminal doesn't answer and there's no multiplexer."),
        terminalSets("TMUX", .identity, "The program is in a tmux pane."),
        terminalSets("TMUX_PANE", .identity, "Which tmux pane, to ask tmux about it."),
        terminalSets("STY", .identity, "The program is in a GNU screen session."),
        terminalSets("ZELLIJ", .identity, "The program is in a zellij session."),
        terminalSets("ZELLIJ_SESSION_NAME", .identity, "The program is in a zellij session."),
        terminalSets("ABDUCO_SESSION", .identity, "The program is in an abduco session."),
        terminalSets("SHPOOL_SESSION_NAME", .identity, "The program is in a shpool session."),
        terminalSets("SSH_CONNECTION", .session, "The program is running over ssh, so the person isn't at this machine."),
        terminalSets("SSH_CLIENT", .session, "The program is running over ssh, so the person isn't at this machine."),
        terminalSets("SSH_TTY", .session, "The program is running over ssh, so the person isn't at this machine."),
        terminalSets("DISPLAY", .session, "On Linux, an X11 clipboard helper may be usable."),
        terminalSets("WAYLAND_DISPLAY", .session, "On Linux, a Wayland clipboard helper may be usable."),
    ]

    private static func terminalSets(
        _ name: String, _ topic: TUIEnvironmentVariable.Topic, _ effect: String
    ) -> TUIEnvironmentVariable {
        TUIEnvironmentVariable(name, .detected, topic, values: "Whatever sets it says", effect: effect, reading: .eachUse)
    }
}

// swiftlint:enable line_length
