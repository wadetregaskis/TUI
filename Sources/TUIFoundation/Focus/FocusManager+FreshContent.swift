//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManager+FreshContent.swift
//
//  New content in a window's place, whose focus is chosen as a window's first
//  content's is. Beside `Focus.swift`, which is at its file-length limit.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Asks the end of this pass to choose the focus as it does for a window's
    /// first content, if the focused control has gone: the content's
    /// `.defaultFocus`, else its first control that takes the focus by itself
    /// (not a search field, ``AutomaticFocusDeclining``), as the manager's own
    /// choice — not the gone control's neighbour, which would be the first
    /// control of new content, whatever it is.
    ///
    /// For content that replaces a window's whole content, as a newly opened
    /// window's does on macOS: a document a `DocumentGroup` opens in place of
    /// the last one. A focus that is still there (outside the content
    /// replaced) is left alone.
    ///
    /// - Returns: `false`, doing nothing, on a backdrop's throwaway manager
    ///   (``isBackdrop``), whose pass is not the live page's.
    @discardableResult
    package func chooseFocusAfresh() -> Bool {
        guard !isBackdrop else { return false }
        choosesFocusAfresh = true
        return true
    }
}
