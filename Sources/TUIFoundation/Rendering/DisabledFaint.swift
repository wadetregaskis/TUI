//  🖥️ TUI — A Terminal UI framework for Swift
//  DisabledFaint.swift
//
//  The faint a disabled control and a row that can't be selected are drawn in,
//  and the italic it brings with it where the host doesn't show faint.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling
import TUITerminalHost

extension TerminalClient {
    /// Whether faint (SGR 2) draws text visibly fainter than plain, in the
    /// terminal's own foreground as much as in a stated colour.
    ///
    /// Every host measured does but one: Warp with a light background, which
    /// darkens a faint run instead and leaves its default foreground (black)
    /// as it was, so a disabled control drawn faint at no colour looked like an
    /// enabled one (`faint_card.py`, 2026-11-07; the compatibility survey's
    /// faint table). Warp with a dark background is assumed to dim as asked,
    /// since darkening a light foreground is dimming it (inferred, not
    /// measured), and so is a Warp whose background is unknown: Warp answers
    /// OSC 11, so an unknown background there is rare, and the case the
    /// workaround is for is the one that has been seen.
    ///
    /// Decided for the session, not per cell: the host and its background are
    /// the same for every cell of a frame. A theme change the terminal reports
    /// moves `TerminalColors.current`, whose generation drops the render cache,
    /// so the next frame reads the new answer.
    ///
    /// Under tmux the host is tmux, which passes the attribute to whichever
    /// terminal it is drawn in, and the answer is `true`: tmux in Warp's light
    /// theme still loses the faint.
    @MainActor package static var drawsFaint: Bool {
        drawsFaintPin ?? drawsFaint(on: effective.program, prefersDark: TerminalColors.current.prefersDark)
    }

    /// ``drawsFaint`` for `program` with a background that is dark, light
    /// (`false`) or unknown (`nil`).
    package static func drawsFaint(on program: Program, prefersDark: Bool?) -> Bool {
        !(program == .warp && prefersDark == false)
    }

    /// A task-local answer for ``drawsFaint``, for tests, as
    /// ``drawsBold``'s pin is.
    @TaskLocal package static var drawsFaintPin: Bool?
}

extension ANSIRenderer {
    /// SGR 2 and 3 together: faint, and italic.
    private static let faintItalic = "\(csi)2;3m"

    /// Wraps a string in the faint that says "disabled", restated after every
    /// reset in it, as ``applyPersistentDim(_:)`` does: italic too where the
    /// terminal doesn't draw faint (``TerminalClient/drawsFaint``), so that a
    /// disabled control still looks like one there.
    ///
    /// Italic because Warp, the host that needs it, draws it as asked in the
    /// same theme, and because it changes no cell and no colour: the control's
    /// look is otherwise the one it has everywhere.
    ///
    /// - Parameter string: The text to draw disabled.
    /// - Returns: The string with the persistent attributes applied.
    @MainActor
    package static func applyPersistentDisabled(_ string: String) -> String {
        guard !TerminalClient.drawsFaint else { return applyPersistentDim(string) }
        return wrapping(string, restoring: faintItalic, opening: faintItalic, padding: 0, closing: reset) ?? string
    }
}
