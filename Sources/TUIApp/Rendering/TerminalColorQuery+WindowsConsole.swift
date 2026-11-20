//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalColorQuery+WindowsConsole.swift
//
//  The classic Windows console's colours, which it does not report to the
//  colour queries but tells the program it runs: its colour table and the
//  attribute it draws with.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation
import TUIStyling

#if os(Windows)
import WinSDK
#endif

extension TerminalColorQuery {
    /// The ANSI slot each of the console's colour table's entries is: the
    /// console orders its sixteen by its attribute bits (blue 1, green 2, red
    /// 4, bright 8), ANSI by red 1, green 2, blue 4, bright 8, so the console's
    /// blue (1) is ANSI's slot 4 and its red (4) slot 1.
    static let consoleSlotOrder = [0, 4, 2, 6, 1, 5, 3, 7, 8, 12, 10, 14, 9, 13, 11, 15]

    /// What the classic console's own record says of its colours, as a report:
    /// the sixteen slots from its colour table, and the default foreground and
    /// background the table entries its attribute names (the attribute's low
    /// four bits and the four above them); `nil` for a table that is not
    /// sixteen entries.
    ///
    /// - Parameters:
    ///   - attributes: The screen buffer's `wAttributes`.
    ///   - table: Its `ColorTable`, each a `COLORREF` (`0x00BBGGRR`), in the
    ///     console's order.
    static func consoleReport(attributes: UInt16, table: [UInt32]) -> TerminalColorReport? {
        guard table.count == TerminalColorReport.slotCount else { return nil }
        func rgb(_ entry: UInt32) -> TerminalColors.RGB {
            TerminalColors.RGB(
                red: UInt8(entry & 0xFF), green: UInt8((entry >> 8) & 0xFF), blue: UInt8((entry >> 16) & 0xFF))
        }
        var report = TerminalColorReport()
        report.slots = consoleSlotOrder.map { rgb(table[$0]) }
        report.foreground = rgb(table[Int(attributes & 0x0F)])
        report.background = rgb(table[Int((attributes >> 4) & 0x0F)])
        return report
    }

    /// `report`, with what it left unsaid said by `console`: each default
    /// colour the terminal did not report, and the slots where it reported
    /// none of them. What the terminal reported stands.
    static func filling(_ report: TerminalColorReport, from console: TerminalColorReport) -> TerminalColorReport {
        var filled = report
        if filled.foreground == nil { filled.foreground = console.foreground }
        if filled.background == nil { filled.background = console.background }
        if filled.slots.allSatisfy({ $0 == nil }) { filled.slots = console.slots }
        return filled
    }

    /// `report`, filled from the classic Windows console's own record where
    /// the host is that console (``filling(_:from:)``); as it is everywhere
    /// else.
    @MainActor
    static func withClassicConsoleColors(_ report: TerminalColorReport) -> TerminalColorReport {
        #if os(Windows)
            guard TerminalHost.program == .windowsConsole, let console = classicConsoleReport() else { return report }
            return filling(report, from: console)
        #else
            return report
        #endif
    }

    #if os(Windows)
        /// The classic console's report of itself, from its screen buffer's
        /// record (`GetConsoleScreenBufferInfoEx`); `nil` where standard output
        /// is no console.
        ///
        /// Only the classic console's: it answers none of the colour queries,
        /// OSC 10, 11 and 4 alike (`osc_colour_probe.py`, conhost of build
        /// 26300, 2026-11-20), where Windows Terminal answers all of them. A
        /// pseudo console's record describes the pseudo console, not the
        /// terminal drawing it, so it is not asked there.
        static func classicConsoleReport() -> TerminalColorReport? {
            var info = CONSOLE_SCREEN_BUFFER_INFOEX()
            info.cbSize = ULONG(MemoryLayout<CONSOLE_SCREEN_BUFFER_INFOEX>.size)
            guard unsafe GetConsoleScreenBufferInfoEx(StandardHandle.output, &info) else { return nil }
            // A C array, imported as a tuple: read through a mirror, as
            // `ConsoleFont` reads its face name.
            let table = Mirror(reflecting: info.ColorTable).children.compactMap { $0.value as? COLORREF }
            return consoleReport(attributes: info.wAttributes, table: table.map { UInt32($0) })
        }
    #endif
}
