//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalClipboardSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Which terminals put an OSC 52 write on the clipboard

extension TerminalClient {

    /// How far a terminal can be trusted to put an OSC 52 write on the
    /// clipboard of the machine the user is at.
    ///
    /// OSC 52 (`ESC ] 52 ; c ; <base64> ESC \`) is how a program asks the
    /// terminal to set the clipboard. It is the one route to the user's
    /// clipboard that works over ssh, because the terminal acting on it runs
    /// on the user's machine. No terminal acknowledges the write, though, so
    /// whether it happened is known only from what the terminal is documented
    /// or measured to do.
    public enum ClipboardWriteSupport: Sendable, Equatable {
        /// The terminal writes it by default: documented, or measured with
        /// `Tools/TerminalProbes/clipboard_probe.py`.
        case honoured

        /// The terminal may write it: a setting decides, as iTerm2's
        /// "Applications in terminal may access clipboard" does; or the
        /// terminal says it can in its Device Attributes; or tmux, told to
        /// with `set-clipboard on`, passes it on to whatever terminal it is
        /// drawn in.
        case unconfirmed

        /// The terminal is not known to write it.
        case unsupported
    }

    /// Whether `program` is known to put an OSC 52 write on the clipboard by
    /// default.
    ///
    /// ## A capability, so the default is "no"
    ///
    /// The same reasoning as ``honoursHyperlinks(_:)``: an unmeasured terminal
    /// gets the answer that cannot hurt. For a copy that answer matters more
    /// than for a link, because a copy sent where it is dropped is a copy the
    /// user believes they made. TUIkit therefore sends OSC 52 on this table's
    /// word, says "Sent to the terminal's clipboard" rather than "Copied"
    /// where the word is only a maybe, and copies nothing — and says so —
    /// where neither this table nor the local clipboard reaches the user.
    ///
    /// ## The table
    ///
    /// | Host | Writes | Evidence |
    /// |---|---|---|
    /// | Ghostty | yes | `clipboard-write = allow` is its default (its OSC 52 page and config reference) |
    /// | iTerm2 | only with a setting | "Applications in terminal may access clipboard", off by default |
    /// | tmux | only with `set-clipboard on` | `external`, the default, ignores an application's write; `on` keeps it as a buffer and passes it on (measured, 3.7c) |
    /// | GNU screen | no | it passes an application's OSC 52 on only inside its own DCS passthrough, which TUIkit does not send; recognised by `STY`, whatever terminal is named (unmeasured) |
    /// | Apple Terminal | no | no OSC 52 anywhere in the app |
    /// | Warp | not known | unmeasured |
    /// | unidentified | no | unless its Device Attributes list `52` (see ``clipboardWrites``) |
    ///
    /// Three terminals TUIkit has no ``Program`` for are recognised by their
    /// own variables instead, and all three write by default: kitty
    /// (`TERM=xterm-kitty`, `KITTY_WINDOW_ID`), WezTerm (`TERM_PROGRAM=WezTerm`,
    /// `TERM=wezterm`) and foot (`TERM=foot`, `foot-extra`).
    ///
    /// None of the rows above is measured yet on the hosts themselves except
    /// tmux's: `clipboard_probe.py` is how they will be, and
    /// `Documentation/Terminals/Terminal compatibility survey.md`, "OSC 52 clipboard writes",
    /// keeps the record.
    public static func honoursClipboardWrites(_ program: Program) -> Bool {
        support(of: program) == .honoured
    }

    /// The table behind ``honoursClipboardWrites(_:)``, with its middle rung.
    static func support(of program: Program) -> ClipboardWriteSupport {
        switch program {
        case .ghostty: .honoured
        // Whether tmux passes the write on is its `set-clipboard` option, which
        // the ladder asks tmux for; this is the answer for "on".
        case .iTerm2, .tmux: .unconfirmed
        case .appleTerminal, .warp, .unidentified: .unsupported
        }
    }

    /// Force the answer for the terminal in front of you, whatever was
    /// detected: `true` sends every copy by OSC 52 as one the terminal
    /// honours, `false` never sends OSC 52.
    ///
    /// `nil` (the default) means "use the measured table", unless
    /// `TUIKIT_OSC52` is set in the environment — `1` for on, `0` for off —
    /// which is how a user turns copying on for a terminal TUIkit does not
    /// know, without the application knowing anything about it.
    @MainActor public static var clipboardWriteSupport: Bool?

