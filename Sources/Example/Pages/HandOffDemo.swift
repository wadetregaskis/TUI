//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

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
                Text(Self.explanation)
                    .foregroundStyle(.palette.foregroundSecondary)
                ValueDisplayRow("page.terminal.handOffNote", note)
                Button(L("page.terminal.handOffEdit")) { edit() }
                if let outcome {
                    Text(outcome).foregroundStyle(.palette.foregroundSecondary)
                }
            }
        }
    }

    /// What the section says it does. Windows' editor when none is set is
    /// `edit`, and Ctrl-Break, not ⌃Z, is the other key the program has there:
    /// ⌃Z is a key like any other in a Windows console.
    #if os(Windows)
        private static let explanation: LocalizedStringKey = "page.terminal.handOffExplainWindows"
    #else
        private static let explanation: LocalizedStringKey = "page.terminal.handOffExplain"
    #endif

    /// Writes the note to a file, hands the terminal to the editor on it, and
    /// reads it back if the editor ended well.
    private func edit() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("tui-example-note-\(ProcessInfo.processInfo.processIdentifier).txt")
        try? note.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        // `$1` keeps the path out of the command's words; the shell expands the
        // person's own editor, arguments and all, as git does.
        let ended: HandOffTerminalAction.Termination
        do {
            #if os(Windows)
                // No shell to split the setting: its first word is the program,
                // the rest its arguments. `edit` is Windows' own console editor.
                let environment = ProcessInfo.processInfo.environment
                let editor = (environment["VISUAL"] ?? environment["EDITOR"] ?? "edit").split(separator: " ")
                ended = try handOffTerminal(
                    running: .name(editor.first.map(String.init) ?? "edit"),
                    arguments: editor.dropFirst().map(String.init) + [file.path]
                )
            #else
                ended = try handOffTerminal(
                    running: .path("/bin/sh"),
                    arguments: ["-c", "${VISUAL:-${EDITOR:-vi}} \"$1\"", "sh", file.path]
                )
            #endif
        } catch {
            outcome = L("page.terminal.handOffUnavailable")
            return
        }
        guard ended == .exit(0), let edited = try? String(contentsOf: file, encoding: .utf8) else {
            outcome = "\(L("page.terminal.handOffStatus")) \(Self.describe(ended))"
            return
        }
        note = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        outcome = L("page.terminal.handOffSaved")
    }

    /// An ending as a shell shows it: the exit status, or 128 plus the signal
    /// that ended the editor.
    static func describe(_ ended: HandOffTerminalAction.Termination) -> String {
        switch ended {
        case .exit(let status): "\(status)"
        case .uncaughtSignal(let signal): "\(128 + signal)"
        @unknown default: "?"
        }
    }
}
