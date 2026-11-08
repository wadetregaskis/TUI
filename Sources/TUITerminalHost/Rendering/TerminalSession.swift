//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalSession.swift
//
//  Which terminal window, tab or pane this process runs in, from what the
//  terminal put in its environment: what `@SceneStorage` keeps its values per.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The Session

/// The terminal session this process runs in: a window, a tab or a pane, as
/// the terminal names it in the environment it starts the shell with.
///
/// `@SceneStorage` keeps its values per session, so that running an app
/// again in the same window puts back where it was there, while a new window
/// starts from whatever was saved last. See
/// `Documentation/Historical/State and dynamic properties/Scene storage per terminal session.md`.
package enum TerminalSession {
    /// The session `environment` names, or `nil` where it names none, as over
    /// a plain ssh connection, which forwards none of these.
    ///
    /// The most specific answer wins, so a multiplexer comes first: a tmux
    /// pane or a screen window is where the app runs, and the outer terminal's
    /// variables inside one are those of whichever client started the server,
    /// stale for every client since (`Terminal compatibility survey.md`,
    /// "Environment leakage does NOT work"). Then the terminals whose variable
    /// names one window or pane and nothing else of theirs, then Apple
    /// Terminal's and iTerm2's.
    ///
    /// A terminal started from another's shell inherits the other's
    /// variables. For a terminal that names itself in `TERM_PROGRAM` (Apple
    /// Terminal, iTerm2, WezTerm, Warp) that is caught: its variable counts
    /// only where `TERM_PROGRAM` names it. kitty, Windows Terminal, Konsole,
    /// GNOME Terminal and Alacritty name themselves no such way, so their
    /// variables count wherever they are set; they are checked before Apple
    /// Terminal's and iTerm2's, the likeliest to have been inherited. A
    /// variable inherited by a terminal that sets none of its own (Ghostty
    /// sets none per window) makes every window of it one session, which is
    /// what every window was before sessions.
    ///
    /// Each answer starts with its source, so two terminals' numbers never
    /// meet, and carries the instance where the number restarts with one
    /// (kitty's window ids, tmux's pane ids).
    package static func identity(environment: [String: String]) -> String? {
        func value(_ name: String) -> String? {
            guard let value = environment[name], !value.isEmpty else { return nil }
            return value
        }
        let program = value("TERM_PROGRAM")

        // tmux: `TMUX` is the server's socket, its pid and the session's
        // index; the pane's id is unique within one server, so the socket and
        // the pid scope it. Not the session's index, which a pane keeps when
        // it moves between sessions.
        if let tmux = value("TMUX"), let pane = value("TMUX_PANE") {
            let server = tmux.split(separator: ",", omittingEmptySubsequences: false).prefix(2).joined(separator: ",")
            return "tmux:\(server):\(pane)"
        }
        // screen: the session's name (its pid first) and the window's number.
        if let session = value("STY"), let window = value("WINDOW") {
            return "screen:\(session):\(window)"
        }
        if let window = value("KITTY_WINDOW_ID") {
            return "kitty:\(value("KITTY_PID") ?? ""):\(window)"
        }
        if let session = value("WT_SESSION") {
            return "windows-terminal:\(session)"
        }
        if let session = value("KONSOLE_DBUS_SESSION") {
            return "konsole:\(value("KONSOLE_DBUS_SERVICE") ?? ""):\(session)"
        }
        if let screen = value("GNOME_TERMINAL_SCREEN") {
            return "gnome-terminal:\(screen)"
        }
        if let window = value("ALACRITTY_WINDOW_ID") {
            return "alacritty:\(value("ALACRITTY_SOCKET") ?? ""):\(window)"
        }
        if program == "WezTerm", let pane = value("WEZTERM_PANE") {
            return "wezterm:\(value("WEZTERM_UNIX_SOCKET") ?? ""):\(pane)"
        }
        if program == "WarpTerminal", let session = value("WARP_TERMINAL_SESSION_UUID") {
            return "warp:\(session)"
        }
        // iTerm2 sets both to the same `w0t0p0:UUID`; Apple Terminal sets
        // only `TERM_SESSION_ID`, a UUID per window, which it restores with
        // the window when it relaunches.
        if program == "iTerm.app", let session = value("ITERM_SESSION_ID") ?? value("TERM_SESSION_ID") {
            return "iterm2:\(session)"
        }
        if program == "Apple_Terminal", let session = value("TERM_SESSION_ID") {
            return "apple-terminal:\(session)"
        }
        return nil
    }
}
