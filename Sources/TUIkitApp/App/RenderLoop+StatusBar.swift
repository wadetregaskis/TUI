//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+StatusBar.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitChrome
import TUIkitFoundation

// MARK: - What the status bar shows besides its items

/// The rows a frame adds to the status bar above its items.
///
/// Separate from `RenderLoop.swift` because that file is at its length limit,
/// the bargain `RenderLoop+Scene.swift` makes too; it is why
/// `resolveStatusBarTooltip` is not private.
extension RenderLoop {
    /// Resolves this frame's tooltip into the status bar's rows — or, with no
    /// tooltip to show there, the line about the latest copy
    /// (``ClipboardWriter/statusNote(atNanos:)``) — or clears them.
    ///
    /// The rows are wrapped HERE rather than by the bar, because the bottom
    /// bar's rows are reserved before the content draws, and have to already
    /// know how many lines the text takes. Wrapped to `ChromeStyle.barContentWidth`,
    /// the one function the bordered renderer also lays its items out at.
    ///
    /// A popover-styled tooltip clears the rows: it is drawn by the content pass
    /// as an overlay and must not also spend a row of chrome. The style comes
    /// from the CANDIDATE, not from the root environment — `tooltipStyle` is a
    /// subtree setting, so a panel asking for a popover inside an app that uses
    /// the bar is answered by the panel.
    func resolveStatusBarTooltip(terminalWidth: Int, nowNanos: Int64, scheduler: AnimationScheduler?) {
        let width = windowChrome.style.barContentWidth(terminalWidth)
        statusBar.showsNoteInPlaceOfItems = false
        // Whether last frame's line of key hints drew a row of items for the
        // copy's line to stand in for; this frame's line records it afresh.
        let lineShowedItems = statusBar.lineShowsItems
        statusBar.lineShowsItems = false
        statusBarTooltipText = statusBarTooltip(nowNanos: nowNanos)
        if let text = statusBarTooltipText {
            statusBar.tooltipLines = TextWrapping.wrap(text, width: width)
            return
        }
        // The copy's line yields to a tooltip, which the user asked for, and
        // comes back if it is still fresh when the tooltip goes. It stands in
        // for the line of key hints' items rather than above them, where the
        // line drew some, so the page keeps its height
        // (``StatusBarState/showsNoteInPlaceOfItems``) — which holds only if
        // it is ONE row, so it is cut to the bar's width rather than wrapped:
        // at forty columns "Not copied: no clipboard reachable from here"
        // wrapped to two, and the second was a row taken from the page. It
        // asks for the frame that takes it away: nothing else would draw one.
        if let note = tuiContext.clipboardWriter.statusNote(atNanos: UInt64(bitPattern: nowNanos)) {
            statusBar.tooltipLines = [note.text.truncatedToWidth(width)]
            statusBar.showsNoteInPlaceOfItems = lineShowedItems
            scheduler?.requestWake("clipboard-note", at: Int64(bitPattern: note.expiresAtNanos))
            return
        }
        statusBar.tooltipLines = []
    }

    /// Asks for the next frame when the walk changed the tooltip the status
    /// bar shows: called once the frame is drawn, with the frame's instant.
    ///
    /// The bar is sized before the walk, from the candidate the last walk
    /// left (``resolveStatusBarTooltip(terminalWidth:nowNanos:scheduler:)``),
    /// and the focused control publishes its help during the walk. So a walk
    /// can leave a different answer from the one the bar was drawn with: the
    /// focus moved to a control whose help shows at once (`.onFocus` with no
    /// delay), help the reader revealed changed its text under the focus, or
    /// the focused control no longer carries help. Nothing else would draw
    /// the frame that shows it: a held focus may breathe by replaying the
    /// frame on screen rather than by rendering one, and a candidate due now
    /// has no deadline to wake for (`TooltipState.pendingDeadlineNanos`).
    ///
    /// The next frame, as the window's chrome adopts a change of its rows a
    /// frame later (`WindowChromeHost.settle`) rather than walking the scene a
    /// second time. That frame's bar is sized from what this walk left, and
    /// asks again only if its own walk changes the answer once more — which
    /// help text that differs on every walk, with nothing else changing,
    /// would do at the frame-rate cap for as long as it shows in the bar.
    func requestStatusBarTooltipAdoption(nowNanos: Int64, scheduler: AnimationScheduler?) {
        guard statusBarTooltip(nowNanos: nowNanos) != statusBarTooltipText else { return }
        // A wake an instant after this frame: the next frame the cap allows.
        scheduler?.requestWake("status-bar-tooltip", at: nowNanos &+ 1)
    }

    /// The text of the tooltip the status bar shows at `nowNanos`, `nil` when
    /// none shows there.
    private func statusBarTooltip(nowNanos: Int64) -> String? {
        guard let showing = tuiContext.tooltipState.resolved(nowNanos: nowNanos),
            showing.style == .statusBar
        else { return nil }
        return showing.text
    }
}
