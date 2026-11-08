//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalGraphicsQuery.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#endif

// MARK: - Asking whether pictures are possible

/// The startup exchange that asks a terminal whether it can draw an image
/// **into the cell grid**.
///
/// ## Why this is asked rather than looked up
///
/// Every other terminal capability in this project is a table: a host is
/// identified, and what it can do is what somebody measured it doing. That is
/// forced on us — no terminal reports whether it honours OSC 8, or how far it
/// advances a keycap. The Kitty graphics protocol is the exception. It has a
/// real handshake, and the handshake answers the question at the granularity
/// that matters:
///
/// - **Warp** answers the *protocol* query `OK` and then refuses a virtual
///   placement by name — `UnicodePlaceholderUnsupported`. A table written from
///   its feature list would have said "supports Kitty graphics" and been
///   wrong about the only part TUI uses.
/// - **Ghostty** answers `OK` to both.
/// - **Apple Terminal** and **tmux** answer nothing.
///
/// So the question asked here is not "does this terminal speak the protocol"
/// but "will it place an image for me": a one-pixel image is transmitted, a
/// virtual placement of it is requested, and the image is deleted again. Only
/// `OK` to the *placement* counts.
///
/// ## Why the cursor is asked about too
///
/// `OK` is not enough. A host that does not know the `U` key reads a virtual
/// placement as a classic one, draws it at the cursor and answers `OK`: Konsole
/// reads no `U` and acknowledges every `a=p` (source, 2026-11-01), and its
/// placeholder cells would print as tofu. And a host may place a picture and
/// answer nothing: WezTerm's `a=p` sends no reply (source, 2026-11-01). What
/// tells them apart is what a placement does to the **cursor**: a classic one
/// moves it (unless `C=1`), a virtual one has no position to move it from. So
/// four cursor reports go around the questions, read by ``parse(_:)``. Measured
/// on Ghostty 1.4.0, iTerm2 3.7.6 and Warp, `classic_placement_probe.py`; kitty
/// moves it only `!g->unicode_placement` (source, `graphics.c`).
///
/// ## Why it is not asked of everybody
///
/// This is an APC sequence, and **Apple Terminal does not parse APC** — it
/// prints the payload (measured; `Documentation/Terminals/Terminal compatibility survey.md`).
/// Two defences, because one is a table and tables go stale:
///
/// 1. The exchange is skipped on a host identified as one that prints APC.
/// 2. It is wrapped in save-cursor, restore-cursor and erase-to-end anyway
///    (`ESC 7` … `ESC 8 ESC [J`), so an unmeasured terminal with the same
///    parser gap has whatever it printed wiped before the first frame. The
///    payload is kept deliberately tiny (one pixel, ~80 bytes) so that what
///    such a host prints fits in a row.
enum TerminalGraphicsQuery {

    /// The id the handshake borrows. The top of the range, so it cannot
    /// collide with one ``TerminalImageStore`` has allocated — that store
    /// counts up from 1.
    static let probeID: KittyGraphics.ImageID = KittyGraphics.maximumImageID

    /// The id the compression probe borrows — the one below the placement's,
    /// and equally out of the store's reach.
    static let compressionProbeID: KittyGraphics.ImageID = KittyGraphics.maximumImageID - 1

    /// The id the classic placement borrows: below the hairlines' sixteen strips
    /// (``HairlineLayer/firstStripID``), which count down from below the other
    /// two. Deleted before the store hands out its first id, so never in its way.
    static let classicProbeID: KittyGraphics.ImageID = KittyGraphics.maximumImageID - 18

    /// The id the frame question borrows, the one below the classic placement's.
    /// Deleted before the store hands out its first id.
    static let playbackProbeID: KittyGraphics.ImageID = KittyGraphics.maximumImageID - 19

    /// `CSI 6 n`: where the cursor is, which the host says as `CSI row;col R`.
    private static let cursorReport = "\u{1B}[6n"

    /// How many ``cursorReport``s the request asks for, around its questions.
    fileprivate static let cursorReportCount = 4

    /// One transparent pixel, RGBA: a classic placement of it draws nothing.
    private static let onePixel: [UInt8] = [0, 0, 0, 0]

