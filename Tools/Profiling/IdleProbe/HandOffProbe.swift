//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffProbe.swift
//
//  IdleProbe's `handoff` mode, for `Tools/Smoke/hand_off_smoke.py`: a button
//  that hands the terminal to a shell command, and what it saw.
//
//  Created by Wade Tregaskis
//  License: MIT

// A PTY and child processes, neither of which wasip1 has (see main.swift).
#if !canImport(WASILibc)

import Foundation
import TUI

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// The `handoff` mode: one button, which hands the terminal to
/// `IDLE_PROBE_HANDOFF_COMMAND` (run by `/bin/sh -c`) through
/// `\.handOffTerminal`, and rows saying the scene's phase, how many hand-offs
/// have ended and how the last command ended (`exit 0`, `signal 2`). A row at
/// the bottom, so a repaint at a new size shows on that size's last line.
///
/// With `IDLE_PROBE_HANDOFF_PIDFILE` set, the app's process ID and the
/// command's go to that file as the command starts, for the harness to watch
/// a ⌃Z stop both.
struct HandOffProbe: View {
    @Environment(\.handOffTerminal) private var handOffTerminal
    @Environment(\.scenePhase) private var scenePhase
    @State private var handOffs = 0
    @State private var outcome = "none"

    private static let environment = ProcessInfo.processInfo.environment
    private static let command = environment["IDLE_PROBE_HANDOFF_COMMAND"] ?? "true"
    private static let pidFile = environment["IDLE_PROBE_HANDOFF_PIDFILE"]

    var body: some View {
        VStack(alignment: .leading) {
            Text("idle probe — handoff")
            Text("phase \(phaseName)")
            Text("handoffs \(handOffs) \(outcome)")
            Button("hand off") {
                outcome = handOffTerminal { Self.run(Self.command) }
                handOffs += 1
            }
            Spacer()
            Text("bottom row")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var phaseName: String {
        switch scenePhase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    /// Runs `command` with `/bin/sh -c` in this process group, every signal at
    /// its default and none blocked, and waits for it: how `\.handOffTerminal`'s
    /// documentation says to start an interactive program. Returns how it
    /// ended.
    private static func run(_ command: String) -> String {
        let arguments = ["/bin/sh", "-c", command]
        let environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        let argv: [UnsafeMutablePointer<CChar>?] = unsafe arguments.map { unsafe strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = unsafe environment.map { unsafe strdup($0) } + [nil]
        defer {
            unsafe argv.forEach { unsafe free($0) }
            unsafe envp.forEach { unsafe free($0) }
        }
        #if canImport(Darwin)
            var attributes: posix_spawnattr_t?
        #else
            var attributes = unsafe posix_spawnattr_t()
        #endif
        unsafe posix_spawnattr_init(&attributes)
        defer { unsafe posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        unsafe sigfillset(&defaults)
        unsafe sigdelset(&defaults, SIGKILL)
        unsafe sigdelset(&defaults, SIGSTOP)
        unsafe posix_spawnattr_setsigdefault(&attributes, &defaults)
        var none = sigset_t()
        unsafe sigemptyset(&none)
        unsafe posix_spawnattr_setsigmask(&attributes, &none)
        unsafe posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        var child: pid_t = 0
        let spawned = unsafe posix_spawn(&child, "/bin/sh", nil, &attributes, argv, envp)
        guard spawned == 0 else { return "spawn failed \(spawned)" }
        if let pidFile {
            try? "\(getpid()) \(child)".write(toFile: pidFile, atomically: true, encoding: .utf8)
        }
        var status: Int32 = 0
        while unsafe waitpid(child, &status, 0) < 0 {
            guard errno == EINTR else { return "wait failed \(errno)" }
        }
        // `WIFEXITED` and friends are macros Swift does not import.
        let signal = status & 0x7F
        return signal == 0 ? "exit \((status >> 8) & 0xFF)" : "signal \(signal)"
    }
}

#endif
