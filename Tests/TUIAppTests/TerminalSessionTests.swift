//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalSessionTests.swift
//
//  Which terminal session a process runs in, from its environment: what
//  `@SceneStorage` keeps its values per.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUITerminalHost

@Suite("TerminalSession")
struct TerminalSessionTests {
    @Test("Each terminal's own variable names its session")
    func eachTerminal() {
        let cases: [([String: String], String)] = [
            (["TERM_PROGRAM": "Apple_Terminal", "TERM_SESSION_ID": "U1"], "apple-terminal:U1"),
            (["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t1p0:U2", "TERM_SESSION_ID": "w0t1p0:U2"], "iterm2:w0t1p0:U2"),
            (["KITTY_WINDOW_ID": "3", "KITTY_PID": "77"], "kitty:77:3"),
            (["TERM_PROGRAM": "WezTerm", "WEZTERM_PANE": "4", "WEZTERM_UNIX_SOCKET": "/s/gui-sock-9"], "wezterm:/s/gui-sock-9:4"),
            (["WT_SESSION": "G"], "windows-terminal:G"),
            (["TERM_PROGRAM": "WarpTerminal", "WARP_TERMINAL_SESSION_UUID": "W"], "warp:W"),
            (["KONSOLE_DBUS_SESSION": "/Sessions/1", "KONSOLE_DBUS_SERVICE": ":1.4"], "konsole::1.4:/Sessions/1"),
            (["GNOME_TERMINAL_SCREEN": "/org/gnome/Terminal/screen/x"], "gnome-terminal:/org/gnome/Terminal/screen/x"),
            (["STY": "123.pts-0.host", "WINDOW": "2"], "screen:123.pts-0.host:2"),
        ]
        for (environment, expected) in cases {
            #expect(TerminalSession.identity(environment: environment) == expected)
        }
    }

    @Test("A tmux pane wins over the outer terminal's variables, which tmux keeps stale")
    func tmuxWins() {
        let environment = [
            "TERM_PROGRAM": "tmux", "TMUX": "/tmp/tmux-501/default,4242,0", "TMUX_PANE": "%3",
            "TERM_SESSION_ID": "stale", "KITTY_WINDOW_ID": "1",
        ]
        #expect(TerminalSession.identity(environment: environment) == "tmux:/tmp/tmux-501/default,4242:%3")
    }

    @Test("A variable whose terminal TERM_PROGRAM does not name was inherited, and does not count")
    func inheritedVariables() {
        // Ghostty started from an Apple Terminal shell: every window would
        // otherwise be one session.
        #expect(TerminalSession.identity(environment: ["TERM_PROGRAM": "ghostty", "TERM_SESSION_ID": "U"]) == nil)
        #expect(TerminalSession.identity(environment: ["TERM_PROGRAM": "ghostty", "ITERM_SESSION_ID": "U"]) == nil)
        #expect(TerminalSession.identity(environment: ["WEZTERM_PANE": "1"]) == nil)
    }

    @Test("A plain ssh session names none")
    func sshNamesNone() {
        let environment = ["SSH_CONNECTION": "10.0.0.1 5 10.0.0.2 22", "TERM": "xterm-256color", "LC_TERMINAL": "iTerm2"]
        #expect(TerminalSession.identity(environment: environment) == nil)
        #expect(TerminalSession.identity(environment: ["TERM_PROGRAM": "Apple_Terminal", "TERM_SESSION_ID": ""]) == nil)
    }
}
