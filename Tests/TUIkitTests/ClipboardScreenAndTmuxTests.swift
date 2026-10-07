//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardScreenAndTmuxTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The clipboard ladder's rows for GNU screen and tmux together, where
/// neither `STY` nor the pane's own process chain can say whether screen
/// stands between tmux and the terminal, and tmux's clients decide.
@Suite("OSC 52 under GNU screen and tmux")
struct ClipboardScreenAndTmuxTests {
    typealias Row = ClipboardTerminalSupportTests.Row

    /// Inside both GNU screen and tmux.
    static let screenAndTmux = ["STY": "4242.pts-0.desk", "TMUX": "/tmp/tmux-501/default,7,0"]

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
            tmuxClientChains: [["tmux", "zsh", "login", "iTerm2", "launchd"]]),
        Row(
            name: "tmux started inside screen, attached from the terminal, on Linux",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["bash", "tmux: server", "systemd"],
            tmuxClientChains: [["tmux: client", "bash", "ghostty", "systemd"]]),
        // ...and still attached from inside screen, nothing reaches the
        // terminal: the copy is "Not copied", not "Sent" (review round 2:
        // the pane's chain alone said tmux was the nearer).
        Row(
            name: "tmux started inside screen, attached from inside screen",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unsupported, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClientChains: [["tmux", "zsh", "screen", "launchd"]]),
        Row(
            name: "tmux started inside screen, attached from inside screen, on Linux",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unsupported, ownChain: ["bash", "tmux: server", "systemd"],
            tmuxClientChains: [["tmux: client", "bash", "SCREEN", "systemd"]]),
        // A tmux started outside screen and attached from inside it has
        // no STY to say so.
        Row(
            name: "tmux attached from inside screen, STY not set",
            environment: ["TMUX": "/tmp/tmux-501/default,7,0"], program: .tmux, deviceAttributes: nil,
            tmuxSetClipboard: "on", expected: .unsupported,
            tmuxClientChains: [["tmux", "zsh", "screen", "zsh", "login", "Terminal", "launchd"]]),
        // One client that can take it is enough for tmux to pass it on.
        Row(
            name: "tmux with one client inside screen and one not",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClientChains: [["tmux", "zsh", "screen", "launchd"], ["tmux", "zsh", "ghostty", "launchd"]]),
        // Where it cannot be told, the write goes as a maybe, reported as
        // sent: a client's chain unread, tmux not listing its clients.
        Row(
            name: "tmux started inside screen, a client's chain unread",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed, ownChain: ["zsh", "tmux", "launchd"],
            tmuxClientChains: [["tmux", "zsh", "screen", "launchd"], nil]),
        Row(
            name: "screen and tmux, no chain readable",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unconfirmed),
        // A screen run in a tmux pane is what the app draws in.
        Row(
            name: "screen run in a tmux pane",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unsupported, ownChain: ["zsh", "screen", "zsh", "tmux", "launchd"],
            tmuxClientChains: [["tmux", "zsh", "login", "iTerm2", "launchd"]]),
        Row(
            name: "screen run in a tmux pane, reattached",
            environment: Self.screenAndTmux, program: .tmux, deviceAttributes: nil, tmuxSetClipboard: "on",
            expected: .unsupported, ownChain: ["zsh", "SCREEN", "launchd"],
            tmuxClientChains: [["tmux", "zsh", "login", "iTerm2", "launchd"]]),
    ]

    @Test("The ladder", arguments: rows)
    func ladder(_ row: Row) {
        #expect(
            TerminalClient.clipboardWrites(
                environment: row.environment, program: row.program,
                primaryDeviceAttributes: row.deviceAttributes, tmuxSetClipboard: row.tmuxSetClipboard,
                ownChain: row.ownChain, tmuxClientChains: row.tmuxClientChains)
                == row.expected)
    }
}