    /// A 32×32 black RGBA image, deflated: 4,096 bytes that any zlib inflates
    /// from these twenty-six.
    ///
    /// A constant rather than ``SystemZlib``'s output so the question is asked
    /// the same way on every host, zlib or no zlib — and the SIZE is the
    /// point. A terminal that ignores the `o=z` key would read these bytes as
    /// raw pixels, and twenty-six bytes cannot be a 32×32 picture, so it
    /// errors; one that honours the key inflates them to exactly the 4,096 it
    /// expects and answers `OK`. A one-pixel probe could not tell those apart:
    /// its twelve deflated bytes are MORE than the four a pixel needs, and a
    /// terminal that ignored the key might have accepted them.
    private static let deflatedBlock: [UInt8] = [
        0x78, 0x9C, 0xED, 0xC1, 0x01, 0x0D, 0x00, 0x00, 0x00, 0xC2, 0xA0, 0xF7, 0x4F,
        0x6D, 0x0F, 0x07, 0x14, 0x00, 0x00, 0x00, 0xF0, 0x6E, 0x10, 0x00, 0x00, 0x01,
    ]

    /// The exchange: transmit quietly, ask for a placement out loud, delete
    /// quietly; then offer a deflated transmission out loud and delete that
    /// too; tidy up, and fence with DSR so a silent terminal reports silence
    /// instead of hanging.
    ///
    /// Four commands speak, and they are told apart by id — see ``parse(_:)``.
    /// Everything else is `q=2`, so the reply holds exactly the four answers
    /// and not a chorus of acknowledgements in the same `ESC _ G i=…;` shape.
    /// The classic placement states no `C`, so a host that places it moves the
    /// cursor, and asks for a `z` that is not 0 as every placement does.
    ///
    /// The cursor is saved with DECSC (`ESC 7`) and restored with DECRC
    /// (`ESC 8`), not SCOSC/SCORC (`CSI s`/`CSI u`). Ghostty's VT reference
    /// reads `CSI s` as DECSLRM (set left and right margins) whenever mode 69
    /// is on, and whether SCORC restores the SGR state is up to the terminal;
    /// DECSC saves the position and the SGR state, and every VT100 descendant
    /// reads it one way. Cosmetic here — no measured host leaves mode 69 on —
    /// but the spelling with one meaning is the one to use
    /// (`Documentation/Terminals/Ghostty VT reference adoption study.md`, K6).
    static var request: String {
        "\u{1B}7"  // DECSC: save the cursor, in case the payload is printed
            + "\u{1B}[B"  // CUD: off row 1, so no report can be read as a key
            + cursorReport
            + KittyGraphics.transmit(pixels: onePixel, width: 1, height: 1, id: probeID)
            + KittyGraphics.transmit(pixels: onePixel, width: 1, height: 1, id: classicProbeID)
            + cursorReport
            + "\u{1B}_Ga=p,U=1,q=0,i=\(probeID),c=1,r=1\u{1B}\\"
            + cursorReport
            + "\u{1B}_Ga=p,q=0,i=\(classicProbeID),p=1,c=1,r=1,z=1\u{1B}\\"
            + cursorReport
            + KittyGraphics.delete(id: probeID)
            + KittyGraphics.delete(id: classicProbeID)
            + compressionRequest
            + playbackRequest
            + "\u{1B}8\u{1B}[J"  // DECRC, and wipe whatever was printed
            + TerminalQueryReplies.statusFence
    }

    /// The compression half: the deflated block, transmitted with `o=z` and
    /// `q=0` so the transmission itself is the thing acknowledged or refused.
    /// No placement — nothing about a picture is in question here, only
    /// whether the bytes were understood.
    private static var compressionRequest: String {
        var encoded: [UInt8] = []
        KittyGraphics.base64(deflatedBlock, into: &encoded)
        return "\u{1B}_Ga=t,q=0,f=32,t=d,o=z,s=32,v=32,i=\(compressionProbeID);"
            + KittyGraphics.ascii(encoded) + "\u{1B}\\"
            + KittyGraphics.delete(id: compressionProbeID)
    }

    /// The playback half: a second frame added to a one-pixel picture, out loud.
    /// Credited only for naming the frame it made (`r=2`), as kitty's and Ghostty's
    /// replies do: a host that acknowledges what it does not read cannot know the
    /// number. Warp refuses this by name and iTerm2 says nothing
    /// (`animation_probe.py`).
    private static var playbackRequest: String {
        var encoded: [UInt8] = []
        KittyGraphics.base64(onePixel, into: &encoded)
        return KittyGraphics.transmit(pixels: onePixel, width: 1, height: 1, id: playbackProbeID)
            + "\u{1B}_Ga=f,q=0,f=32,t=d,s=1,v=1,z=40,i=\(playbackProbeID);" + KittyGraphics.ascii(encoded) + "\u{1B}\\"
            + KittyGraphics.delete(id: playbackProbeID)
    }

