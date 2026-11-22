//  🖥️ TUI — A Terminal UI framework for Swift
//  ConsoleWindow.swift
//
//  The classic Windows console's window: the size of its cell in the pixels
//  it draws, and how many of those make a point at its display's scale.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import TUIFoundation
import WinSDK

/// The window the classic Windows console (conhost) draws in, which a program
/// in the console can measure, as it cannot measure a terminal's.
///
/// The console's font size (``ConsoleFont/cellSize()``) is its cell at 96 dots
/// an inch, whatever the display's scale. Measured 2026-11-20, build 26300, at
/// 200%: Consolas names 8 × 16, and its window draws 120 × 30 cells in 1800 ×
/// 960 pixels at 192 dots an inch, a cell of 15 × 32, which is 7.5 × 16 points.
/// So the cell is taken from the window, in its pixels, and the window's dots
/// an inch over 96 is how many of them make a point.
enum ConsoleWindow {
    /// The console's cell in its window's pixels, and how many of those make a
    /// point: `nil` where standard output is no classic console. A pseudo
    /// console (Windows Terminal's, an ssh server's) has a window of no size
    /// and names a font of no width, so it is none.
    ///
    /// Where the window can't be measured (it is minimized, say), the font's
    /// cell at the window's scale; where it has no scale, the font's cell, in
    /// points.
    static func cell() -> (pixels: TerminalCellPixels, pixelsPerPoint: Double)? {
        guard let font = ConsoleFont.cellSize() else { return nil }
        guard let window = unsafe GetConsoleWindow() else { return (font, 1) }
        let dotsPerInch = unsafe GetDpiForWindow(window)
        guard dotsPerInch > 0 else { return (font, 1) }
        let scale = Double(dotsPerInch) / Double(USER_DEFAULT_SCREEN_DPI)
        if let area = unsafe clientSize(of: window), let grid = StandardHandle.windowSize(),
            area.width >= grid.width, area.height >= grid.height
        {
            // A maximised window may be part of a cell wider than its grid:
            // whole division leaves that part out.
            return (TerminalCellPixels(width: area.width / grid.width, height: area.height / grid.height), scale)
        }
        let scaled = TerminalCellPixels(
            width: Int(clamping: (Double(font.width) * scale).rounded()),
            height: Int(clamping: (Double(font.height) * scale).rounded()))
        return (scaled, scale)
    }

    /// The size of `window`'s client area in the pixels its display has, or
    /// `nil` where it has none (it is minimized). Asked as a thread aware of
    /// each display's scale, so the answer is not scaled to 96 dots an inch,
    /// and the thread is put back as it was.
    private static func clientSize(of window: HWND) -> (width: Int, height: Int)? {
        // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2, a macro Swift doesn't
        // import: `((DPI_AWARENESS_CONTEXT)-4)`.
        let previous = unsafe SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4))
        defer { if let previous = unsafe previous { _ = unsafe SetThreadDpiAwarenessContext(previous) } }
        var rect = RECT()
        guard unsafe GetClientRect(window, &rect) else { return nil }
        let width = Int(rect.right - rect.left)
        let height = Int(rect.bottom - rect.top)
        return width > 0 && height > 0 ? (width, height) : nil
    }
}

#endif