    /// How far the terminal painting this app's output can be trusted with an
    /// OSC 52 write.
    ///
    /// In order: ``clipboardWriteSupport``; then `TUIKIT_OSC52`; then, in a
    /// tmux pane, tmux's `set-clipboard` (`on` is
    /// ``ClipboardWriteSupport/unconfirmed``, anything else unsupported),
    /// and unsupported where GNU screen is known to stand between tmux and
    /// the terminal; then, inside GNU screen (`STY`), unsupported, as screen
    /// drops an application's OSC 52; then the table at
    /// ``honoursClipboardWrites(_:)``, with kitty, WezTerm and foot recognised
    /// by their variables. Last, a terminal the environment did not name is
    /// asked its Device Attributes at startup, and a reply listing `52` raises
    /// an unsupported answer to unconfirmed — it never lowers one, because a
    /// terminal that writes by default need not say so.
    ///
    /// Asks tmux for its `set-clipboard` option when running in a tmux pane,
    /// and where it is `on`, for its clients, then walks their parents (and
    /// this process's, where screen is named too): bounded subprocesses and
    /// kernel reads, made when a copy is made, not per frame.
    ///
    /// Reads the DETECTED program, never ``simulated``, unlike
    /// ``hyperlinksSupported``. Simulating a terminal changes how the app is
    /// drawn, which is the diagnostic's point; a copy is the user's text, and
    /// it has to go where the terminal actually in front of them takes it.
    /// Read through the simulation, rendering as Ghostty inside Apple Terminal
    /// sent every copy by OSC 52 to a terminal that drops it, and called it
    /// copied.
    @MainActor public static var clipboardWrites: ClipboardWriteSupport {
        let environment = ProcessInfo.processInfo.environment
        if let override = clipboardWriteSupport { return override ? .honoured : .unsupported }
        let program = current.program
        let setClipboard = program == .tmux ? TerminalHost.tmuxOption("set-clipboard") : nil
        // Whom tmux would pass a write on to matters only where it would.
        let passesOn = setClipboard == "on"
        let screenNamed = environment["STY"]?.isEmpty == false
        return clipboardWrites(
            environment: environment, program: program,
            primaryDeviceAttributes: TerminalHost.startupIdentity?.primaryAttributes,
            tmuxSetClipboard: setClipboard,
            ownChain: passesOn && screenNamed ? ProcessAncestry.ownCommandNames() : nil,
            tmuxClients: passesOn ? SessionLocality.tmuxClients() : nil)
    }

    /// The ladder behind ``clipboardWrites``, posed on its inputs so it can be
    /// asked without a terminal.
    ///
    /// 1. `TUIKIT_OSC52`: `1` honoured, `0` unsupported.
    /// 2. tmux: `set-clipboard on` is ``ClipboardWriteSupport/unconfirmed`` —
    ///    tmux keeps the write as a buffer and passes it on only to a client
    ///    that can take it — and anything else, the default `external`
    ///    included, is unsupported, because tmux then ignores an application's
    ///    write. Under `on`, unsupported where GNU screen is known to stand
    ///    between tmux and the terminal
    ///    (``screenStandsBeforeTheTerminal(environment:ownChain:tmuxClients:)``):
    ///    a screen run in this tmux pane, or a tmux every one of whose clients
    ///    showing this pane runs in a screen window. Where that cannot be told — a
    ///    chain unread, tmux not answering — the answer stays unconfirmed,
    ///    which the status bar reports as sent, not as copied. tmux's own variables are checked
    ///    before the ones below, which inside a pane may be stale leftovers of
    ///    whichever terminal, or screen, started the server.
    /// 3. GNU screen (`STY` set, the session is somewhere inside one):
    ///    unsupported. screen does not pass an application's OSC 52 on unless
    ///    it is wrapped in screen's own DCS passthrough, which TUIkit does not
    ///    send, so the terminal's name — inherited from wherever screen was
    ///    started, and stale once it is attached from elsewhere — says
    ///    nothing. Under screen a copy is "Not copied" (at the desk too: a
    ///    keeper is never local, ``SessionLocality``), where the terminal's
    ///    rung said "Sent" (iTerm2) or "Copied" (Ghostty) of a write screen
    ///    dropped. (screen 4's sequence handling, as review 2 of the D4X lane
    ///    read it; unmeasured on a host, and screen 5 unmeasured.)
    /// 4. The table, and the three terminals recognised by their variables.
    /// 5. A Primary Device Attributes reply carrying `52` raises an
    ///    unsupported answer to unconfirmed. It can only ADD a terminal: a
    ///    terminal that writes by default need not say so (Ghostty's
    ///    `ESC[?62;22c` does not), so the table, not DA1, is the main rung.
    ///    Asked only where the environment named no terminal, so it is the
    ///    rung that reaches an unknown terminal over ssh.
    static func clipboardWrites(
        environment: [String: String], program: Program, primaryDeviceAttributes: String?,
        tmuxSetClipboard: String?, ownChain: [String]? = nil, tmuxClients: [SessionLocality.AttachedClient]? = nil
    ) -> ClipboardWriteSupport {
        switch environment["TUIKIT_OSC52"] {
        case "1": return .honoured
        case "0": return .unsupported
        default: break
        }
        if program == .tmux {
            guard tmuxSetClipboard == "on" else { return .unsupported }
            let screenStands = screenStandsBeforeTheTerminal(
                environment: environment, ownChain: ownChain, tmuxClients: tmuxClients)
            return screenStands ? .unsupported : .unconfirmed
        }
        if environment["STY"]?.isEmpty == false { return .unsupported }
        var support = support(of: program)
        if program == .unidentified, namesClipboardWritingTerminal(environment) {
            support = .honoured
        }
        if support == .unsupported, let reply = primaryDeviceAttributes,
            deviceAttributesAdvertiseClipboard(reply)
        {
            support = .unconfirmed
        }
        return support
    }

