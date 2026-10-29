//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarPoof.swift
//
//  The puff of smoke a toolbar item dragged off the bar goes in, as on macOS:
//  a third of a second of small glyphs spreading from where it was let go,
//  drawn over the whole window.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The puff a customizable toolbar's item goes in when the person drags it
/// off the bar while customizing (``_ToolbarItemDrag``; the owner,
/// 2026-10-28, afternoon list #41).
///
/// Four frames of five sixtieths of a second each — a third of a second in
/// all — of a star that opens and scatters: one-cell glyphs of no ambiguous
/// width (ASCII, and the dingbats U+273B and U+273A, which have no emoji
/// form), in the palette's secondary foreground, each composited onto its own
/// cell so the window shows between them. Timed from the frame after the
/// release, which stamps ``ToolbarCustomizationGestures/Poof/startNanos``,
/// and woken for each next frame, so it plays without input; gone after the
/// last. Nothing at all is done while no puff is showing.
enum _ToolbarPoof {
    /// One glyph of a frame: its offset from the puff's centre, across and
    /// down, and the glyph.
    typealias Cell = (dx: Int, dy: Int, glyph: Character)

    /// The frames, in order.
    static let frames: [[Cell]] = [
        [(0, 0, "*")],
        [(0, 0, "\u{273B}"), (-1, 0, "."), (1, 0, "."), (0, -1, "."), (0, 1, "'")],
        [(0, 0, "\u{273A}"), (-2, 0, "."), (2, 0, "."), (-1, -1, "."), (1, -1, "."), (-1, 1, "'"), (1, 1, "'")],
        [(0, 0, "."), (-3, 0, "."), (3, 0, "."), (-2, -1, "."), (2, -1, "."), (-2, 1, "'"), (2, 1, "'")],
    ]

    /// How long each frame shows: five frames at 60 Hz.
    static let frameNanos: Int64 = 1_000_000_000 * 5 / 60

    /// The token of the wake that brings the next frame.
    static let wakeToken = "toolbar-customization-poof"

    /// Draws the frame of the puff showing, if one is, over `frame`, the
    /// stacked window, and asks for a wake at the next frame's time — or
    /// forgets the puff once its last frame is over.
    @MainActor
    static func draw(over frame: inout FrameBuffer, chrome: WindowChromeState, context: RenderContext) {
        let gestures = chrome.toolbarCustomization
        guard var poof = gestures.poof else { return }
        let now = context.environment.frameNowNanos
        let start = poof.startNanos ?? now
        poof.startNanos = start
        let index = Int(max(0, now - start) / frameNanos)
        guard index < frames.count else {
            gestures.poof = nil
            return
        }
        gestures.poof = poof
        context.requestWake(token: wakeToken, atNanos: start + Int64(index + 1) * frameNanos)
        let colour = context.environment.palette.foregroundSecondary.opaqueSpelling
        for cell in frames[index] {
            let (x, y) = (poof.x + cell.dx, poof.y + cell.dy)
            guard x >= 0, y >= 0, x < frame.width, y < frame.height else { continue }
            let glyph = ANSIRenderer.colorize(String(cell.glyph), foreground: colour)
            frame.composite(with: FrameBuffer(lines: [glyph]), at: (x, y))
        }
    }
}
