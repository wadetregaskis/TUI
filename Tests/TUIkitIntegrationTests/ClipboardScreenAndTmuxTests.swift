//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardScreenAndTmuxTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTerminalHost
@testable import TUIkitTestSupport

/// The clipboard ladder's rows for GNU screen and tmux together, where
/// neither `STY` nor the pane's own process chain can say whether screen
/// stands between tmux and the terminal, and tmux's clients decide.
@Suite("OSC 52 under GNU screen and tmux")
struct ClipboardScreenAndTmuxTests {
    typealias Row = ClipboardTerminalSupportTests.Row

    /// Inside both GNU screen and tmux.
    static let screenAndTmux = ["STY": "4242.pts-0.desk", "TMUX": "/tmp/tmux-501/default,7,0"]

    /// The same, in tmux's pane `%1`.
    static let screenAndTmuxPane = screenAndTmux.merging(["TMUX_PANE": "%1"]) { $1 }

    /// A tmux client whose chain is `chain` — each process's name and
    /// controlling terminal, the client's own first — attached to a session
    /// holding `panes` (`nil`: not listed).
    static func client(_ chain: [(String, Int32?)]?, panes: [String]? = nil) -> SessionLocality.AttachedClient {
        SessionLocality.AttachedClient(
            sessionPanes: panes, chain: chain?.map { ProcessAncestry.Link(name: $0.0, terminal: $0.1) })
    }

