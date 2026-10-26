//  🖥️ TUI — A Terminal UI framework for Swift
//  SessionLocality+Remote.swift
//
//  The other side of SessionLocality: not only whether the user is at this
//  machine, but whether there is evidence that they are at another — what a
//  file panel's "you are browsing <host>" notice is shown on.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension SessionLocality {
    /// Where the person at the keyboard is, as far as this process can tell.
    package enum Judgement: Equatable, Sendable {
        /// At this machine: ``SessionLocality/isLocal()``'s positive evidence.
        case local
        /// At another: positive evidence of a session carried in from
        /// elsewhere, as the session is now.
        case remote
        /// Neither can be shown: inside a session keeper whose clients cannot
        /// be asked (screen, zellij, dtach and the rest of rung 4's), a tmux
        /// that could not be asked or whose clients are all here though the
        /// pane's variables say ssh, a chain that could not be read, or a
        /// platform with no processes to walk.
        case unknown
    }

    /// The judgement, posed on the inputs ``isLocal(environment:ownChain:tmuxClientChains:inTmux:)``
    /// is.
    ///
    /// Local wherever that says local. Otherwise remote only on evidence of
    /// the session as it is now, not as it was started:
    ///
    /// - Inside tmux, the clients: one whose chain passes a remote-session
    ///   daemon before any session keeper above its own tmux is watching from
    ///   another machine. The pane's variables and chain were the server's
    ///   when it started (a session started over ssh and attached at the desk
    ///   keeps `SSH_CONNECTION`), so they say nothing here.
    /// - Outside it, the chain: a remote-session daemon nearer this process
    ///   than any session keeper. A keeper nearer — or one's variable set —
    ///   holds the session for whoever attaches, so what is above it, and
    ///   the ssh variables it kept, are its start's.
    /// - Then the ssh variables, where no keeper is known to hold the session.
    ///
    /// The rest is ``Judgement/unknown``.
    static func judgement(
        environment: [String: String], ownChain: [String]?, tmuxClientChains: [[String]?]?, inTmux: Bool
    ) -> Judgement {
        if isLocal(environment: environment, ownChain: ownChain, tmuxClientChains: tmuxClientChains, inTmux: inTmux) {
            return .local
        }
        if inTmux {
            let watchedFromAfar = tmuxClientChains?.contains { chain in
                // The client is itself named tmux, the chain's first name: a
                // keeper counts only above it, as in `isLocal`.
                guard let chain else { return false }
                return daemonBeforeKeeper(chain) { index, name in isSessionKeeper(name, inTmux: index == 0) }
            }
            return watchedFromAfar == true ? .remote : .unknown
        }
        // A chain that cannot be read cannot show that no keeper holds the
        // session (dtach, tmate and WezTerm's mux set no variable).
        guard let ownChain else { return .unknown }
        if daemonBeforeKeeper(ownChain, isKeeper: { isSessionKeeper($1, inTmux: false) }) {
            return .remote
        }
        let kept =
            sessionKeeperVariables.contains { environment[$0]?.isEmpty == false }
            || ownChain.contains { isSessionKeeper($0, inTmux: false) }
        if kept { return .unknown }
        let ssh = ["SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"].contains { environment[$0]?.isEmpty == false }
        return ssh ? .remote : .unknown
    }

    /// Whether `chain` passes a remote-session daemon before (nearer the
    /// process than) the first name `isKeeper` says keeps a session.
    private static func daemonBeforeKeeper(_ chain: [String], isKeeper: (Int, String) -> Bool) -> Bool {
        for (index, name) in chain.enumerated() {
            if isRemoteSessionDaemon(name) { return true }
            if isKeeper(index, name) { return false }
        }
        return false
    }

    /// The judgement for this process, now.
    ///
    /// Inside tmux this asks tmux for its clients — a bounded subprocess — so
    /// it is asked when something is about to say where the user is (a file
    /// panel as it is presented), off the main actor, never per frame.
    package static func judgement() -> Judgement {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            let inputs = Inputs.current()
            return judgement(
                environment: inputs.environment, ownChain: inputs.ownChain,
                tmuxClientChains: inputs.tmuxClientChains, inTmux: inputs.inTmux)
        #else
            // No processes to walk, and so nothing to tell either way.
            return .unknown
        #endif
    }
}
