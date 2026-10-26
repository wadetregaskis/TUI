//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowChromeHost+Stacking.swift
//
//  The window's rows stacked: the bars around the page, each on its own
//  background, with the menu bar's open menu over the whole.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension _WindowChromeHost {
    /// What each bar drew this walk, if anything.
    struct Bars {
        var menu: FrameBuffer?
        var top: FrameBuffer?
        var bottom: FrameBuffer?
        /// The background escape of the top bar's blank rows.
        var topBackground: String
        /// The background escape of the bottom bar's blank rows.
        var bottomBackground: String
    }

    /// The window: `bars` around `page`, each fitted to its rows on its own
    /// background — the menu bar, the top bar, the page and the bottom bar,
    /// top to bottom — with the menu bar's open menu composited over the
    /// whole of it: it hangs from its title in the bar's row, over the top bar
    /// and the page alike.
    func stacked(
        _ bars: Bars, around page: FrameBuffer, in rows: Rows, width: Int, height: Int,
        chrome: WindowChromeState, palette: any Palette
    ) -> FrameBuffer {
        let backgrounds = RenderBackgroundCodes(palette: palette)
        var frame = FrameBuffer()
        func append(_ bar: FrameBuffer?, rows: Int, background: String) {
            guard rows > 0 else { return }
            frame.appendVertically((bar ?? FrameBuffer()).fittedAsChrome(toRows: rows, width: width, background: background))
        }
        append(bars.menu, rows: rows.menu, background: backgrounds.appHeader)
        append(bars.top, rows: rows.top, background: bars.topBackground)
        frame.appendVertically(page)
        append(bars.bottom, rows: rows.bottom, background: bars.bottomBackground)
        if let layers = bars.menu?.overlays, !layers.isEmpty {
            chrome.presentationsOverPage += Self.presentations(in: layers)
            frame.overlays = layers
            frame = frame.compositingOverlays(maxWidth: width, maxHeight: height, palette: palette)
        }
        return frame
    }
}
