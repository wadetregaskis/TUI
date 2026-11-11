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

/// The `handoff` mode: one button, which hands the terminal to
/// `IDLE_PROBE_HANDOFF_COMMAND` (run by `/bin/sh -c`) through
/// `\.handOffTerminal`'s `running:` form, and rows saying the scene's phase,
/// how many hand-offs have ended and how the last command ended (`exit 0`,
/// `signal 2`). A row at the bottom, so a repaint at a new size shows on that
/// size's last line.
///
/// The harness's commands write their own process IDs and the app's (`$PPID
/// $$`) to `IDLE_PROBE_HANDOFF_PIDFILE`, to watch a ⌃Z stop both.
struct HandOffProbe: View {
    @Environment(\.handOffTerminal) private var handOffTerminal
    @Environment(\.scenePhase) private var scenePhase
    @State private var handOffs = 0
    @State private var outcome = "none"

    private static let environment = ProcessInfo.processInfo.environment
    private static let command = environment["IDLE_PROBE_HANDOFF_COMMAND"] ?? "true"

    var body: some View {
        VStack(alignment: .leading) {
            Text("idle probe — handoff")
            Text("phase \(phaseName)")
            Text("handoffs \(handOffs) \(outcome)")
            Button("hand off") {
                outcome = run(Self.command)
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

    /// Runs `command` with `/bin/sh -c` through
    /// `handOffTerminal(running:arguments:)`, and says how it ended.
    private func run(_ command: String) -> String {
        do {
            switch try handOffTerminal(running: .path("/bin/sh"), arguments: ["-c", command]) {
            case .exit(let status): return "exit \(status)"
            case .uncaughtSignal(let signal): return "signal \(signal)"
            @unknown default: return "ended"
            }
        } catch {
            return "failed \(error)"
        }
    }
}

#endif
