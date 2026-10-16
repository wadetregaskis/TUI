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
    ///
    /// - Returns: Whether the tooltip the bar shows changed the rows the bar
    ///   takes from the page: what ``publishHitTestRegions(_:tooltipMovedThePage:)``
    ///   is told.
    func resolveStatusBarTooltip(terminalWidth: Int, nowNanos: Int64, scheduler: AnimationScheduler?) -> Bool {
        let shownBefore = statusBarTooltipText
        let rowsBefore = statusBar.linesAboveItems.count
        fillStatusBarTooltipLines(
            width: windowChrome.style.barContentWidth(terminalWidth), nowNanos: nowNanos, scheduler: scheduler)
        return statusBarTooltipText != shownBefore && statusBar.linesAboveItems.count != rowsBefore
    }

    /// Publishes the frame's hit-test regions, which re-resolves the hover
    /// under a resting pointer (`MouseEventDispatcher.setRegions`), holding a
    /// hover tooltip through a reshape its own rows in the bar caused.
    ///
    /// The bar grows upwards for a tooltip, so a page laid out in the middle
    /// of the window moves as the tooltip comes or goes, and the view under
    /// the resting pointer slides out from under it. The dispatcher reports
    /// that as the pointer leaving; to the tooltip it is not
    /// (`TooltipState.held`, decisions-HELP A-HELP-1). Other hover observers
    /// and the controls hear the transitions as before: the pointer IS over
    /// something else now. On a page that fills the window the bar's rows
    /// cover the page's last rows instead of moving it, and a pointer resting
    /// on them rests on the tooltip's own bar, over the view it was on
    /// (`WindowChromeState.tooltipRows`).
    ///
    /// **A popover the reshape replaced.** The walk attached the popover of
    /// the candidate it found (`HelpModifier`); a reshape that slides another
    /// view with help under the resting pointer makes that one the candidate
    /// after the walk, with its delay still to serve. The frame drawn showed
    /// the old panel, and nothing asked for a frame before the new candidate's
    /// delay ran out, so the old panel stayed up for as long as the delay
    /// (decisions-HELP A-HELP-1, "Left open"). The next frame is asked for,
    /// as `requestTooltipFrames` asks for the bar's.
    ///
    /// - Parameters:
    ///   - tooltipMovedThePage: What
    ///     ``resolveStatusBarTooltip(terminalWidth:nowNanos:scheduler:)``
    ///     returned this frame.
    ///   - nowNanos: The frame's instant.
    ///   - scheduler: Where the next frame is asked for.
    func publishHitTestRegions(
        _ regions: [HitTestRegion], tooltipMovedThePage: Bool, nowNanos: Int64, scheduler: AnimationScheduler?
    ) {
        let tooltips = tuiContext.tooltipState
        let dispatcher = tuiContext.mouseEventDispatcher
        let popoverDrawn = Self.popoverText(tooltips.resolved(nowNanos: nowNanos))
        // What is presented over the page, which a hold on the rows the bar
        // covers stays with (`TooltipState.heldPresentations`).
        tooltips.beginReshape(
            movedByTooltip: tooltipMovedThePage, presentations: windowChrome.presentationsOverPage)
        if dispatcher.setRegions(regions) {
            // A held menu's highlight moved to the option the reshape put
            // under the pointer: the next frame draws it.
            scheduler?.requestWake("held-drag-reshape", at: nowNanos &+ 1)
        }
        let tooltipRows = windowChrome.tooltipRows
        let onTooltipRows = dispatcher.restingPointer.map { tooltipRows.contains($0.y) } ?? false
        tooltips.endReshape(pointerOnTooltipRows: onTooltipRows) { dispatcher.reachesHoverObserver($0) }
        guard Self.popoverText(tooltips.resolved(nowNanos: nowNanos)) != popoverDrawn else { return }
        // A wake an instant after this frame: the next frame the cap allows.
        scheduler?.requestWake("tooltip-popover", at: nowNanos &+ 1)
    }

    /// The text of `showing` when it is drawn as a popover, `nil` otherwise.
    private static func popoverText(_ showing: TooltipState.Resolved?) -> String? {
        showing?.style == .popover ? showing?.text : nil
    }

    /// Fills the status bar's rows above its items for this frame: the body
    /// of ``resolveStatusBarTooltip(terminalWidth:nowNanos:scheduler:)``.
    private func fillStatusBarTooltipLines(width: Int, nowNanos: Int64, scheduler: AnimationScheduler?) {
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

    /// Asks for the frames the tooltip owes once this one is drawn: called
    /// after the frame's hit-test regions are published, with its instant.
    ///
    /// **The end of a delay.** A view with help asks for the wake at the end
    /// of its delay as it draws (`HelpModifier`), which covers a pointer that
    /// arrived between frames. It does not cover a pointer the frame itself
    /// put a view under: publishing the regions re-resolves the hover under a
    /// resting pointer (`MouseEventDispatcher.setRegions`), so a reshape that
    /// slides a view with help under it makes that view the candidate after
    /// it has drawn, and nothing would wake when its delay ran out.
    ///
    /// **The next frame, when the walk changed the tooltip the status bar
    /// shows.** The bar is sized before the walk, from the candidate the last
    /// walk left (``resolveStatusBarTooltip(terminalWidth:nowNanos:scheduler:)``),
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
    func requestTooltipFrames(nowNanos: Int64, scheduler: AnimationScheduler?) {
        if let deadline = tuiContext.tooltipState.pendingDeadlineNanos(nowNanos: nowNanos) {
            scheduler?.requestWake("tooltip-delay", at: deadline)
        }
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
