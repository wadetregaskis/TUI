//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FieldTextLayout.swift
//
//  How field text draws a selection: the look the text inputs give their
//  selected cells, which the screen's own selection borrows.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The protocol

/// Drawing the text of a field, as far as the substrate shares it: what a
/// selection over it looks like (``selectionColors(palette:background:ink:)``).
///
/// Adopted by the text inputs' renderer (`TextFieldContentRenderer`), which
/// draws a field's selected cells in these colours, and by ``ScreenSelection``,
/// which highlights a drag over the page in the same ones, so the two read as
/// one kind of selection. The substrate declares it and implements the colours
/// once, here: the screen's selection is the substrate's, and the text inputs
/// sit above it once TUIkit is split into modules, so it must not name their
/// renderer to borrow the look.
package protocol FieldTextLayout {}

extension FieldTextLayout {
    /// The selection highlight's background and the text colour that reads on
    /// it.
    ///
    /// A blend needs something concrete to blend TOWARD, and a `.plain` field
    /// has no surface to name — so the palette's background stands in. The
    /// selection is an opaque highlight either way; this only decides its
    /// exact tint.
    ///
    /// Where the accent or that ground has no RGB there is no tint to draw at all:
    /// every share of such a blend is one end or the other, so 60% of the accent is
    /// either a solid accent under text nobody can check for contrast or the ground
    /// itself, which shows nothing (`Documentation/Colour and styling/Opacity as composition.md` §75,
    /// §87). The cell's own pair is exchanged instead — reverse video is the one
    /// highlight a terminal paints legibly whatever colours it keeps — and, since it is
    /// the CELL that is reversed, the ink is the field's own, a `.textFieldTextStyle`
    /// override included, rather than the palette's. Both sides are stated opaque, as
    /// every reversal is, so a reversed cell claims nothing.
    ///
    /// - Parameter ink: What the field draws its text in, for the reversed case.
    ///   Defaults to the palette's foreground, for a caller with no cell in hand.
    package static func selectionColors(
        palette: any Palette, background: Color?, ink: Color? = nil
    ) -> FieldSelectionStyle {
        let ground = background ?? palette.background
        let selection = palette.accent.opacity(ViewConstants.selectionIndicator, over: ground)
        guard palette.highlightFill(selection, over: ground, tint: palette.accent).isReversed
        else {
            return FieldSelectionStyle(
                background: selection, foreground: palette.readableText(on: selection),
                isReversed: false)
        }
        return FieldSelectionStyle(
            background: ground.opaqueSpelling,
            foreground: (ink ?? palette.foreground).opaqueSpelling, isReversed: true)
    }
}

// MARK: - What a selected cell paints

/// What a selected cell paints: the highlight's own pair, or — where that
/// highlight cannot be measured — the cell's pair, exchanged by reverse video.
package struct FieldSelectionStyle {
    /// The colour the selected cells are filled with. Reversed, the colour the
    /// terminal exchanges INTO them, which is the field the cell already had.
    package let background: Color

    /// The colour the selected text is drawn in. Reversed, the cell's own ink.
    package let foreground: Color

    /// Whether the pair is stated beside an SGR 7 rather than painted directly.
    package let isReversed: Bool

    /// Every colour resolved against `palette`. A custom palette may state a role
    /// semantically, and ``RunAccumulator`` hands its colours to ``ANSIRenderer``
    /// as they are, which traps on `.semantic`.
    package func resolved(with palette: any Palette) -> Self {
        Self(
            background: background.resolve(with: palette),
            foreground: foreground.resolve(with: palette), isReversed: isReversed)
    }
}
