//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Player.swift
//
//  Plays a clip: runs its app under a pseudo-terminal of the player's own,
//  between the real terminal and the app, and types the script into it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Darwin
import Foundation

/// The player: a relay between the terminal it was started in and the clip's
/// app, which it starts under a pseudo-terminal of its own.
///
/// Everything the app writes is copied to the terminal unchanged, and
/// everything the terminal sends (its answers to TUIkit's queries, a key the
/// viewer presses) to the app, so the app sees the real terminal — its name,
/// its size, its colours — as it would without the player. Into that stream
/// the player types the script's keys, at the script's instants, and those go
/// through TUIkit's own input path exactly as typed keys do.
///
/// The markers file gets lines of a name and a `CLOCK_UPTIME_RAW` time in
/// nanoseconds — the clock ScreenCaptureKit stamps its frames with: `start`,
/// when the script's clock starts, and `end`, when it has played. The recorder
/// stops at `end`, and the encoder keeps the frames between the two.
///
/// Before the app starts, the player draws a calibration card (see
/// ``calibrate(size:)``) and notes `calibrated` once the recorder has filmed
/// it, with a `grid` line giving the terminal's size in cells: from the card
/// the encoder learns where the grid sits in the window and how big a cell is,
/// in the film's own pixels, whatever the terminal, its font, its padding and
/// its title bar — so a clip's camera can be stated in cells.
struct Player {
    let clip: Clip
    let markers: String?
    /// How long the app is given, after its first output, to settle — to ask
    /// the terminal what it is and draw its first full frame — before the
    /// script starts. Nothing before the script's start is kept.
    var settle = 1.2
    /// How long the last frame is held after the script ends.
    var hold = 0.0

    func play() -> Int32 {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) != 0 {
            size = winsize(ws_row: UInt16(clip.rows), ws_col: UInt16(clip.columns), ws_xpixel: 0, ws_ypixel: 0)
        }
        if markers != nil { calibrate(size: size) }

        // The cue pipe: the app keeps the read end across exec, the player's
        // write end closes on it.
        var cuePipe: [Int32] = [0, 0]
        guard pipe(&cuePipe) == 0 else { return fail("pipe") }
        _ = fcntl(cuePipe[1], F_SETFD, FD_CLOEXEC)
        setenv(ClipCues.environmentKey, String(cuePipe[0]), 1)

        // The child's arguments, made before the fork: between fork and exec
        // the child may only make async-signal-safe calls, and malloc is not.
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        var argv: [UnsafeMutablePointer<CChar>?] = [executable, "--child", clip.id].map { $0.withCString { strdup($0) } }
        argv.append(nil)
        var master: Int32 = -1
        let child = forkpty(&master, nil, nil, &size)
        if child < 0 { return fail("forkpty") }
        if child == 0 {
            execv(executable, &argv)
            _exit(127)
        }
        argv.forEach { free($0) }
        close(cuePipe[0])
        let cues = cuePipe[1]

