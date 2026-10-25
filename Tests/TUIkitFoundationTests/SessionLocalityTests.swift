//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SessionLocalityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore
@testable import TUIkitTerminalHost
@testable import TUIkitTestSupport

@Suite("Session locality: whether the user is at this machine")
struct SessionLocalityTests {
    static let deskChain = ["zsh", "login", "Terminal", "launchd"]

    @Test("A desk session is local")
    func desk() {
        #expect(
            SessionLocality.isLocal(
                environment: [:], ownChain: Self.deskChain, tmuxClientChains: nil, inTmux: false))
    }

    @Test(
        "Any ssh variable says not",
        arguments: ["SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"])
    func sshVariables(_ name: String) {
        #expect(
            !SessionLocality.isLocal(
                environment: [name: "10.0.0.1 5000 10.0.0.2 22"], ownChain: Self.deskChain,
                tmuxClientChains: nil, inTmux: false))
    }

    /// mosh sets no variable: the chain is the only witness.
    @Test(
        "A remote-session daemon in the chain says not",
        arguments: ["sshd", "sshd-session", "mosh-server", "dropbear", "etserver", "etterminal"])
    func daemons(_ daemon: String) {
        #expect(
            !SessionLocality.isLocal(
                environment: [:], ownChain: ["zsh", daemon, "launchd"], tmuxClientChains: nil, inTmux: false))
    }

    /// A session started at the desk and attached over ssh later: the pane's
    /// chain ends at the keeper's daemonised server, and its environment was
    /// set at the desk, so neither rung 1 nor 2 sees the ssh.
    @Test(
        "A session keeper in the chain says not",
        arguments: [
            "screen", "SCREEN", "zellij", "dtach", "abduco", "shpool", "tmate",
            // WezTerm's mux server, as Darwin's 16 bytes and Linux's 15 cut it.
            "wezterm-mux-serv", "wezterm-mux-ser",
        ])
    func sessionKeepers(_ keeper: String) {
        #expect(
            !SessionLocality.isLocal(
                environment: [:], ownChain: ["zsh", keeper, "launchd"], tmuxClientChains: nil, inTmux: false))
    }

    @Test(
        "A session keeper's variable says not",
        arguments: ["STY", "ZELLIJ", "ZELLIJ_SESSION_NAME", "ABDUCO_SESSION", "SHPOOL_SESSION_NAME"])
    func sessionKeeperVariables(_ name: String) {
        #expect(
            !SessionLocality.isLocal(
                environment: [name: "0"], ownChain: Self.deskChain, tmuxClientChains: nil, inTmux: false))
    }

    @Test("A tmux server in the chain is evidence only through its clients")
    func tmuxServerOutsideAPane() {
        let chain = ["zsh", "tmux: server", "launchd"]
        #expect(!SessionLocality.isLocal(environment: [:], ownChain: chain, tmuxClientChains: nil, inTmux: false))
        #expect(
            SessionLocality.isLocal(
                environment: [:], ownChain: chain, tmuxClientChains: [Self.deskChain], inTmux: true))
        // A client attached from inside a screen session is as far away as it.
        #expect(
            !SessionLocality.isLocal(
                environment: [:], ownChain: chain, tmuxClientChains: [["tmux", "zsh", "screen", "launchd"]],
                inTmux: true))
    }

    /// Review 2 of 016fffdfa: at the desk, `tmux` (server A), inside it
    /// `TMUX= tmux -L inner`, the app in inner's pane; detach A, ssh in,
    /// `tmux attach`. Inner's only client runs in a pane of A, so its chain
    /// reads tmux, zsh, tmux (A's server), launchd — and every tmux in it
    /// was exempt, so it passed for local.
    @Test("A tmux client inside another tmux's pane is as far away as that tmux")
    func nestedTmux() {
        let pane = ["zsh", "tmux", "launchd"]
        func local(_ client: [String]) -> Bool {
            SessionLocality.isLocal(environment: [:], ownChain: pane, tmuxClientChains: [client], inTmux: true)
        }
        #expect(!local(["tmux", "zsh", "tmux", "launchd"]))
        // Linux: the outer server renames itself.
        #expect(!local(["tmux", "zsh", "tmux: server", "systemd"]))
        // A client at the desk is still local: only its own name is tmux.
        #expect(local(["tmux", "zsh", "login", "Terminal", "launchd"]))
        #expect(local(["tmux: client", "zsh", "login", "Terminal", "launchd"]))
    }

    /// Review round 1 of the follow-ups: every name starting "tmux" counted
    /// as a tmux, so a wrapper run by its shebang above a desk client — its
    /// process named after the script — made the desk session "not local".
    @Test("A process above a tmux client whose name only starts with tmux is a plain parent")
    func tmuxNamedWrapper() {
        let pane = ["zsh", "tmux", "launchd"]
        for wrapper in ["tmux-sessionizer", "tmuxp", "tmuxinator"] {
            #expect(
                SessionLocality.isLocal(
                    environment: [:], ownChain: pane,
                    tmuxClientChains: [["tmux", wrapper, "zsh", "login", "Terminal", "launchd"]], inTmux: true),
                "\(wrapper)")
        }
        #expect(SessionLocality.isLocal(environment: [:], ownChain: ["tmuxp", "zsh"] + Self.deskChain,
            tmuxClientChains: nil, inTmux: false))
    }

    @Test("A chain that could not be read is not evidence")
    func unreadableChain() {
        #expect(!SessionLocality.isLocal(environment: [:], ownChain: nil, tmuxClientChains: nil, inTmux: false))
    }

    @Test("Inside tmux every client must be local, and one must be attached")
    func tmuxClients() {
        let paneChain = ["zsh", "tmux", "launchd"]
        func local(_ clients: [[String]?]?) -> Bool {
            SessionLocality.isLocal(environment: [:], ownChain: paneChain, tmuxClientChains: clients, inTmux: true)
        }
        #expect(local([Self.deskChain]))
        #expect(!local([Self.deskChain, ["tmux", "zsh", "sshd-session", "sshd", "launchd"]]))
        #expect(!local([Self.deskChain, nil]))
        #expect(!local([]))
        #expect(!local(nil))
    }

    @Test("This process's own chain reads to the root")
    func ownChainReads() throws {
        let chain = try #require(ProcessAncestry.commandNames(from: getpid()))
        #expect(chain.count >= 2)
        #if canImport(Darwin)
            #expect(chain.last == "launchd")
        #endif
    }
}

