//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardLocalityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@Suite("Clipboard: whether the user is at this machine")
struct ClipboardLocalityTests {
    static let deskChain = ["zsh", "login", "Terminal", "launchd"]

    @Test("A desk session is local")
    func desk() {
        #expect(
            ClipboardLocality.isLocal(
                environment: [:], ownChain: Self.deskChain, tmuxClientChains: nil, inTmux: false))
    }

    @Test(
        "Any ssh variable says not",
        arguments: ["SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"])
    func sshVariables(_ name: String) {
        #expect(
            !ClipboardLocality.isLocal(
                environment: [name: "10.0.0.1 5000 10.0.0.2 22"], ownChain: Self.deskChain,
                tmuxClientChains: nil, inTmux: false))
    }

    /// mosh sets no variable: the chain is the only witness.
    @Test(
        "A remote-session daemon in the chain says not",
        arguments: ["sshd", "sshd-session", "mosh-server", "dropbear", "etserver"])
    func daemons(_ daemon: String) {
        #expect(
            !ClipboardLocality.isLocal(
                environment: [:], ownChain: ["zsh", daemon, "launchd"], tmuxClientChains: nil, inTmux: false))
    }

    /// A session started at the desk and attached over ssh later: the pane's
    /// chain ends at the keeper's daemonised server, and its environment was
    /// set at the desk, so neither rung 1 nor 2 sees the ssh.
    @Test(
        "A session keeper in the chain says not",
        arguments: ["screen", "SCREEN", "zellij", "dtach", "abduco", "shpool"])
    func sessionKeepers(_ keeper: String) {
        #expect(
            !ClipboardLocality.isLocal(
                environment: [:], ownChain: ["zsh", keeper, "launchd"], tmuxClientChains: nil, inTmux: false))
    }

    @Test(
        "A session keeper's variable says not",
        arguments: ["STY", "ZELLIJ", "ZELLIJ_SESSION_NAME", "ABDUCO_SESSION", "SHPOOL_SESSION_NAME"])
    func sessionKeeperVariables(_ name: String) {
        #expect(
            !ClipboardLocality.isLocal(
                environment: [name: "0"], ownChain: Self.deskChain, tmuxClientChains: nil, inTmux: false))
    }

    @Test("A tmux server in the chain is evidence only through its clients")
    func tmuxServerOutsideAPane() {
        let chain = ["zsh", "tmux: server", "launchd"]
        #expect(!ClipboardLocality.isLocal(environment: [:], ownChain: chain, tmuxClientChains: nil, inTmux: false))
        #expect(
            ClipboardLocality.isLocal(
                environment: [:], ownChain: chain, tmuxClientChains: [Self.deskChain], inTmux: true))
        // A client attached from inside a screen session is as far away as it.
        #expect(
            !ClipboardLocality.isLocal(
                environment: [:], ownChain: chain, tmuxClientChains: [["tmux", "zsh", "screen", "launchd"]],
                inTmux: true))
    }

    @Test("A chain that could not be read is not evidence")
    func unreadableChain() {
        #expect(!ClipboardLocality.isLocal(environment: [:], ownChain: nil, tmuxClientChains: nil, inTmux: false))
    }

    @Test("Inside tmux every client must be local, and one must be attached")
    func tmuxClients() {
        let paneChain = ["zsh", "tmux", "launchd"]
        func local(_ clients: [[String]?]?) -> Bool {
            ClipboardLocality.isLocal(environment: [:], ownChain: paneChain, tmuxClientChains: clients, inTmux: true)
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
