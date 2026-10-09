//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderFrameValues.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitFoundation

/// The clock a frame is stamped with: an absolute monotonic reading, the
/// same one every call site uses.
///
/// `render(frameNowNanos:)` once defaulted this to `0`. The parameter is an
/// ABSOLUTE uptime, and the two callers that took the default — the frame
/// rendered before a Ctrl-Z suspend, and the debug frame dump — anchored
/// every drag flight and the auto-scroll timer at process-uptime zero; the
/// next real frame then measured a lift as having run for the whole uptime.
/// The default is the clock now, and the frame pacer reads the same one.
package enum FrameClock {
    package static var nowNanos: Int64 { Int64(bitPattern: MonotonicClock.nowNanoseconds) }

    /// The wall clock, read beside ``nowNanos`` wherever a frame is stamped: the
    /// one date a `TimelineView` resolves its schedule against in every walk of
    /// the frame, and the one its wake is counted from. See
    /// `RenderCache.frameDate`.
    package static var nowDate: Date { Date() }
}

/// ANSI background codes for each render surface in a frame.
///
/// Keeping these grouped avoids accidentally rendering every surface
/// with `palette.background` and ignoring palette-specific tokens like
/// `statusBarBackground`.
package struct RenderBackgroundCodes: Equatable {
    /// Main content area background code.
    package let content: String

    /// App header background code.
    let appHeader: String

    /// Status bar background code.
    let statusBar: String

    package init(palette: any Palette) {
        self.content = ANSIRenderer.backgroundCode(for: palette.background)
        self.appHeader = ANSIRenderer.backgroundCode(for: palette.appHeaderBackground)
        self.statusBar = ANSIRenderer.backgroundCode(for: palette.statusBarBackground)
    }
}

/// The height of the content area: whatever the terminal has left after the
/// chrome laid out around it (the window's top and bottom bars, if any).
///
/// **Never negative.** A terminal can be shorter than its own chrome — the
/// status bar and header are laid out first and keep their full height — which
/// makes the raw subtraction negative. A negative height is not a size: it
/// reached `WindowGroup.centerBuffer` and `FrameDiffWriter.buildOutputLines` as
/// `0..<negative` and trapped ("Range requires lowerBound <= upperBound"), so
/// the app died on launch in a short terminal rather than drawing a squeezed
/// frame. Zero means "no room": the content renders empty, the chrome still shows.
///
/// This exists as one function because the subtraction was open-coded at four
/// sites and only some of them clamped — fixing three of four just moved the
/// crash from `centerBuffer` to `FrameDiffWriter`. One definition, one clamp.
@inline(__always)
internal func contentAreaHeight(
    terminalHeight: Int, statusBarHeight: Int, headerHeight: Int = 0
) -> Int {
    max(0, terminalHeight - statusBarHeight - headerHeight)
}