    /// What the terminal said to each of the questions.
    struct Answers: Equatable {
        /// It drew — accepted — a virtual placement.
        var placement = false
        /// It accepted a deflated transmission.
        var compression = false
        /// It drew, or acknowledged, a classic placement.
        var classicPlacement = false
        /// It added a frame to a picture, and said which.
        var framePlayback = false
    }

    /// The acknowledgements in `bytes`, each credited to the question that
    /// asked it.
    ///
    /// Reads the APC reply's body rather than searching the buffer for `OK`:
    /// the body is `i=<id>;OK` on success and `i=<id>;<some error text>`
    /// otherwise, and at least one of those error texts
    /// (`UnicodePlaceholderUnsupported`) is a refusal that a substring search
    /// for `OK` would not have distinguished from success on its own. The id
    /// decides WHICH question was answered, which is what lets two of them
    /// share one exchange: a placement `OK` carries ``probeID``, a compression
    /// `OK` carries ``compressionProbeID``, a classic one ``classicProbeID``, and
    /// an `OK` naming none of them — a stray acknowledgement of something else —
    /// credits nothing. Then the cursor has its say
    /// (``Answers/correctedByCursor(_:)``).
    static func parse(_ bytes: [UInt8]) -> Answers {
        var answers = Answers()
        var index = bytes.startIndex
        while index + 2 < bytes.endIndex {
            guard bytes[index] == 0x1B, bytes[index + 1] == 0x5F, bytes[index + 2] == 0x47
            else {
                index += 1
                continue
            }
            var end = index + 3
            while end < bytes.endIndex, bytes[end] != 0x1B { end += 1 }
            var body = ""
            body.unicodeScalars.append(
                contentsOf: bytes[(index + 3)..<end].map { Unicode.Scalar($0) })
            if let semicolon = body.firstIndex(of: ";"),
                body[body.index(after: semicolon)...] == "OK"
            {
                let keys = body[..<semicolon].split(separator: ",")
                let id = keys.lazy.compactMap { key -> KittyGraphics.ImageID? in
                    guard key.hasPrefix("i=") else { return nil }
                    return KittyGraphics.ImageID(key.dropFirst(2))
                }.first
                if id == probeID { answers.placement = true }
                if id == compressionProbeID { answers.compression = true }
                if id == classicProbeID { answers.classicPlacement = true }
                if id == playbackProbeID, keys.contains("r=2") { answers.framePlayback = true }
            }
            index = end
        }
        return answers.correctedByCursor(cursorReports(in: bytes))
    }

    /// The cursor reports in `bytes`, in order: `CSI row;col R` on any row but
    /// the first.
    ///
    /// `CSI 1;m R` is a modified F3 (`KeyEvent.parse`), so a report for row 1 is
    /// one that could not be told from a key. The request moves off row 1 before
    /// it asks (``request``), which is what makes this one exchange a safe place
    /// for `CSI 6 n`, here or arriving late, past the fence's timeout. A key stays
    /// a key. On a terminal one row high no report counts, and
    /// ``Answers/correctedByCursor(_:)`` goes by the acknowledgements alone.
    static func cursorReports(in bytes: [UInt8]) -> [[Int]] {
        var reports: [[Int]] = []
        var index = bytes.startIndex
        while index + 1 < bytes.endIndex {
            guard bytes[index] == 0x1B, bytes[index + 1] == 0x5B else {
                index += 1
                continue
            }
            var end = index + 2
            var fields = [0]
            while end < bytes.endIndex, (0x30...0x3B).contains(bytes[end]), bytes[end] != 0x3A {
                if bytes[end] == 0x3B {  // ';'
                    fields.append(0)
                } else {
                    fields[fields.count - 1] = min(fields[fields.count - 1] * 10 + Int(bytes[end] - 0x30), 0xFFFF)
                }
                end += 1
            }
            if end < bytes.endIndex, bytes[end] == 0x52, fields.count == 2, fields[0] > 1 {  // 'R'
                reports.append(fields)
            }
            index = end
        }
        return reports
    }

    /// Whether one complete escape sequence is a reply of this exchange: a Kitty
    /// graphics reply, `ESC _ G … ST`, whichever id it names, which no key sends;
    /// or a cursor report off row 1, which no key sends either
    /// (``cursorReports(in:)``).
    static func isReply(_ sequence: ArraySlice<UInt8>) -> Bool {
        guard sequence.count >= 3, sequence.first == 0x1B else { return false }
        if sequence[sequence.startIndex + 1] == 0x5F {  // '_'
            return sequence[sequence.startIndex + 2] == 0x47  // 'G'
        }
        return cursorReports(in: Array(sequence)).count == 1
    }
}

