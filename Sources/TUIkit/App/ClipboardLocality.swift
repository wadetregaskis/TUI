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
///    `mosh-server`, `dropbear`, `telnetd`, `etserver`, `ttyd`, `gotty`. mosh
///    sets no variable of its own, so the chain is the only witness to it.
/// 3. Inside tmux, the pane's process is a child of the tmux SERVER, which
///    says nothing about who is watching: every attached client's chain must
///    pass the same test, and there must be at least one client. A session
///    started at the desk and attached from afar is the case this catches —
///    its variables were set when it was started, here.
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
        return ["mosh-server", "dropbear", "telnetd", "in.telnetd", "rlogind", "etserver", "ttyd", "gotty"]
            .contains(name)
    }

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
        for variable in ["SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"]
        where environment[variable]?.isEmpty == false {
            return false
        }
        guard let ownChain, !ownChain.contains(where: isRemoteSessionDaemon) else { return false }
        guard inTmux else { return true }
        guard let clients = tmuxClientChains, !clients.isEmpty else { return false }
        return clients.allSatisfy { chain in
            guard let chain else { return false }
            return !chain.contains(where: isRemoteSessionDaemon)
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
        let ownChain = ProcessAncestry.commandNames(from: getpid())
        var clientChains: [[String]?]?
        if inTmux, ownChain != nil {
            clientChains = TerminalHost.probeTmuxClients().map { clients in
                clients.map { client in client.pid.flatMap { ProcessAncestry.commandNames(from: $0) } }
            }
        }
        return isLocal(
            environment: environment, ownChain: ownChain, tmuxClientChains: clientChains, inTmux: inTmux)
        #endif
    }
}
