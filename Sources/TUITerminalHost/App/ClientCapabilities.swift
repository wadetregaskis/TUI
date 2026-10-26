//  🖥️ TUI — A Terminal UI framework for Swift
//  ClientCapabilities.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The push-refreshed cache of what the terminal(s) in front of the user can
/// render — the emoji chrome, and skin-tone clusters (see
/// ``ClientCapabilities``).
///
/// Off tmux the answer is a process-lifetime constant: it is resolved once and
/// never re-asked. Under tmux it can change while the app runs — a client
/// detaches, a different terminal attaches, possibly at the same size (which
/// sends no SIGWINCH of its own) — so at startup the app registers tmux hooks
/// that push a SIGWINCH on any client change
/// (``TerminalHost/installTmuxClientChangeHooks()``), and the SIGWINCH path
/// calls ``refresh()``.
///
/// ``refresh()`` is ASYNCHRONOUS: the probe (a bounded `fork`/`exec`, see
/// ``TerminalHost/probeTmuxClients()``) runs off the main actor while frames
/// keep rendering with the previous answer; when the result lands and differs,
/// `onChange` runs — the owner invalidates the whole screen and requests a
/// render, so the correction is proactive rather than waiting for the next
/// keypress. In steady state — no client changes, no resizes — no subprocess
/// runs at all, ever.
///
/// Non-generic and separate from `RenderLoop` for two reasons: the coalescing
/// logic is unit-testable with an injected probe (no tmux server, no forks),
/// and a `Task.detached` inside the generic `RenderLoop<A>` would capture
/// `A.Type`, which is not `Sendable`.
/// One probe's answer — what the attached clients can render — plus whether
/// it might improve on a short retry.
///
/// Five capabilities, because they genuinely differ per terminal (measured):
/// - `emojiChrome`: all clients draw tmux's re-emission of the ⬛︎/⬜︎ VS-15
///   chrome correctly (Apple Terminal, iTerm2, Warp — NOT Ghostty, whose
///   native support depends on a compensation that cannot cross tmux).
/// - `skinTonesSafe`: all clients advance tmux's verbatim re-emission of
///   the tone clusters tmux itself merges (👍🏽 — the measured 70-base set,
///   `Character.tmuxMergedToneBases`) by the 2 cells tmux believes
///   (Ghostty ONLY — Apple Terminal and Warp advance 4, shearing the row,
///   and iTerm2 paints the tone as a broken separate swatch). When false,
///   the writer strips ALL modifiers at source; when true it still strips
///   the bases tmux detaches, which no client can repair — the strip, unlike
///   cursor compensation, survives the tmux hop: tmux's grid then holds and
///   re-emits the toneless cluster.
/// - `blockElementsFillTheLine`: every client draws Block Elements glyphs the
///   full height of the line (all but Terminal.app, which draws them from the
///   font, short of it — `TerminalHost.blockElementsFillTheLine`). When false,
///   a three-row button face is drawn without them.
/// - `cornerTrianglesFillTheCell`: every client draws the corner triangles
///   `◢ ◣ ◤ ◥` edge to edge (all but Terminal.app and Warp —
///   `TerminalHost.cornerTrianglesFillTheCell`). When false, a double-width
///   scrollbar's arrows are `▲▲` and `▼▼` rather than one triangle across both
///   cells.
/// - `drawsProgressBars`: every client has tmux's `progressbar` feature, so
///   tmux passes a pane's progress bar on to it (iTerm2's, by its XTVERSION
///   answer; not Ghostty's, Apple Terminal's or Warp's unless the user gives
///   it — measured, `progress_probe.py --tmux-forwarding`). When false, the
///   person sees no bar the app sends: `\.terminalFeatures.showsProgress` is
///   false, so the app draws its own. Off tmux nothing stands between the
///   app and the terminal, and this is `true`: whether that terminal draws a
///   bar is `TerminalClient.honoursProgressReports`'s question.
///
/// `mayImproveShortly` covers a measured race: the `client-attached` tmux hook
/// fires — and the app probes — before the new client's XTVERSION reply has
/// arrived, so the client is silent at that instant even when it is an iTerm2
/// that will name itself milliseconds later. A silent client the process walk
/// also can't identify is therefore worth a few bounded re-asks before the
/// safe answer is allowed to stand.
package struct ClientCapabilities: Equatable, Sendable {
    package let emojiChrome: Bool
    package let skinTonesSafe: Bool
    package let blockElementsFillTheLine: Bool
    package let cornerTrianglesFillTheCell: Bool
    package let drawsProgressBars: Bool
    package let mayImproveShortly: Bool

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and the run loop (TUIApp, since step B3) makes these values.
    package init(
        emojiChrome: Bool, skinTonesSafe: Bool, blockElementsFillTheLine: Bool, cornerTrianglesFillTheCell: Bool,
        drawsProgressBars: Bool, mayImproveShortly: Bool
    ) {
        self.emojiChrome = emojiChrome
        self.skinTonesSafe = skinTonesSafe
        self.blockElementsFillTheLine = blockElementsFillTheLine
        self.cornerTrianglesFillTheCell = cornerTrianglesFillTheCell
        self.drawsProgressBars = drawsProgressBars
        self.mayImproveShortly = mayImproveShortly
    }
}