extension TerminalGraphicsQuery.Answers {
    /// These answers, given what the placements did to the cursor: `reports` is
    /// the four the request asks for, or the acknowledgements stand as they are.
    ///
    /// - Moved by the **transmissions**: the host printed them. It has no
    ///   graphics protocol, whatever else it seemed to say.
    /// - Moved by the **virtual placement**: the host read it as a classic one.
    ///   Its `OK` was not to a virtual placement, and it did place a picture.
    /// - Moved by the **classic placement**: it placed a picture, answer or none.
    fileprivate func correctedByCursor(_ reports: [[Int]]) -> Self {
        guard reports.count == TerminalGraphicsQuery.cursorReportCount else { return self }
        guard reports[0] == reports[1] else { return Self() }
        var answers = self
        if reports[1] != reports[2] {
            answers.placement = false
            answers.classicPlacement = true
        }
        if reports[2] != reports[3] { answers.classicPlacement = true }
        return answers
    }
}

// MARK: - Asking

extension Terminal {

    /// The terminal cell's size in pixels, or `nil` where the terminal does
    /// not report one.
    ///
    /// The same `TIOCGWINSZ` fields ``cellPixelAspect()`` divides out, kept
    /// undivided: an image drawn with the terminal's own graphics protocol is
    /// transmitted at a real pixel size, and an aspect ratio cannot say what
    /// that is. All four measured hosts report it — 16x34 on a Retina Ghostty,
    /// 8x16 on Warp, 7x14 on Apple Terminal — and one that does not gets a
    /// plausible default rather than no picture (see
    /// ``EnvironmentValues/imageCellPixels``).
    func cellPixelSize() -> TerminalCellPixels? {
        #if canImport(WASILibc)
            // wasip1 has no `ioctl`, so the pixel geometry is unavailable and
            // callers take the default cell — the same path a terminal that
            // reports zeroes puts them on.
            return nil
        #else
        var windowSize = winsize()
        #if canImport(Glibc) || canImport(Musl)
            let result = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &windowSize)
        #else
            let result = unsafe ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize)
        #endif
        guard result == 0,
            windowSize.ws_col > 0, windowSize.ws_row > 0,
            windowSize.ws_xpixel > 0, windowSize.ws_ypixel > 0
        else { return nil }
        return TerminalCellPixels(
            width: Int(windowSize.ws_xpixel) / Int(windowSize.ws_col),
            height: Int(windowSize.ws_ypixel) / Int(windowSize.ws_row))
        #endif
    }

    /// Asks the terminal whether it will place an image in the cell grid.
    ///
    /// The same exchange as ``queryMode(_:timeout:)``,
    /// ``fencedExchange(request:timeout:sawFence:)``: one write, then read
    /// until the DSR fence lands or the deadline passes.
    ///
    /// Bytes that arrive during the round trip and are not replies — a
    /// keystroke typed while the app was starting, or a focus report sent the
    /// moment `enableRawMode` turned reporting on — go back to the input
    /// parser through ``handBackUnconsumed(from:isReply:isFence:)``, as every
    /// startup exchange hands them back.
    ///
    /// - Returns: `true` only for a terminal that acknowledged the placement.
    ///   Silence, an error reply, no tty, and a host measured to print APC all
    ///   answer `false` — which costs the glyph renderer, and nothing else.
    func queryGraphicsSupport(timeout: Double = 0.5) -> TerminalGraphicsQuery.Answers {
        guard isatty(STDIN_FILENO) == 1, isRawMode else { return TerminalGraphicsQuery.Answers() }
        // The one host measured to PRINT an APC payload rather than consume
        // it. Everything else gets asked, including terminals nobody has
        // measured — that is the point of a handshake — with the request's own
        // erase as the guard for the ones that share the gap.
        guard !TerminalHost.isAppleTerminal else { return TerminalGraphicsQuery.Answers() }
        return askGraphicsSupport(timeout: timeout)
    }

    /// The exchange behind ``queryGraphicsSupport(timeout:)``, without its
    /// guards.
    ///
    /// Apart so a test can run the exchange through ``readSource`` and
    /// ``exchangeTransport``: the guards want a real TTY in raw mode and a host
    /// that is not Apple Terminal, and a test process may have neither.
    func askGraphicsSupport(timeout: Double) -> TerminalGraphicsQuery.Answers {
        let collected = fencedExchange(
            request: TerminalGraphicsQuery.request, timeout: timeout,
            sawFence: TerminalQueryReplies.sawStatusFence)
        handBackUnconsumed(
            from: collected, isReply: TerminalGraphicsQuery.isReply,
            isFence: TerminalQueryReplies.isStatusFence)
        return TerminalGraphicsQuery.parse(collected)
    }
}
