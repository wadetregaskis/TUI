//  🖥️ TUI — A Terminal UI framework for Swift
//  Terminal+PixelMouse.swift
//
//  The terminal's side of ``PixelMouseNegotiation``: what it writes, and asks.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation
import TUITerminalHost

extension Terminal {
    /// One frame's view of whether anything wants the pointer's place within a
    /// cell. An app that never does pays one comparison a frame.
    func updatePixelMouse(wanted: Bool, tracking: Bool) {
        guard wanted || pixelMouse.holdsPixels else { return }
        let write = pixelMouse.update(
            wanted: wanted, tracking: tracking, grid: windowGrid(), cellReading: cellPixelSize(),
            host: PixelMouseNegotiation.Host.of(
                program: TerminalHost.program, environment: ProcessInfo.processInfo.environment))
        if !write.isEmpty { writeImmediate(write) }
    }

    /// A report in pixels as an event in whole cells, or nothing if it proved the
    /// cell size wrong.
    func convertPixelReport(_ report: MouseEvent) -> TerminalInput? {
        let converted = pixelMouse.convert(report)
        if !converted.write.isEmpty { writeImmediate(converted.write) }
        return converted.event.map(TerminalInput.mouse)
    }
}