/// The judgement a file panel's remote-machine notice is shown on: local where
/// `isLocal` says so, remote only on evidence of the session as it is now.
@Suite("Session locality: whether the user is at another machine")
struct SessionJudgementTests {
    static let deskChain = SessionLocalityTests.deskChain
    static let sshChain = ["zsh", "sshd-session", "sshd", "launchd"]
    static let ssh = ["SSH_CONNECTION": "10.0.0.1 5000 10.0.0.2 22"]

    private func judge(
        _ environment: [String: String] = [:], chain: [String]?, clients: [[String]?]? = nil, inTmux: Bool = false
    ) -> SessionLocality.Judgement {
        SessionLocality.judgement(
            environment: environment, ownChain: chain, tmuxClientChains: clients, inTmux: inTmux)
    }

    @Test("A desk session is local; an ssh or mosh session is remote")
    func plainSessions() {
        #expect(judge(chain: Self.deskChain) == .local)
        #expect(judge(Self.ssh, chain: Self.sshChain) == .remote)
        // mosh sets no variable: its daemon in the chain says it.
        #expect(judge(chain: ["zsh", "mosh-server", "launchd"]) == .remote)
        // A daemon TUIkit does not know of, with OpenSSH's variables.
        #expect(judge(Self.ssh, chain: ["zsh", "some-daemon", "launchd"]) == .remote)
    }

    /// The keeper's server runs detached: the variables and the chain above
    /// it are from whenever it started, and anyone may be attached now.
    @Test("Inside a session keeper, what it kept from its start is not evidence")
    func keepers() {
        #expect(judge(Self.ssh, chain: ["zsh", "SCREEN", "launchd"]) == .unknown)
        #expect(judge(["ZELLIJ": "0"], chain: Self.deskChain) == .unknown)
        #expect(judge(["STY": "1.tty"].merging(Self.ssh) { $1 }, chain: Self.deskChain) == .unknown)
        #expect(judge(chain: ["zsh", "dtach", "sshd", "launchd"]) == .unknown)
        // An ssh from inside the session: its daemon is nearer than the keeper.
        #expect(judge(chain: ["zsh", "sshd-session", "sshd", "SCREEN", "launchd"]) == .remote)
    }

    @Test("A chain that could not be read tells nothing, ssh variables or not")
    func unreadableChain() {
        #expect(judge(chain: nil) == .unknown)
        #expect(judge(Self.ssh, chain: nil) == .unknown)
    }

    /// The pane's variables and chain are the tmux server's start; the clients
    /// are who watches now.
    @Test("Inside tmux, a client attached from afar is remote; the pane's variables are not evidence")
    func tmux() {
        let pane = ["zsh", "tmux", "launchd"]
        let remoteClient = ["tmux", "zsh", "sshd-session", "sshd", "launchd"]
        #expect(judge(chain: pane, clients: [Self.deskChain], inTmux: true) == .local)
        #expect(judge(chain: pane, clients: [Self.deskChain, remoteClient], inTmux: true) == .remote)
        // Started over ssh, attached at the desk now.
        #expect(judge(Self.ssh, chain: pane, clients: [["tmux"] + Self.deskChain], inTmux: true) == .unknown)
        #expect(judge(chain: pane, clients: nil, inTmux: true) == .unknown)
        #expect(judge(chain: pane, clients: [nil], inTmux: true) == .unknown)
        // A client inside a screen session that was started over ssh: the
        // keeper holds it, so the sshd above it is that session's start.
        #expect(
            judge(chain: pane, clients: [["tmux", "zsh", "SCREEN", "sshd", "launchd"]], inTmux: true) == .unknown)
    }
}