    static let rows: [Row] = [
        // A tmux server started inside screen keeps screen's STY in its
        // environment whoever attaches, and its panes' chains end at the
        // daemonized server however it is attached: its clients' chains
        // decide. Attached straight from the terminal, its set-clipboard
        // does (review round 1 of the follow-ups: STY alone said "Not
        // copied")...
        Row(
            name: "tmux started inside screen, attached from the terminal",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [client([("tmux", 5), ("zsh", 5), ("login", 5), ("iTerm2", nil), ("launchd", nil)])]),
        Row(
            name: "tmux started inside screen, attached from the terminal, on Linux",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["bash", "tmux: server", "systemd"],
            tmuxClients: [client([("tmux: client", 5), ("bash", 5), ("ghostty", nil), ("systemd", nil)])]),
        // ...and still attached from inside screen, nothing reaches the
        // terminal: the copy is "Not copied", not "Sent" (review round 2:
        // the pane's chain alone said tmux was the nearer).
        Row(
            name: "tmux started inside screen, attached from inside screen",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unsupported, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [client([("tmux", 5), ("zsh", 5), ("screen", nil), ("launchd", nil)])]),
        Row(
            name: "tmux started inside screen, attached from inside screen, on Linux",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unsupported, ownChain: ["bash", "tmux: server", "systemd"],
            tmuxClients: [client([("tmux: client", 5), ("bash", 5), ("SCREEN", nil), ("systemd", nil)])]),
        // A tmux started outside screen and attached from inside it has
        // no STY to say so.
        Row(
            name: "tmux attached from inside screen, STY not set",
            environment: ["TMUX": "/tmp/tmux-501/default,7,0"], program: .tmux, deviceAttributes: nil,
            tmuxSetClipboard: "on", expected: .unsupported,
            tmuxClients: [client([("tmux", 5), ("zsh", 5), ("screen", nil), ("zsh", 2), ("login", 2), ("Terminal", nil), ("launchd", nil)])]),
        // One client that can take it is enough for tmux to pass it on.
        Row(
            name: "tmux with one client inside screen and one not",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [
                client([("tmux", 5), ("zsh", 5), ("screen", nil), ("launchd", nil)]),
                client([("tmux", 5), ("zsh", 5), ("ghostty", nil), ("launchd", nil)]),
            ]),
        // What counts is what the client draws in: the process holding its
        // terminal. A GUI terminal started from a shell inside screen draws
        // the client itself (review 1 of the follow-ups' fixes: screen
        // anywhere above a client counted, and such a copy was "Not copied").
        Row(
            name: "tmux attached from a terminal started inside screen, on Linux",
            environment: ["TMUX": "/tmp/tmux-1000/default,7,0"], program: .tmux, deviceAttributes: nil,
            tmuxSetClipboard: "on", expected: .unconfirmed,
            tmuxClients: [
                client([
                    ("tmux: client", 7), ("bash", 7), ("xterm", 3), ("bash", 3), ("SCREEN", nil), ("systemd", nil),
                ])
            ]),
        // ...where a screen run in a GUI terminal holds the client's.
        Row(
            name: "tmux attached from inside screen run in a GUI terminal, on Linux",
            environment: ["TMUX": "/tmp/tmux-1000/default,7,0"], program: .tmux, deviceAttributes: nil,
            tmuxSetClipboard: "on", expected: .unsupported,
            tmuxClients: [
                client([
                    ("tmux: client", 3), ("bash", 3), ("SCREEN", nil), ("screen", 9), ("bash", 9), ("xterm", nil),
                    ("systemd", nil),
                ])
            ]),
        // tmux passes a pane's write on only to the clients whose session
        // holds the pane: a client on another session neither receives it
        // nor makes up for one that receives it inside screen (review 1 of
        // the follow-ups' fixes: every client of the server was counted).
        Row(
            name: "the pane's session attached from inside screen, another session from the terminal",
            environment: Self.screenAndTmuxPane, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unsupported, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [
                client([("tmux", 5), ("zsh", 5), ("screen", nil), ("launchd", nil)], panes: ["%0", "%1"]),
                client([("tmux", 5), ("zsh", 5), ("ghostty", nil), ("launchd", nil)], panes: ["%3"]),
            ]),
        Row(
            name: "the pane's session attached from the terminal, another session from inside screen",
            environment: Self.screenAndTmuxPane, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [
                client([("tmux", 5), ("zsh", 5), ("screen", nil), ("launchd", nil)], panes: ["%3"]),
                client([("tmux", 5), ("zsh", 5), ("ghostty", nil), ("launchd", nil)], panes: ["%0", "%1"]),
            ]),
        // A session grouped with the pane's holds its windows, and tmux's
        // list names the pane for its clients as well.
        Row(
            name: "a session grouped with the pane's, attached from the terminal",
            environment: Self.screenAndTmuxPane, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [
                client([("tmux", 5), ("zsh", 5), ("screen", nil), ("launchd", nil)], panes: ["%0", "%1"]),
                client([("tmux", 5), ("zsh", 5), ("ghostty", nil), ("launchd", nil)], panes: ["%0", "%1"]),
            ]),
        // Where it cannot be told, the write goes as a maybe, reported as
        // sent: a client's panes unlisted, no client showing the pane, a
        // client's chain unread, tmux not listing its clients.
        Row(
            name: "the pane's session attached from inside screen, a client's panes unlisted",
            environment: Self.screenAndTmuxPane, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [
                client([("tmux", 5), ("zsh", 5), ("screen", nil), ("launchd", nil)], panes: ["%0", "%1"]),
                client([("tmux", 5), ("zsh", 5), ("ghostty", nil), ("launchd", nil)]),
            ]),
        Row(
            name: "tmux attached from inside screen, the client on no terminal",
            environment: Self.screenAndTmuxPane, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [client([("tmux", nil), ("zsh", nil), ("screen", nil), ("launchd", nil)])]),
        Row(
            name: "no client showing the pane",
            environment: Self.screenAndTmuxPane, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [client([("tmux", 5), ("zsh", 5), ("screen", nil), ("launchd", nil)], panes: ["%3"])]),
        Row(
            name: "tmux started inside screen, a client's chain unread",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [client([("tmux", 5), ("zsh", 5), ("screen", nil), ("launchd", nil)]), client(nil)]),
        Row(
            name: "screen and tmux, no chain readable",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed),
        // A screen run in a tmux pane is what the app draws in.
        Row(
            name: "screen run in a tmux pane",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unsupported, ownChain: ["zsh", "screen", "zsh", "tmux", "launchd"],
            tmuxClients: [client([("tmux", 5), ("zsh", 5), ("login", 5), ("iTerm2", nil), ("launchd", nil)])]),
        Row(
            name: "screen run in a tmux pane, reattached",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unsupported, ownChain: ["zsh", "SCREEN", "launchd"],
            tmuxClients: [client([("tmux", 5), ("zsh", 5), ("login", 5), ("iTerm2", nil), ("launchd", nil)])]),
        // tmux's passthrough reaches the client's terminal as the bare write,
        // which screen drops there just the same: no wrapped write is sent.
        Row(
            name: "tmux passthrough, attached from inside screen",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "external",
            expected: .unsupported, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [client([("tmux", 5), ("zsh", 5), ("screen", nil), ("launchd", nil)])],
            tmuxAllowPassthrough: "on"),
        Row(
            name: "tmux passthrough, attached from the terminal",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "external",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClients: [client([("tmux", 5), ("zsh", 5), ("login", 5), ("iTerm2", nil), ("launchd", nil)])],
            tmuxAllowPassthrough: "on", passthrough: .tmux),
    ]

    @Test("The ladder", arguments: rows)
    func ladder(_ row: Row) {
        #expect(row.answer == row.delivery)
    }
}
