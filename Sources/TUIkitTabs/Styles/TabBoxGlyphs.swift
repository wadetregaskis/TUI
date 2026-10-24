//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabBoxGlyphs.swift
//
//  The glyphs a bordered TabView's folder tabs and content box are drawn in:
//  the border style of the appearance in force, as any box's are.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// The glyphs a `.bordered` ``TabView`` draws its folder tabs and its content
/// box in, from the ``BorderStyle`` of the ``Appearance`` in force — rounded
/// by default, as a box's border is, and square, heavy, double, Braille dots,
/// solid blocks or nothing under the others (owner, 2026-10-24: "TabView
/// borders should reflect the active border style").
///
/// A border style names its four corners, its edges and its walls; the folder
/// tabs need two junctions more, where a wall between two tabs meets the line
/// above it (`┬`) or the box's top below it (`┴`). Those are the style's own
/// where it is one of the line families TUIkit ships, the union of the two
/// lines' dots under Braille, and the corner otherwise — a block's `█`, a
/// blank border's space, an app's own style's corner glyph.
struct TabBoxGlyphs: Equatable {
    let topLeft: Character
    let topRight: Character
    let bottomLeft: Character
    let bottomRight: Character
    /// The top of a tab, and the content box's top.
    let horizontal: Character
    /// The content box's bottom.
    let bottomHorizontal: Character
    /// A wall: every tab's, and the box's left.
    let wall: Character
    /// The box's right wall, and the last tab's.
    let rightWall: Character
    /// Where a wall between two tabs meets the line over them: `┬`.
    let teeDown: Character
    /// Where a wall between two tabs meets the box's top under them: `┴`.
    let teeUp: Character
    /// Whether a glyph paints its cell in the border's colour too
    /// (``BorderStyle/paintsBackground``): `.block`'s.
    let paintsBackground: Bool
    /// Whether the style is drawn in Braille dots, whose junctions are the
    /// union of the dots that meet there.
    private let isBraille: Bool

    init(_ style: BorderStyle) {
        topLeft = style.topLeft
        topRight = style.topRight
        bottomLeft = style.bottomLeft
        bottomRight = style.bottomRight
        horizontal = style.horizontal
        bottomHorizontal = style.bottomHorizontal
        wall = style.vertical
        rightWall = style.rightVertical
        paintsBackground = style.paintsBackground
        isBraille = style.brailleThickness != nil
        switch (style.horizontal, style.vertical) {
        case ("─", "│"): (teeDown, teeUp) = ("┬", "┴")
        case ("━", "┃"): (teeDown, teeUp) = ("┳", "┻")
        case ("═", "║"): (teeDown, teeUp) = ("╦", "╩")
        default:
            teeDown = Self.union(style.horizontal, style.vertical) ?? style.topLeft
            teeUp = Self.union(style.horizontal, style.vertical) ?? style.bottomLeft
        }
    }

    /// The field a glyph paints under itself in `border`: the border's own
    /// colour under a style that paints its cells, nothing otherwise.
    func field(_ border: Color) -> Color? { paintsBackground ? border : nil }

    /// The glyph where `wall` meets a top edge inside the box — a tab's wall
    /// the line over the tabs, or the box's top under them: `line` for a
    /// border of lines, the corner or junction the caller names, and under
    /// Braille the two sets of dots together, so the wall's column of dots
    /// runs into the edge whichever side of its cell it is on.
    func meeting(_ wall: Character, _ line: Character) -> Character {
        guard isBraille else { return line }
        return Self.union(horizontal, wall) ?? line
    }

    /// Two Braille glyphs' dots in one, or `nil` where either is not Braille.
    private static func union(_ a: Character, _ b: Character) -> Character? {
        guard let x = a.unicodeScalars.first?.value, let y = b.unicodeScalars.first?.value,
            (0x2800...0x28FF).contains(x), (0x2800...0x28FF).contains(y)
        else { return nil }
        return Unicode.Scalar(0x2800 | (x - 0x2800) | (y - 0x2800)).map(Character.init)
    }
}
