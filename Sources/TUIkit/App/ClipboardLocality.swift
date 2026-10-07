//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardLocality.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Whether the person at the keyboard is on the machine this app runs on —
/// the one condition under which this machine's clipboard is theirs.
///
/// A copy written with `pbcopy`, `wl-copy` or `xclip` lands on the clipboard of
/// the machine the app runs on. Over ssh that is the server's, which the user
/// never sees, and a Mac server's pasteboard is someone's: writing it is
/// meddling, not copying. So TUIkit uses this machine's clipboard only on
/// positive evidence that the terminal is here too, and every rung below has
/// to hold:
///
/// 1. None of `SSH_CONNECTION`, `SSH_CLIENT` or `SSH_TTY` is set: OpenSSH sets
///    all three in a session it starts.
/// 2. This process's chain of parents reaches the root without passing a
///    remote-session daemon — `sshd` (and its `sshd-session` halves),
///    `mosh-server`, `dropbear`, `telnetd`, `etserver` and `etterminal`,
///    `ttyd`, `gotty`. mosh sets no variable of its own, so the chain is the
///    only witness to it.
/// 3. Inside tmux, the pane's process is a child of the tmux SERVER, which
///    says nothing about who is watching: every attached client's chain must
///    pass the same test, and there must be at least one client. A session
///    started at the desk and attached from afar is the case this catches —
///    its variables were set when it was started, here. A client is itself
///    named tmux, but a tmux further up its chain is another server: a tmux
///    run inside an outer tmux's pane, whose outer session can be attached
///    from afar as well, so it counts as rung 4's keeper there.
/// 4. None of the session keepers TUIkit knows is in the chain or named by its
///    variable: GNU `screen` (`STY`), `zellij` (`ZELLIJ`,
///    `ZELLIJ_SESSION_NAME`), `abduco` (`ABDUCO_SESSION`), `shpool`
///    (`SHPOOL_SESSION_NAME`), and, by the chain alone, `dtach`, `tmate` and
///    WezTerm's `wezterm-mux-server` (a pane of a mux server attached through
///    an SSH domain sets no variable that differs from a local one). Each
///    runs its sessions under a server detached from the terminal that
///    started it, as tmux does, so the pane's chain ends at that server
///    whoever is attached — and none of them can be asked for its clients the
///    way tmux can. A session inside one is therefore not evidence, and
///    answers "not local" even at the desk. A tmux server in the chain of a
///    process outside a tmux pane (`TMUX` unset) is the same case. A keeper
///    TUIkit does not know of passes as a plain parent: the list is the
///    programs found so far, not every one there is.
///
/// A chain that cannot be read to the root is not evidence, so it answers
/// "not local". A wrong "not local" costs a copy the user can redo with the
/// terminal's own selection; a wrong "local" puts their text on a machine they
/// are not at.
enum ClipboardLocality {

    /// The command names (as ``ProcessAncestry/commandName(of:)`` reads them)
    /// of programs that carry a terminal session in from another machine.
    static func isRemoteSessionDaemon(_ name: String) -> Bool {
        // `sshd`, and OpenSSH 9.8's `sshd-session` and `sshd-auth`.
        if name.hasPrefix("sshd") { return true }
        // Eternal Terminal's daemon, and the per-session half its client
        // starts over ssh, which runs the shell (by its design; unmeasured).
        return [
            "mosh-server", "dropbear", "telnetd", "in.telnetd", "rlogind", "etserver", "etterminal", "ttyd",
            "gotty",
        ]
        .contains(name)
    }

    /// The command names of programs that keep a terminal session for whoever
    /// attaches next: rung 4's session keepers. tmux is one too, but its
    /// clients can be asked for, so it counts here only for a process that is
    /// not in a tmux pane.
    ///
    /// GNU screen's server renames itself `SCREEN` in its arguments while the
    /// kernel keeps `screen`, so both are matched; tmux is matched by
    /// ``isTmux(_:)``. The kernel cuts a name to 16 bytes on Darwin and 15 on
    /// Linux, so `wezterm-mux-server` reads `wezterm-mux-serv` or
    /// `wezterm-mux-ser`: matched by the 15.
    static func isSessionKeeper(_ name: String, inTmux: Bool) -> Bool {
        if !inTmux, isTmux(name) { return true }
        if name.hasPrefix("wezterm-mux-ser") { return true }
        return ["screen", "SCREEN", "zellij", "dtach", "abduco", "shpool", "tmate"].contains(name)
    }

