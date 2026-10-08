//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SheetDetentHeight.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Carrying the resolved height to the sheet's box

/// The height a detented sheet's outermost *container* must render at, or `nil`
/// when the sheet is not detented.
private struct SheetDetentHeightKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The height the presented sheet's box must take, set by the modal host
    /// when the content named a detent, or a ``PresentationSizing`` that
    /// proposes a height (its width twin is ``sheetProposedWidth``).
    ///
    /// A detent is a height for the *sheet*, and in SwiftUI the sheet is a card
    /// with its own material, so the height is always something you can see. A
    /// terminal sheet has no material of its own — the presented content **is**
    /// the sheet — so the height has to reach the content's own box, which is
    /// what this value does: the outermost container (``Dialog``, ``Panel``,
    /// ``Card``, `.border()`) renders exactly this tall and encloses the
    /// leftover as empty interior.
    ///
    /// Consumed by that outermost container, which clears it for its children
    /// — the same one-shot discipline `focusIndicator` follows, and for the
    /// same reason: a `Panel` nested inside a detented `Dialog` must not also
    /// stretch to the sheet's height. Boxes side by side under it each take
    /// it, flexibly, so a `VStack` or `HStack` of them shares it as it shares
    /// any surplus. A `ScrollView` consumes it along the axes it scrolls, so
    /// the boxes in one are their content's size there (a vertical one still
    /// passes the sheet's width on); a `ZStack`, a `Grid` and a lazy stack or
    /// lazy grid outside a scroll view pass it on, and each box below takes
    /// the whole of it.
    ///
    /// Content with no box (a bare `Text`) has nothing to stretch, so it keeps
    /// its own size. The alternative — padding the presented buffer out to the
    /// detent — is what this replaced: those rows were blank, unstyled and
    /// *opaque*, so they punched a hole through the dialog's page rather than
    /// belonging to anything.
    var sheetDetentHeight: Int? {
        get { self[SheetDetentHeightKey.self] }
        set { self[SheetDetentHeightKey.self] = newValue }
    }
}
