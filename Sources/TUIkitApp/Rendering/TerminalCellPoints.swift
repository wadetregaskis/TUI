//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalCellPoints.swift
//
//  The terminal cell's size in POINTS — the unit SwiftUI sizes an image in —
//  worked out per host from what each one reports, measured.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

// MARK: - What a host's pixels are

/// How many of the pixels a terminal reports through `TIOCGWINSZ` make one
/// point, on each axis.
///
/// The reported "pixels" are not one unit across hosts, and that is the whole
/// reason this exists. Measured on one Retina Mac (`Terminal compatibility survey.md`,
/// "A cell's size in points"):
///
/// | Host | `TIOCGWINSZ` per cell | in points |
/// |---|---|---|
/// | Apple Terminal 455.1 | 7 × 14 | 7 × 14 — points already |
/// | Warp | 8 × 16 | 8 × 16 — points already |
/// | iTerm2 3.6.11 | 14 × 34 | 7.125 × 18.32 — `CSI 14 t` answers in points |
/// | Ghostty 1.3.1 | 16 × 34 | 8 × 17 — device pixels, at the display's scale |
///
/// Applied to every later reading, so a font change, which moves the reported
/// pixels, moves the points with them.
struct CellPointsCalibration: Equatable, Sendable {
    /// Reported pixels per point, across.
    var pixelsPerPointWide: Double

    /// Reported pixels per point, down.
    var pixelsPerPointHigh: Double

    /// The terminal reports points.
    static let points = Self(pixelsPerPointWide: 1, pixelsPerPointHigh: 1)

    /// A cell of `pixels` reported pixels, in points.
    func points(for pixels: TerminalCellPixels) -> TerminalCellPoints {
        TerminalCellPoints(
            width: Double(pixels.width) / pixelsPerPointWide, height: Double(pixels.height) / pixelsPerPointHigh)
    }
}

extension EnvironmentValues {
    /// Publishes the cell's size as the terminal reports it this frame: in
    /// pixels, and — on the hosts whose pixels are measured — in points, what
    /// an image that is not resizable takes its natural size from.
    mutating func publishCell(pixels: TerminalCellPixels, calibration: CellPointsCalibration?) {
        imageCellPixels = pixels
        imageCellPoints = calibration?.points(for: pixels)
    }
}

// MARK: - Asking iTerm2

/// `CSI 14 t` — the text area's size in pixels — asked of iTerm2, which
/// answers it in points where its `TIOCGWINSZ` fields are retina-scaled.
///
/// The text area rather than `CSI 16 t`'s cell, because iTerm2's cell is not a
/// whole number of points (7.125 × 18.32 at its default font), and `16 t`
/// answers whole numbers: divided by the grid, the area keeps the fraction.
///
/// Fenced with the status report, as every startup question is, so a terminal
/// that ignores it answers the fence alone. Not the cursor report: its reply,
/// `CSI row ; column R`, is a modified F3's shape (Shift-F3 is `CSI 1;2 R`),
/// and one pressed during the exchange would end it before the answer and be
/// lost as the fence (see ``TerminalIdentityQuery``).
enum TerminalTextAreaQuery {
    /// The question and its fence.
    static let request = "\u{1B}[14t" + TerminalQueryReplies.statusFence

    /// The text area's size, from the reply `CSI 4 ; height ; width t`, or
    /// `nil` where `bytes` carries none.
    static func parse(_ bytes: [UInt8]) -> (width: Int, height: Int)? {
        let prefix = Array("\u{1B}[4;".utf8)
        var index = 0
        while index + prefix.count < bytes.count {
            guard bytes[index..<(index + prefix.count)].elementsEqual(prefix) else {
                index += 1
                continue
            }
            var cursor = index + prefix.count
            func number() -> Int? {
                let begin = cursor
                while cursor < bytes.count, bytes[cursor] >= 0x30, bytes[cursor] <= 0x39 { cursor += 1 }
                return ASCIIDecimal.value(of: bytes[begin..<cursor])
            }
            guard let height = number(), cursor < bytes.count, bytes[cursor] == 0x3B else {
                index += 1
                continue
            }
            cursor += 1
            guard let width = number(), cursor < bytes.count, bytes[cursor] == 0x74,  // 't'
                width > 0, height > 0
            else {
                index += 1
                continue
            }
            return (width, height)
        }
        return nil
    }

    /// Whether one complete escape sequence is a window report,
    /// `CSI … t`. No key sends one.
    static func isReply(_ sequence: ArraySlice<UInt8>) -> Bool {
        guard sequence.count >= 3, sequence.first == 0x1B, sequence[sequence.startIndex + 1] == 0x5B
        else { return false }
        return sequence.last == 0x74  // 't'
    }
}

extension Terminal {
    /// The text area's size as the terminal answers `CSI 14 t`, or `nil` where
    /// it did not — through ``fencedExchange(request:timeout:sawFence:)``, and
    /// handing back what else arrived, as every startup question does.
    func queryTextAreaSize(timeout: Double = 0.5) -> (width: Int, height: Int)? {
        guard isatty(STDIN_FILENO) == 1, isRawMode else { return nil }
        return askTextAreaSize(timeout: timeout)
    }

