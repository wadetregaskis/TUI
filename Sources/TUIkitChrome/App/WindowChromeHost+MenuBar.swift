//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowChromeHost+MenuBar.swift
//
//  The window's menu bar, as the chrome host draws it: the view the scene's
//  commands make, in the window's top row.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension _WindowChromeHost {
    /// The menu bar `bar` draws, in its row, on the bars' background — with the
    /// open menu's layers on it, for the caller to composite over the whole
    /// window.
    ///
    /// Drawn in a context of its own under the window's identity, a row high
    /// and the window wide, whose overlays may take every row below the bar: a
    /// menu hangs over the top bar and the page alike. While a modal holds the
    /// input it is drawn inert, as the top bar is — on throwaway focus, key and
    /// shortcut channels — so no menu opens and no command's key fires from
    /// behind the modal.
    func menuBarBuffer(
        _ bar: AnyView, width: Int, height: Int, isModal: Bool, context: RenderContext
    ) -> FrameBuffer {
        var barContext = context.withChildIdentity(type: MenuBarSlot.self, index: 0)
        barContext.availableWidth = width
        barContext.availableHeight = 1
        barContext.hasExplicitWidth = true
        barContext.hasExplicitHeight = true
        barContext.environment.overlayContentHeight = max(0, height - 1)
        if isModal { barContext = barContext.isolatedForBackground() }
        let palette = context.environment.palette
        let backgrounds = RenderBackgroundCodes(palette: palette)
        return TUIkitView.renderToBuffer(bar, context: barContext)
            .clamped(toWidth: width, height: 1)
            .resolvingOpacity(surface: palette.appHeaderBackground, palette: palette)
            .groundedAsChrome(width: width, background: backgrounds.appHeader)
    }
}

/// The menu bar's place among the window's children: what its identity is
/// keyed by, apart from the content's and the toolbars'.
private enum MenuBarSlot {}
