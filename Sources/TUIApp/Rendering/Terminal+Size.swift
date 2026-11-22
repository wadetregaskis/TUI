//  🖥️ TUI — A Terminal UI framework for Swift
//  Terminal+Size.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
#endif

// MARK: - Size

/// How big the terminal is: the size to draw at, the window's own grid, and
/// its cell's pixel aspect.
extension Terminal {
    /// The size to draw at: an in-band report, then `COLUMNS` and `LINES`, each on
    /// its own axis, then what the terminal measures, then 80x24.
    ///
    /// A report comes first because a host that sends one (the browser page) starts
    /// its guest with the first size in `COLUMNS`/`LINES` and the later ones as
    /// reports. No terminal sends one unasked, and TUI doesn't ask, so everywhere
    /// else the variables are the last word: the owner's ruling of 2026-11-02, which
    /// means an export left over from a window since resized pins the size, and a
    /// SIGWINCH finds nothing to change on an axis one of them states.
    ///
    /// - Returns: A tuple with width and height in characters/lines.
    func getSize() -> (width: Int, height: Int) {
        Self.size(
            reported: reportedWindowSize,
            columns: terminalDimension(fromEnvironment: "COLUMNS"),
            lines: terminalDimension(fromEnvironment: "LINES"),
            measured: measuredSize())
    }

    /// The rule behind ``getSize()``, posed on its inputs. `measured` costs a system
    /// call, so it is asked for only if a variable leaves an axis open.
    static func size(
        reported: (width: Int, height: Int)?, columns: Int?, lines: Int?,
        measured: @autoclosure () -> (width: Int, height: Int)?
    ) -> (width: Int, height: Int) {
        if let reported { return reported }
        if let columns, let lines { return (columns, lines) }
        let measured = measured()
        return (columns ?? measured?.width ?? 80, lines ?? measured?.height ?? 24)
    }

    /// The cells the window really has, whatever `COLUMNS` and `LINES` say: what a
    /// terminal's reply in pixels, which is about the window, has to be divided by.
    func windowGrid() -> (width: Int, height: Int) {
        reportedWindowSize ?? measuredSize() ?? getSize()
    }

    /// What the terminal says its size is, or `nil` where it can't say.
    private func measuredSize() -> (width: Int, height: Int)? {
        // No `ioctl` on wasip1, and nothing to ask it: a wasm program has no
        // controlling terminal to measure. The environment is the whole answer
        // there, which is why a WebAssembly host has to put the size in
        // `COLUMNS`/`LINES` — see `Documentation/WebAssembly port.md`.
        #if canImport(WASILibc)
            return nil
        #elseif os(Windows)
            return StandardHandle.windowSize()
        #else
            var windowSize = winsize()

            #if canImport(Glibc) || canImport(Musl)
                let result = unsafe ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &windowSize)
            #else
                let result = unsafe ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize)
            #endif

            guard result == 0 && windowSize.ws_col > 0 && windowSize.ws_row > 0 else { return nil }
            return (Int(windowSize.ws_col), Int(windowSize.ws_row))
        #endif
    }

    /// An environment variable of the process's as a terminal dimension. By `getenv`,
    /// which walks the environment, where `ProcessInfo` would build a dictionary of
    /// all of it: this runs on every frame.
    func terminalDimension(fromEnvironment name: String) -> Int? {
        #if os(Windows)
            environmentValue(name).flatMap(Self.terminalDimension)
        #else
            unsafe getenv(name).flatMap { unsafe Self.terminalDimension(String(cString: $0)) }
        #endif
    }

    /// An environment variable in `environment` as a terminal dimension, a question
    /// posed on a dictionary, as `ColorDepth.detect(environment:)` poses its own,
    /// without writing the one environment every thread reads.
    func terminalDimension(fromEnvironment name: String, in environment: [String: String]) -> Int? {
        environment[name].flatMap(Self.terminalDimension)
    }

    /// `raw` as a terminal dimension, accepting only a positive count; `nil` when
    /// unparseable or non-positive.
    ///
    /// Validated, not just parsed: `COLUMNS` / `LINES` are ordinary environment
    /// variables that anything may set, and `Int("0")` succeeds, so an unvalidated
    /// parse hands back a 0-row terminal. Only a positive value is a size; anything
    /// else leaves the axis to the terminal, and then to the 80x24 default.
    private static func terminalDimension(_ raw: String) -> Int? {
        guard let value = Int(raw), value > 0 else { return nil }
        return value
    }

    /// The terminal cell's height-to-width ratio, derived from the window's
    /// reported pixel size, or `nil` when the terminal doesn't report it.
    ///
    /// `TIOCGWINSZ` also carries the drawable area in pixels (`ws_xpixel`,
    /// `ws_ypixel`); dividing by the cell grid gives each cell's pixel size, and
    /// their ratio is the aspect an undistorted image needs (see
    /// ``View/imageCellAspect(_:)``). Not every terminal fills these fields —
    /// some report `0` — in which case this returns `nil` and callers keep their
    /// default. This self-corrects for the terminal + font + line spacing on the
    /// terminals that do report it, without any escape-sequence round trip.
    func cellPixelAspect() -> Double? {
        #if canImport(WASILibc)
            // The pixel fields ride on the same `ioctl` the size does, so this
            // is unavailable for the same reason; callers keep their default
            // aspect, which is what they do on the terminals that report zero.
            return nil
        #elseif os(Windows)
            // The classic console's cell (`cellPixelSize()`), so a font
            // narrower than Consolas (Cascadia Mono) keeps a picture its shape;
            // elsewhere on Windows, the default.
            guard let cell = cellPixelSize(), cell.width > 0 else { return nil }
            let aspect = Double(cell.height) / Double(cell.width)
            return (aspect >= 1.0 && aspect <= 4.0) ? aspect : nil
        #else
        var windowSize = winsize()
        #if canImport(Glibc) || canImport(Musl)
            let result = unsafe ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &windowSize)
        #else
            let result = unsafe ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize)
        #endif
        guard result == 0,
            windowSize.ws_col > 0, windowSize.ws_row > 0,
            windowSize.ws_xpixel > 0, windowSize.ws_ypixel > 0
        else { return nil }

        let cellWidth = Double(windowSize.ws_xpixel) / Double(windowSize.ws_col)
        let cellHeight = Double(windowSize.ws_ypixel) / Double(windowSize.ws_row)
        guard cellWidth > 0 else { return nil }
        let aspect = cellHeight / cellWidth
        // Guard against nonsense (a cell that's wider than tall, or absurdly
        // tall) so a misreporting terminal can't distort worse than the default.
        return (aspect >= 1.0 && aspect <= 4.0) ? aspect : nil
        #endif
    }
}
