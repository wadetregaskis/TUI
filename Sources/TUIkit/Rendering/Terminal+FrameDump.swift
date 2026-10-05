//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal+FrameDump.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Terminal {
    /// Writes the raw ANSI bytes of the last completed frame to a
    /// date-stamped `tuikit-frame (…).ansi` in `directory`, the working
    /// directory unless a test names another, and says so in the frame's
    /// top-left corner (``frameDumpNotice(_:)``).
    ///
    /// Triggered by the backtick key — only when the app was launched with
    /// `TUIKIT_DEBUG_FRAME_DUMP=1` (see the run loop's key handling). The file
    /// can be opened in a hex viewer or piped through `cat` in another
    /// terminal to inspect the exact sequences sent for a given frame.
    ///
    /// The notice is drawn over the frame behind the diff writer's back, so
    /// the caller tells the writer to forget what styling the terminal is in
    /// (`RenderLoop.forgetTerminalStyling()`).
    func dumpLastFrame(inDirectory directory: String = FileManager.default.currentDirectoryPath) {
        guard !lastFrameData.isEmpty else {
            writeImmediate(Self.frameDumpNotice("[TUIkit] No frame data to dump"))
            return
        }

        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(Self.frameDumpFilename(for: Date()))

        do {
            try Data(lastFrameData).write(to: url)
            writeImmediate(Self.frameDumpNotice("Frame dumped → \(url.path)"))
        } catch {
            // Show the error on-screen rather than crashing (a crash would leave
            // the terminal in raw-mode / alternate-screen).
            writeImmediate(Self.frameDumpNotice("[TUIkit] Dump failed: \(error)"))
        }
    }

    /// `message` in reverse video at the top-left corner, with the cursor put
    /// back where it was, and in the styling it was in, afterwards.
    ///
    /// DECSC and DECRC (`ESC 7`, `ESC 8`), NOT SCOSC and SCORC (`CSI s`,
    /// `CSI u`), which this used until 2026-10-05. DECRC restores the SGR
    /// attributes along with the position, so the frame the writer carried
    /// its styling across is in that styling again; whether SCORC restores
    /// SGR is up to the terminal. And `CSI s` is not SCOSC at all on a
    /// terminal with left-right margin mode (DEC mode 69) on: Ghostty's
    /// reference lists it as DECSLRM there, which would set margins instead
    /// of saving anything. Found by reading Ghostty's VT reference
    /// (`Documentation/Ghostty-VT-adoption.md`, K6).
    static func frameDumpNotice(_ message: String) -> String {
        "\u{1B}7\u{1B}[1;1H\u{1B}[7m\(message)\u{1B}[0m\u{1B}8"
    }

    /// `tuikit-frame (yyyyMMdd-HHmmss).ansi`, in the local time zone.
    ///
    /// A fixed pattern in a fixed locale, NOT `Date.formatted(date:time:)`:
    /// that style renders in `Locale.autoupdatingCurrent`, and in fifteen
    /// locales — European Portuguese and its regional variants among them —
    /// the abbreviated date carries `/`, which `URL(fileURLWithPath:)` reads
    /// as a directory separator. The dump then targeted a directory that did
    /// not exist and silently never happened.
    static func frameDumpFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "tuikit-frame (\(formatter.string(from: date))).ansi"
    }
}
