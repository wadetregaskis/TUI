//  🖥️ TUI — A Terminal UI framework for Swift
//  ProcessAncestryTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUITerminalHost
@testable import TUITestSupport

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@Suite("Process ancestry")
struct ProcessAncestryTests {
    @Test("A process's parent is the one the kernel reports to the process itself")
    func ownParent() {
        #expect(ProcessAncestry.parent(of: getpid()) == getppid())
    }

    /// The terminal read from the kernel's record is there exactly where
    /// this process has a controlling terminal — where it can open
    /// `/dev/tty`, which a suite run from a script or CI cannot — and names a
    /// terminal device. (`/dev/tty`'s own device number is not the
    /// terminal's: it is the indirection, on Darwin and Linux alike.)
    @Test("A process's controlling terminal is read where it has one, and is a terminal")
    func ownTerminal() throws {
        let link = try #require(ProcessAncestry.link(of: getpid()))
        let descriptor = open("/dev/tty", O_RDONLY | O_NOCTTY)
        if descriptor >= 0 { close(descriptor) }
        #expect((link.terminal != nil) == (descriptor >= 0))
        guard let terminal = link.terminal else { return }
        #if canImport(Darwin)
            let name = devname(terminal, S_IFCHR).map { String(cString: $0) } ?? ""
            #expect(name.hasPrefix("tty") || name == "console")
        #else
            // `tty_nr`'s major: the virtual consoles and serial lines (4),
            // the console (5), the ptys (136–143).
            let major = (terminal >> 8) & 0xFFF
            #expect(major == 4 || major == 5 || (136...143).contains(major))
        #endif
    }

    /// What holds a process's terminal is the first process above it on
    /// another terminal, or on none, not one further up.
    @Test("A terminal's holder is the first process above it on another terminal")
    func terminalHolder() {
        func chain(_ links: [(String, Int32?)]) -> [ProcessAncestry.Link] {
            links.map { ProcessAncestry.Link(name: $0.0, terminal: $0.1) }
        }
        let inScreen = chain([("tmux", 5), ("zsh", 5), ("SCREEN", nil), ("launchd", nil)])
        #expect(ProcessAncestry.terminalHolder(of: inScreen)?.name == "SCREEN")
        let xtermFromScreen = chain([("tmux", 7), ("bash", 7), ("xterm", 3), ("bash", 3), ("SCREEN", nil)])
        #expect(ProcessAncestry.terminalHolder(of: xtermFromScreen)?.name == "xterm")
        #expect(ProcessAncestry.terminalHolder(of: chain([("tmux", nil), ("SCREEN", nil)])) == nil)
        #expect(ProcessAncestry.terminalHolder(of: chain([("tmux", 5), ("zsh", 5)])) == nil)
        #expect(ProcessAncestry.terminalHolder(of: []) == nil)
    }

    @Test("Following parents from this process reaches the root of the tree")
    func reachesTheRoot() {
        var current = getpid()
        var steps = 0
        while let parent = ProcessAncestry.parent(of: current), steps < 64 {
            current = parent
            steps += 1
        }
        // Process 1, or under `docker exec`, as CI's Linux lanes run, a process
        // whose parent is outside the container and reads as 0.
        #expect(steps < 64)
        #expect(ProcessAncestry.parent(of: current) == nil, "stopped at \(current)")
    }
}
