//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+StatusBar.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - What the status bar shows besides its items

/// The rows a frame adds to the status bar above its items.
///
/// Separate from `RenderLoop.swift` because that file is at its length limit,
/// the bargain `RenderLoop+Scene.swift` makes too; it is why
/// `resolveStatusBarTooltip` is not private.
extension RenderLoop {
    /// Resolves this frame's tooltip into the status bar's rows, or clears them.
    ///
    /// The rows are wrapped HERE rather than by the bar, because the height the
    /// content area is given is `statusBar.height` and that has to already know
    /// how many lines the text takes. Wrapped to `ChromeStyle.barContentWidth`,
    /// the one function the bordered renderer also lays its items out at.
    ///
    /// A popover-styled tooltip clears the rows: it is drawn by the content pass
    /// as an overlay and must not also spend a row of chrome. The style comes
    /// from the CANDIDATE, not from the root environment — `tooltipStyle` is a
    /// subtree setting, so a panel asking for a popover inside an app that uses
    /// the bar is answered by the panel.
    func resolveStatusBarTooltip(terminalWidth: Int, nowNanos: Int64) {
        let tooltips = tuiContext.tooltipState
        guard
            let showing = tooltips.resolved(nowNanos: nowNanos),
            showing.style == .statusBar
        else {
            statusBar.tooltipLines = []
            return
        }
        statusBar.tooltipLines = TextWrapping.wrap(
            showing.text, width: statusBar.style.barContentWidth(terminalWidth))
    }
}