    /// The exchange behind ``queryTextAreaSize(timeout:)``, without its guard.
    ///
    /// Apart so a test can run the exchange through ``readSource`` and
    /// ``exchangeTransport``, as ``askMode(_:timeout:)`` is.
    func askTextAreaSize(timeout: Double) -> (width: Int, height: Int)? {
        let collected = fencedExchange(
            request: TerminalTextAreaQuery.request, timeout: timeout, sawFence: TerminalQueryReplies.sawStatusFence)
        handBackUnconsumed(
            from: collected, isReply: TerminalTextAreaQuery.isReply, isFence: TerminalQueryReplies.isStatusFence)
        return TerminalTextAreaQuery.parse(collected)
    }
}

// MARK: - Deciding, at startup

extension TerminalClient {
    /// How this terminal's reported pixels become points, or `nil` where that
    /// is not known — and an image there fits what it is offered, as it did
    /// before images had a natural size. Set at startup by
    /// ``detectCellPoints(using:)``.
    @MainActor static var cellPointsCalibration: CellPointsCalibration?

    /// Works out ``cellPointsCalibration`` for the host this is.
    ///
    /// After identification, which names the host, and before the first frame,
    /// which sizes the first image. Asks iTerm2 one question (`CSI 14 t`); asks
    /// nothing of any other host.
    @MainActor
    static func detectCellPoints(using terminal: Terminal) {
        let environment = ProcessInfo.processInfo.environment
        cellPointsCalibration = calibration(
            host: CellPointsHost(
                isTmux: TerminalHost.isTmux, isAppleTerminal: TerminalHost.isAppleTerminal,
                isWarp: TerminalHost.isWarp, isITerm2: TerminalHost.isITerm2, isGhostty: TerminalHost.isGhostty),
            reportedCell: terminal.cellPixelSize(),
            grid: terminal.getSize(),
            textArea: { TerminalHost.isITerm2 && !TerminalHost.isTmux ? terminal.queryTextAreaSize() : nil },
            localDisplayScale: { SessionLocality.isLikelyLocal(environment: environment) ? mainDisplayScale() : nil })
    }

    /// Which measured host this is, for ``calibration(host:reportedCell:grid:textArea:localDisplayScale:)``.
    struct CellPointsHost: Equatable {
        var isTmux = false
        var isAppleTerminal = false
        var isWarp = false
        var isITerm2 = false
        var isGhostty = false
    }

    /// The calibration for a host, posed on its inputs so a test can ask it.
    ///
    /// - tmux: none. It does not forward the client's pixel fields, and two
    ///   clients attached at once would not agree on a cell anyway.
    /// - Apple Terminal and Warp report points.
    /// - iTerm2 answers `CSI 14 t` in points; the calibration is its reported
    ///   cell over the area's.
    /// - Ghostty reports device pixels, so its calibration is the display's
    ///   scale — known only when the app runs on the Mac the terminal is on,
    ///   from the main display. (A window on a display of another scale is
    ///   sized by the main display's.)
    /// - Any other host: none. Its pixels are pixels of a kind nobody here has
    ///   measured.
    ///
    /// - Parameters:
    ///   - host: Which host this is.
    ///   - reportedCell: The cell's size as `TIOCGWINSZ` reports it.
    ///   - grid: The grid, in cells, at the same moment.
    ///   - textArea: Asks the text area's size in points (iTerm2's `CSI 14 t`).
    ///   - localDisplayScale: The main display's scale, where the app runs on
    ///     the terminal's own machine.
    static func calibration(
        host: CellPointsHost, reportedCell: TerminalCellPixels?, grid: (width: Int, height: Int),
        textArea: () -> (width: Int, height: Int)?, localDisplayScale: () -> Double?
    ) -> CellPointsCalibration? {
        guard !host.isTmux else { return nil }
        if host.isAppleTerminal || host.isWarp { return .points }
        guard let reportedCell else { return nil }
        if host.isITerm2 {
            guard let area = textArea(), grid.width > 0, grid.height > 0 else { return nil }
            let pointsWide = Double(area.width) / Double(grid.width)
            let pointsHigh = Double(area.height) / Double(grid.height)
            guard pointsWide > 0, pointsHigh > 0 else { return nil }
            return CellPointsCalibration(
                pixelsPerPointWide: Double(reportedCell.width) / pointsWide,
                pixelsPerPointHigh: Double(reportedCell.height) / pointsHigh)
        }
        if host.isGhostty, let scale = localDisplayScale(), scale > 0 {
            return CellPointsCalibration(pixelsPerPointWide: scale, pixelsPerPointHigh: scale)
        }
        return nil
    }

    /// The main display's scale — device pixels per point — or `nil` where
    /// there is no display to ask.
    static func mainDisplayScale() -> Double? {
        #if canImport(CoreGraphics)
            guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()), mode.width > 0 else { return nil }
            return Double(mode.pixelWidth) / Double(mode.width)
        #else
            return nil
        #endif
    }
}