        var saved = termios()
        let isTerminal = tcgetattr(STDIN_FILENO, &saved) == 0
        if isTerminal {
            var raw = saved
            cfmakeraw(&raw)
            tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        }
        defer { if isTerminal { tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved) } }

        var steps = clip.script[...]
        var clockStart: UInt64?
        var due: UInt64?          // when the next step is due, once the clock runs
        var firstOutput: UInt64?
        var ended = false
        var buffer = [UInt8](repeating: 0, count: 65536)

        loop: while true {
            let now = Self.now()
            // The clock starts once the app has drawn and settled.
            if clockStart == nil, let first = firstOutput, now >= first + Self.nanoseconds(settle) {
                clockStart = now
                due = now
                mark("start", now)
            }
            // Play every step that is due.
            while let deadline = due, now >= deadline, !ended {
                guard let step = steps.popFirst() else {
                    ended = true
                    mark("end", now)
                    break
                }
                switch step {
                case .wait(let seconds): due = deadline + Self.nanoseconds(seconds)
                case .keys(let text): writeAll(master, Array(text.utf8))
                case .cue(let name): writeAll(cues, Array((name + "\n").utf8))
                case .camera: break  // the encoder's, not the app's
                }
            }
            if ended {
                if hold > 0 { usleep(UInt32(hold * 1_000_000)) }
                break loop
            }

            var timeout: Int32 = 100
            if let deadline = due { timeout = Int32(max(0, (Int64(deadline) - Int64(Self.now())) / 1_000_000)) }
            var fds = [pollfd(fd: master, events: Int16(POLLIN), revents: 0),
                       pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)]
            let ready = poll(&fds, 2, timeout)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if fds[0].revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 {
                let count = read(master, &buffer, buffer.count)
                if count <= 0 { break loop }  // the app has gone
                if firstOutput == nil { firstOutput = Self.now() }
                writeAll(STDOUT_FILENO, Array(buffer[0..<count]))
            }
            if fds[1].revents & Int16(POLLIN) != 0 {
                let count = read(STDIN_FILENO, &buffer, buffer.count)
                if count > 0 { writeAll(master, Self.droppingFocusReports(buffer[0..<count])) }
            }
        }

        // Over: the app is asked to quit as a terminal session asks it, and
        // what it writes on the way out (the screen it restores) still goes to
        // the terminal. The recorder stopped at `end`, so none of it is filmed.
        close(cues)
        kill(child, SIGTERM)
        let deadline = Self.now() + Self.nanoseconds(3)
        var status: Int32 = 0
        while waitpid(child, &status, WNOHANG) == 0 {
            if Self.now() > deadline {
                kill(child, SIGKILL)
                waitpid(child, &status, 0)
                break
            }
            var fds = [pollfd(fd: master, events: Int16(POLLIN), revents: 0)]
            if poll(&fds, 1, 20) > 0 {
                let count = read(master, &buffer, buffer.count)
                if count > 0 { writeAll(STDOUT_FILENO, Array(buffer[0..<count])) }
            }
        }
        close(master)
        if !ended { mark("end", Self.now()) }
        return ended ? 0 : 1
    }

    /// Draws the calibration card, waits until the recorder has filmed it, and
    /// clears it.
    ///
    /// The card is two cells painted magenta (`#FF00FF`, colour 201 of the
    /// 256, so a terminal without 24-bit colour paints it exactly too) on a
    /// cleared screen: the second cell of the second row, and the second-last
    /// cell of the second-last row. Not the corner cells, whose colour a
    /// terminal may extend into its padding (Ghostty's
    /// `window-padding-color=extend`). The distance between the two, over the
    /// cells between them, is a cell's size; the first, less a cell, is where
    /// the grid starts.
    ///
    /// The recorder writes `filming` to the markers file once its stream has
    /// started. Played by hand, with nobody filming, the player waits for it
    /// at most 20 seconds.
    private func calibrate(size: winsize) {
        let rows = Int(size.ws_row), columns = Int(size.ws_col)
        let paint = "\u{1B}[48;5;201m \u{1B}[0m"
        let card = "\u{1B}[?25l\u{1B}[2J\u{1B}[2;2H\(paint)\u{1B}[\(rows - 1);\(columns - 1)H\(paint)"
        writeAll(STDOUT_FILENO, Array(card.utf8))
        let deadline = Self.now() + Self.nanoseconds(20)
        while Self.now() < deadline, !markersSay("filming") { usleep(50_000) }
        // Long enough for the terminal to have drawn the card and the stream
        // to have sent the frame that shows it.
        usleep(600_000)
        mark("grid \(columns) \(rows)")
        mark("calibrated", Self.now())
        writeAll(STDOUT_FILENO, Array("\u{1B}[2J\u{1B}[H".utf8))
    }

    private func markersSay(_ word: String) -> Bool {
        guard let markers, let text = try? String(contentsOfFile: markers, encoding: .utf8) else { return false }
        return text.split(separator: "\n").contains { $0.hasPrefix(word + " ") }
    }

    /// The terminal's input without its focus reports (`ESC [ I`, `ESC [ O`).
    ///
    /// A TUIkit app whose terminal loses the focus goes inactive: its focus
    /// stops breathing and its controls draw as an unfocused window's do. The
    /// window being filmed may not be the frontmost — it may open behind
    /// another, or the person running the clips may click elsewhere — and the
    /// clip should look the same either way, so the app is never told.
    static func droppingFocusReports(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if bytes[index] == 0x1B, index + 2 < bytes.endIndex, bytes[index + 1] == 0x5B,
               bytes[index + 2] == 0x49 || bytes[index + 2] == 0x4F {
                index += 3
                continue
            }
            out.append(bytes[index])
            index += 1
        }
        return out
    }

    private func mark(_ name: String, _ time: UInt64) {
        mark("\(name) \(time)")
    }

    /// Appends a line to the markers file. `O_APPEND`, because the recorder
    /// appends to it too (its `filming`), and a write at a remembered offset
    /// could land on top of the other's.
    private func mark(_ line: String) {
        guard let markers else { return }
        let descriptor = open(markers, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { return }
        writeAll(descriptor, Array((line + "\n").utf8))
        close(descriptor)
    }

    private func writeAll(_ descriptor: Int32, _ bytes: [UInt8]) {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            offset += written
        }
    }

    private func fail(_ what: String) -> Int32 {
        FileHandle.standardError.write(Data("ScreenClips: \(what) failed: \(String(cString: strerror(errno)))\n".utf8))
        return 1
    }

    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    static func nanoseconds(_ seconds: Double) -> UInt64 { UInt64(seconds * 1_000_000_000) }
}