    /// Whether `name` is tmux's own, its server's or a client's: `tmux` as
    /// Darwin keeps it, and `tmux: server` or `tmux: client` on Linux, where
    /// tmux renames itself through `prctl` (tmux's `proc_start`; read from its
    /// source, unmeasured on a host). Not every name starting "tmux": a
    /// wrapper script run by its shebang, `tmux-sessionizer` say, is named
    /// after itself, and above a client it is a plain parent.
    static func isTmux(_ name: String) -> Bool {
        name == "tmux" || name.hasPrefix("tmux: ")
    }

    /// Whether `name` is GNU screen's: `screen` as the kernel keeps it, or
    /// `SCREEN`, which its server renames itself to in its arguments.
    static func isGNUScreen(_ name: String) -> Bool {
        name == "screen" || name == "SCREEN"
    }

    /// The variables rung 4's session keepers set inside a session.
    static let sessionKeeperVariables = [
        "STY", "ZELLIJ", "ZELLIJ_SESSION_NAME", "ABDUCO_SESSION", "SHPOOL_SESSION_NAME",
    ]

    /// The decision, posed on its inputs.
    ///
    /// - Parameters:
    ///   - environment: This process's environment.
    ///   - ownChain: This process's command names up to the root, or `nil`
    ///     when the chain could not be read.
    ///   - tmuxClientChains: Inside tmux, each attached client's chain (an
    ///     element `nil` where one could not be read), or `nil` when tmux
    ///     could not be asked. Ignored outside tmux.
    ///   - inTmux: Whether this process runs in a tmux pane.
    static func isLocal(
        environment: [String: String], ownChain: [String]?, tmuxClientChains: [[String]?]?, inTmux: Bool
    ) -> Bool {
        for variable in ["SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"] + sessionKeeperVariables
        where environment[variable]?.isEmpty == false {
            return false
        }
        guard let ownChain,
            !ownChain.contains(where: { isRemoteSessionDaemon($0) || isSessionKeeper($0, inTmux: inTmux) })
        else { return false }
        guard inTmux else { return true }
        guard let clients = tmuxClientChains, !clients.isEmpty else { return false }
        return clients.allSatisfy { chain in
            guard let chain else { return false }
            // A client is itself named tmux — the chain's first name — so only
            // the keepers above it count against it: a tmux attached from
            // inside a screen session is as far away as that session's own
            // client, and one attached from inside another tmux's pane as far
            // away as that tmux's.
            return !chain.enumerated().contains { index, name in
                isRemoteSessionDaemon(name) || isSessionKeeper(name, inTmux: index == 0)
            }
        }
    }

    /// The decision for this process, now.
    ///
    /// Inside tmux this asks tmux for its clients — a bounded subprocess — so
    /// it is asked when a copy is made, never per frame. Outside tmux it reads
    /// the kernel only.
    static func isLocal() -> Bool {
        #if canImport(WASILibc)
            // A wasm guest has no processes to walk and no helper to run: the
            // machine it runs on is a browser page's sandbox.
            return false
        #else
        let environment = ProcessInfo.processInfo.environment
        let inTmux = TerminalHost.isTmux
        let ownChain = ProcessAncestry.ownCommandNames()
        let clientChains = inTmux && ownChain != nil ? tmuxClients()?.map { $0.chain?.map(\.name) } : nil
        return isLocal(
            environment: environment, ownChain: ownChain, tmuxClientChains: clientChains, inTmux: inTmux)
        #endif
    }

    /// One client attached to this process's tmux server, as a copy reads it.
    struct AttachedClient: Equatable {
        /// The panes of the client's session
        /// (``TerminalHost/TmuxClient/sessionPanes``), or `nil` where tmux did
        /// not list them.
        var sessionPanes: [String]?
        /// The client's processes up to the root, its own first
        /// (``ProcessAncestry/links(from:limit:)``), or `nil` where its chain
        /// could not be read.
        var chain: [ProcessAncestry.Link]?
    }

    /// The clients attached to this process's tmux server, every session's —
    /// or `nil` where tmux could not be asked, or this process is in no tmux
    /// pane.
    ///
    /// Asks tmux for its clients (``TerminalHost/probeTmuxClients()``), a
    /// bounded subprocess, and walks each one's parents: asked when a copy is
    /// made, never per frame.
    static func tmuxClients() -> [AttachedClient]? {
        TerminalHost.probeTmuxClients().map { clients in
            clients.map { client in
                AttachedClient(
                    sessionPanes: client.sessionPanes,
                    chain: client.pid.flatMap { ProcessAncestry.links(from: $0) })
            }
        }
    }
}