    /// Whether GNU screen is known to stand between this tmux pane and the
    /// terminal, so that an OSC 52 write tmux passes on reaches no terminal.
    ///
    /// - A screen run in this pane: `STY` is set, and screen is nearer than
    ///   tmux in `ownChain`, this process's command names from itself up.
    /// - A tmux attached from inside screen: every client in `tmuxClients`
    ///   that the write goes to (``writeRecipients(of:pane:)``) runs in a
    ///   screen window — screen holds its terminal
    ///   (``ProcessAncestry/terminalHolder(of:)``), not merely stands
    ///   somewhere above it: a GUI terminal started from a shell inside
    ///   screen draws the clients run in it itself. The pane's own chain
    ///   cannot say so — tmux's server daemonizes and is reparented to
    ///   launchd or init, so a pane's chain is the same however its session
    ///   is attached — and `STY` cannot either: a server started inside
    ///   screen keeps screen's `STY` whoever attaches, and one attached from
    ///   inside screen later has none. Such a client's terminal type is
    ///   screen's, which tmux's default `terminal-features` give no
    ///   clipboard, and screen drops a bare OSC 52 anyway (as tmux's and
    ///   screen's sources read; unmeasured on a host).
    ///
    /// `false` where it cannot be told: no client showing the pane, a
    /// client's chain or this process's unread, a client attached to no
    /// terminal, tmux not answering. The write is then sent as the maybe it
    /// is.
    static func screenStandsBeforeTheTerminal(
        environment: [String: String], ownChain: [String]?, tmuxClients: [SessionLocality.AttachedClient]?
    ) -> Bool {
        if environment["STY"]?.isEmpty == false, let ownChain,
            let screen = ownChain.firstIndex(where: SessionLocality.isGNUScreen),
            ownChain.firstIndex(where: SessionLocality.isTmux).map({ screen < $0 }) ?? true
        {
            return true
        }
        guard let clients = tmuxClients else { return false }
        let recipients = writeRecipients(of: clients, pane: environment["TMUX_PANE"])
        guard !recipients.isEmpty else { return false }
        // What holds the client's terminal is what it draws in.
        return recipients.allSatisfy { client in
            guard let holder = client.chain.flatMap(ProcessAncestry.terminalHolder(of:)) else { return false }
            return SessionLocality.isGNUScreen(holder.name)
        }
    }

    /// The clients tmux passes an OSC 52 write from `pane` (`TMUX_PANE`, as
    /// `%3`) on to: those whose session holds the pane's window (tmux's
    /// `session_has`), which are those whose session's panes include it. A
    /// client attached to another session does not see the write, so it
    /// cannot make up for one that sees it from inside screen.
    ///
    /// A client whose panes tmux did not list, or every client where the
    /// pane is unknown, may be one, and is kept.
    static func writeRecipients(
        of clients: [SessionLocality.AttachedClient], pane: String?
    ) -> [SessionLocality.AttachedClient] {
        guard let pane, !pane.isEmpty else { return clients }
        return clients.filter { client in client.sessionPanes?.contains(pane) ?? true }
    }

    /// Whether the environment names kitty, WezTerm or foot — terminals that
    /// write OSC 52 by default and that TUIkit otherwise leaves unidentified.
    ///
    /// `TERM` is the variable that crosses ssh (it travels in the pty request),
    /// which is where OSC 52 matters most; kitty and foot set one that names
    /// them. The others are set only on the machine the terminal runs on.
    static func namesClipboardWritingTerminal(_ environment: [String: String]) -> Bool {
        let term = environment["TERM"] ?? ""
        if term == "xterm-kitty" || term == "wezterm" || term == "foot" || term.hasPrefix("foot-") {
            return true
        }
        if environment["KITTY_WINDOW_ID"]?.isEmpty == false { return true }
        return environment["TERM_PROGRAM"] == "WezTerm"
    }

    /// Whether a Primary Device Attributes reply (`ESC[?…c`) lists `52`, the
    /// extension a number of terminals use to say they take OSC 52 writes.
    static func deviceAttributesAdvertiseClipboard(_ reply: String) -> Bool {
        guard reply.hasPrefix("\u{1B}[?"), reply.hasSuffix("c") else { return false }
        let parameters = reply.dropFirst(3).dropLast()
        return parameters.split(separator: ";").contains("52")
    }
}
