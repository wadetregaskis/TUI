//  🖥️ TUI — A Terminal UI framework for Swift
//  FormComposition.swift
//
//  What a `Form` reads from its content and measures before it can lay out a
//  column, kept for the pass at its place and width
//  (`RenderCache.composedOncePerPass(for:context:_:)`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// A form's rows, its label column and its content width, read and measured
/// once a pass at one place and width, and the columns built from them.
///
/// A grouped form in a scroll view was asked for its column three times a
/// frame — the scroll view's measure of its content, the stack's measure of
/// the form, and the draw — and read its content and measured every row each
/// time: on `app-shapes/grouped-form` (1,000 rows) that was 158,735 measures
/// stored a frame, every one a value the measure memo then kept to the end of
/// the pass. Kept, the second and third asks take the first's rows, and its
/// column: the same values, which the memo has already measured.
@MainActor
final class _FormComposition {
    let elements: [_FormElement]
    let pillar: Int
    let contentWidth: Int
    /// The version of what the read of the rows read, which the rows a loop
    /// made are memoised under (``_FormWalkVersion``); `nil` where nothing
    /// is memoised.
    let walk: _FormWalkVersion?
    /// The column built from them, by whether it fills the width it is laid
    /// out at (a grouped form drawn or proposed a width) or hugs its rows.
    var columns: [Bool: AnyView] = [:]

    init(elements: [_FormElement], pillar: Int, contentWidth: Int, walk: _FormWalkVersion?) {
        self.elements = elements
        self.pillar = pillar
        self.contentWidth = contentWidth
        self.walk = walk
    }
}
