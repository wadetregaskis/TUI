//  🖥️ TUI — A Terminal UI framework for Swift
//  TUIEnvironmentVariables+Developer.swift
//
//  The variables for someone building an app, and those that nobody needs to set
//  because a terminal, a multiplexer or ssh does. The developers' may be technical.
//  The detected ones are written for the person running an app, whose man page
//  lists them last, so they say what each means for that person.
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
            values: "Any value, even `0` or an empty one, or a path with a `/` in it to log to",
            effect: "Renders again every picture the render cache serves, draws the fresh one, and reports any that differ. For finding a view that doesn't update.",
            code: .overrides("Assign `RenderCache.verifiesRenderMemo`.")),
        TUIEnvironmentVariable(
            "TUI_VERIFY_MEASURE_MEMO", .developer, .diagnostics,
            values: "Any value, even `0` or an empty one, or a path with a `/` in it to log to",
            effect: "Measures again every size the render cache serves, uses the fresh one, and reports any that differ.",
            code: .overrides("Assign `RenderCache.verifiesMeasureMemo`.")),
        TUIEnvironmentVariable(
            "TUI_DEBUG_RENDER", .developer, .diagnostics,
            values: "`1`",
            effect: "Writes the render cache's statistics to stderr each frame. Redirect stderr, or it lands on the screen."),
        TUIEnvironmentVariable(
            "TUI_FRAME_TRACE", .developer, .diagnostics,
            values: "A file",
            effect: "Writes one tab-separated line per frame to that file: its number, when it began and how long it took in milliseconds, the bytes it sent, its render cache hits and misses, and what caused it."),
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
        terminalSets("TERM_PROGRAM", .identity, "Your terminal's name, which many terminals set. ssh doesn't pass it on. `TUI_TERM_PROGRAM` wins over it."),
        terminalSets("TERM_PROGRAM_VERSION", .identity, "Your terminal's version, which says whether it can change the mouse pointer's shape."),
        terminalSets("LC_TERMINAL", .identity, "Your terminal's name, as iTerm2 sets it. ssh does pass this one on, since its name looks like a language setting's."),
        terminalSets("LC_TERMINAL_VERSION", .identity, "The version that goes with `LC_TERMINAL`."),
        terminalSets("GNOME_TERMINAL_SCREEN", .identity, "This is GNOME Terminal, and which tab, so the program can remember its state for each tab."),
        terminalSets("GNOME_TERMINAL_SERVICE", .identity, "This is GNOME Terminal."),
        terminalSets("VTE_VERSION", .identity, "This terminal is built on VTE, as GNOME Terminal is."),
        terminalSets("WT_SESSION", .identity, "This is Windows Terminal, which draws Sixel pictures on a cell of 10 by 20 pixels, and which tab, so the program can remember its state for each tab."),
        terminalSets("KITTY_WINDOW_ID", .identity, "This is kitty, which accepts clipboard writes and pointer shapes, and which window, so the program can remember its state for each window."),
        terminalSets("KITTY_PID", .identity, "Which kitty this is, since each one numbers its windows from 1 again."),
        terminalSets("TERM_SESSION_ID", .identity, "Which Terminal window or iTerm2 session this is, where `TERM_PROGRAM` names one of them, so the program can remember its state for each."),
        terminalSets("ITERM_SESSION_ID", .identity, "Which iTerm2 session this is, where `TERM_PROGRAM` names iTerm2, so the program can remember its state for each."),
        terminalSets("WEZTERM_PANE", .identity, "Which WezTerm pane this is, where `TERM_PROGRAM` names WezTerm, so the program can remember its state for each."),
        terminalSets("WEZTERM_UNIX_SOCKET", .identity, "Which WezTerm this is, which goes with `WEZTERM_PANE`."),
        terminalSets("WARP_TERMINAL_SESSION_UUID", .identity, "Which Warp session this is, where `TERM_PROGRAM` names Warp, so the program can remember its state for each."),
        terminalSets("KONSOLE_DBUS_SESSION", .identity, "Which Konsole session this is, so the program can remember its state for each."),
        terminalSets("KONSOLE_DBUS_SERVICE", .identity, "Which Konsole this is, which goes with `KONSOLE_DBUS_SESSION`."),
        terminalSets("ALACRITTY_WINDOW_ID", .identity, "Which Alacritty window this is, so the program can remember its state for each."),
        terminalSets("ALACRITTY_SOCKET", .identity, "Which Alacritty this is, which goes with `ALACRITTY_WINDOW_ID`."),
        terminalSets("XTERM_VERSION", .identity, "This is xterm, and its version, which says whether it can change the pointer's shape."),
        terminalSets("COLORFGBG", .identity, "The terminal's text and background colours, which say whether it's dark, when the terminal doesn't answer the program's question and there's no tmux or GNU screen in between."),
        terminalSets("TMUX", .identity, "The program is running inside tmux, which changes what it asks of the terminal."),
        terminalSets("TMUX_PANE", .identity, "Which tmux pane, so the program can ask tmux about it and remember its state for each pane."),
        terminalSets("STY", .identity, "The program is running inside GNU screen, so it can't be sure you're at this computer."),
        terminalSets("WINDOW", .identity, "Which GNU screen window, where `STY` is set, so the program can remember its state for each."),
        terminalSets("ZELLIJ", .identity, "The program is running inside zellij, so it can't be sure you're at this computer."),
        terminalSets("ZELLIJ_SESSION_NAME", .identity, "The program is running inside zellij, so it can't be sure you're at this computer."),
        terminalSets("ABDUCO_SESSION", .identity, "The program is running inside abduco, so it can't be sure you're at this computer."),
        terminalSets("SHPOOL_SESSION_NAME", .identity, "The program is running inside shpool, so it can't be sure you're at this computer."),
        terminalSets("SSH_CONNECTION", .session, "The program is running over ssh, so you aren't at this computer: it doesn't follow this computer's own settings, such as Reduce Motion, and doesn't copy or post notifications through it."),
        terminalSets("SSH_CLIENT", .session, "The program is running over ssh, as `SSH_CONNECTION` says."),
        terminalSets("SSH_TTY", .session, "The program is running over ssh, as `SSH_CONNECTION` says."),
        terminalSets("DISPLAY", .session, "On Linux, there's an X11 desktop, so the program can copy with `xclip` or `xsel`, and post a notification the terminal can't show with `notify-send`."),
        terminalSets("WAYLAND_DISPLAY", .session, "On Linux, there's a Wayland desktop, so the program can copy with `wl-copy`, and post a notification the terminal can't show with `notify-send`."),
        terminalSets("DBUS_SESSION_BUS_ADDRESS", .session, "On Linux, there's a desktop session for `notify-send` to post notifications to."),
        terminalSets("XDG_RUNTIME_DIR", .session, "On Linux, where to look for that desktop session, when `DBUS_SESSION_BUS_ADDRESS` doesn't say."),
        terminalSets("PATH", .session, "Where to look for `notify-send`."),
    ]

    private static func terminalSets(
        _ name: String, _ topic: TUIEnvironmentVariable.Topic, _ effect: String
    ) -> TUIEnvironmentVariable {
        TUIEnvironmentVariable(name, .detected, topic, values: "Whatever sets it says", effect: effect, reading: .eachUse)
    }
}

// swiftlint:enable line_length
