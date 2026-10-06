//  🖥️ TUIKit — Terminal UI Kit for Swift
//  IdleProbe/main.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

// MARK: - Why this exists
//
// `idle_cpu.py` answers "does a static screen cost anything?", but only if the
// screen is genuinely static. Every page of `Example` that shows an `Image` also
// carries focusable controls, and a focused control pulses — so the loop is
// legitimately awake and the measurement says nothing about the image.
//
// This is the smallest app that can be asked the question: ONE view, nothing
// focusable, no spinner, no cursor, no notifications, no timers. Whatever CPU it
// burns is the subject under test and nothing else.
//
// Run each mode for the same window and compare. `text` is the control: it is
// known-static, so a non-zero reading there means the harness or the terminal is
// the source, not the view.
//
//     swift build -c release --product IdleProbe
//     BIN="$(swift build -c release --product IdleProbe --show-bin-path)/IdleProbe"
//     TUIKIT_CONFIG_DIR=$(mktemp -d) IDLE_PROBE_MODE=text  python3 Tools/Profiling/idle_cpu.py "$BIN"
//     TUIKIT_CONFIG_DIR=$(mktemp -d) IDLE_PROBE_MODE=image python3 Tools/Profiling/idle_cpu.py "$BIN"
//
// `Tools/Profiling/idle-image.sh` does exactly that, both modes, one command.
//
// TUIKIT_CONFIG_DIR matters: without it a PTY probe writes to the real
// preferences directory. $HOME does not isolate it on macOS.
//
// Two modes serve `Tools/Smoke/quit_key_smoke.py` instead, which wants the
// smallest app for a different question — what the terminal driver does with
// the Control keys while TUIkit runs: `keys` shows each key the app hears,
// and `hang` blocks its main thread once on screen. So does
// `IDLE_PROBE_CHILD_PIDFILE`, in any mode: a child in the app's process group
// (bottom of this file).

// MARK: - Mode

/// What to put on screen. Each is deliberately a single view with no
/// interactivity, so the loop has no legitimate reason to wake.
enum ProbeMode: String {
    /// The control: a plain `Text`. Known static; the baseline every other
    /// reading is compared against.
    case text
    /// The subject: an `Image`. A missing file is fine and is in fact the
    /// cheaper test — the load fails fast and settles into the failure phase,
    /// after which nothing should change. Point `IDLE_PROBE_IMAGE` at a real
    /// file to measure a decoded image instead.
    case image
    /// A spinner: the known-NOT-idle case, so a run can prove the harness
    /// notices activity at all. A reading of ~0 here means the measurement is
    /// broken, not that the app is efficient.
    case spinner
    /// Each key the app hears, one row per key (`key ctrl-c`), so a PTY can
    /// tell a key that arrived from one the driver turned into a signal. The
    /// keys go on down the input chain, so `q` still quits.
    case keys
    /// A main thread that never returns once the first frame is up, as an
    /// app stuck in a loop or a blocking call: what the user's quit key, `⌃\`,
    /// has to end anyway.
    case hang

    static var current: ProbeMode {
        ProcessInfo.processInfo.environment["IDLE_PROBE_MODE"]
            .flatMap { ProbeMode(rawValue: $0) } ?? .text
    }
}

private let imagePath =
    ProcessInfo.processInfo.environment["IDLE_PROBE_IMAGE"] ?? "/idle-probe-no-such-file.png"

// MARK: - The app

struct IdleProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeContent()
        }
    }
}

private struct ProbeContent: View {
    var body: some View {
        switch ProbeMode.current {
        case .text:
            Text("idle probe — text")
        case .image:
            Image(.file(imagePath))
                .frame(width: 40, height: 20)
        case .spinner:
            Spinner()
        case .keys:
            KeyEcho()
        case .hang:
            Text("idle probe — hanging")
                .onAppear {
                    // After the frame is drawn, not during it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        while true { Thread.sleep(forTimeInterval: 1) }
                    }
                }
        }
    }
}

/// The `keys` mode: every key the app hears, in order, from the top-left
/// corner down, so a row once drawn never moves and each new one is written
/// whole — what a PTY reading the bytes needs to find `key ctrl-y`.
private struct KeyEcho: View {
    @State private var heard: [String] = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("idle probe — keys")
            ForEach(heard.indices, id: \.self) { index in
                Text("key \(heard[index])")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onKeyEvent { event in
            let name: String
            if case .character(let character) = event.key {
                name = String(character)
            } else {
                name = "\(event.key)"
            }
            heard.append((event.ctrl ? "ctrl-" : "") + name)
            return false
        }
    }
}

// MARK: - A child in the app's process group
//
// `quit_key_smoke.py` asks whether the quit key ends the app's children as the
// terminal driver's ⌃\ does: with `IDLE_PROBE_CHILD_PIDFILE` set, the probe
// starts `sleep` in its own process group, as an app starts a helper, and
// writes its own process ID and the child's to that file.
if let path = ProcessInfo.processInfo.environment["IDLE_PROBE_CHILD_PIDFILE"] {
    var child: pid_t = 0
    let arguments: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sleep"), strdup("120"), nil]
    let environment: [UnsafeMutablePointer<CChar>?] = [nil]
    if posix_spawn(&child, "/bin/sleep", nil, nil, arguments, environment) == 0 {
        try? "\(getpid()) \(child)".write(toFile: path, atomically: true, encoding: .utf8)
    }
    arguments.forEach { free($0) }
}

await IdleProbeApp.main()
