//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

// MARK: - Hand-off Demo

/// The Terminal page's last-but-one section: a note, edited in the person's own
/// editor through `\.handOffTerminal`, which hands the terminal to it and takes
/// it back when it ends.
struct HandOffDemo: View {
    @Environment(\.handOffTerminal) private var handOffTerminal
    @State private var note = L("page.terminal.handOffDefault")
    @State private var outcome: String?

    var body: some View {
        DemoSection("page.terminal.handOffSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.terminal.handOffExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                ValueDisplayRow("page.terminal.handOffNote", note)
                Button(L("page.terminal.handOffEdit")) { edit() }
                if let outcome {
                    Text(outcome).foregroundStyle(.palette.foregroundSecondary)
                }
            }
        }
    }

    /// Writes the note to a file, hands the terminal to the editor on it, and
    /// reads it back if the editor ended well.
    private func edit() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("tui-example-note-\(ProcessInfo.processInfo.processIdentifier).txt")
        try? note.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        // `$1` keeps the path out of the command's words; the shell expands the
        // person's own editor, arguments and all, as git does.
        let status = handOffTerminal {
            ForegroundCommand.run(["/bin/sh", "-c", "${VISUAL:-${EDITOR:-vi}} \"$1\"", "sh", file.path])
        }
        guard let status else {
            outcome = L("page.terminal.handOffUnavailable")
            return
        }
        guard status == 0, let edited = try? String(contentsOf: file, encoding: .utf8) else {
            outcome = "\(L("page.terminal.handOffStatus")) \(status)"
            return
        }
        note = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        outcome = L("page.terminal.handOffSaved")
    }
}

// MARK: - Starting a program in the foreground

/// Starts a program the way `\.handOffTerminal`'s documentation asks for an
/// interactive one: in the app's process group, which is the terminal's
/// foreground group, with every signal at its default action and none
/// blocked, and waits for it to end.
///
/// Not Foundation's `Process`, which starts its child in a process group of its
/// own: the terminal treats that as a background job, and stops an editor that
/// reads the keyboard (`SIGTTIN`). And with the defaults, because a program
/// inherits the signals its parent ignores, and the app ignores `SIGPIPE`, and
/// `SIGINT` and `SIGQUIT` while it hands the terminal over.
enum ForegroundCommand {
    /// Runs `arguments` — the program's path, then its arguments — with this
    /// process's environment, and waits for it.
    ///
    /// - Returns: Its exit status, 128 plus the signal that ended it, or `nil`
    ///   where no program can be started.
    static func run(_ arguments: [String]) -> Int32? {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            guard let path = arguments.first else { return nil }
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
            guard unsafe posix_spawn(&child, path, nil, &attributes, argv, envp) == 0 else { return nil }
            var status: Int32 = 0
            while unsafe waitpid(child, &status, 0) < 0 {
                guard errno == EINTR else { return nil }
            }
            // `WIFEXITED` and the rest are macros Swift does not import.
            let signal = status & 0x7F
            return signal == 0 ? (status >> 8) & 0xFF : 128 + signal
        #else
            return nil
        #endif
    }
}
