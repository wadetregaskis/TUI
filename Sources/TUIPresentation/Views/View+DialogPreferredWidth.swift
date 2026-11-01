//  🖥️ TUI — A Terminal UI framework for Swift
//  View+DialogPreferredWidth.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension View {
    /// Sets the width a dialog prefers for its body before it will use more of
    /// the screen.
    ///
    /// A dialog hugs its content, so this is a *ceiling on the comfortable
    /// width*, not a fixed size: content narrower than this is unaffected, and
    /// a dialog only ever grows past it when doing so genuinely fits more
    /// content vertically — a wrapped paragraph gets shorter as it gets wider,
    /// a fixed-width form does not, and the one that gains nothing stays slim.
    ///
    /// The default (100) suits prose. Raise it for a dialog built around a wide
    /// table, where a long line is the content rather than a readability
    /// problem:
    ///
    /// ```swift
    /// .modal(isPresented: $showing) {
    ///     Dialog("Report") { WideTable() }
    /// }
    /// .dialogPreferredWidth(160)
    /// ```
    ///
    /// This is a terminal-specific affordance — SwiftUI has no equivalent,
    /// because a desktop window is sized by the user — so it is a modifier
    /// rather than a `Dialog` initializer parameter.
    ///
    /// - Parameter width: The preferred body width in cells.
    /// - Returns: A view whose dialogs prefer that width.
    nonisolated public func dialogPreferredWidth(_ width: Int) -> some View {
        environment(\.dialogPreferredWidth, max(1, width))
    }
}
