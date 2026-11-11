//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalSymbols+ASCII.swift
//
//  The framework's own glyphs in ASCII, for a terminal that is sent plain text
//  (`TUI_PLAIN_TEXT`): one table, so a radio button, a box's corner and a
//  bracket each have one deliberate ASCII form, rather than whatever a site or
//  the folding at output happened to make of it. See
//  `Documentation/Historical/Text, editing and the clipboard/ASCII transliteration before layout.md`.
//
//  Created by Wade Tregaskis
//  License: MIT

extension TerminalSymbols {
    /// The ASCII forms of the framework's glyphs.
    ///
    /// Two kinds:
    /// - **Forms chosen where the glyph is drawn**, wider than the glyph they
    ///   stand for, so the view lays out around them, or a glyph whose meaning
    ///   there differs from its shape: a radio button's `(*)` for its one-cell
    ///   `●`, a control's `[ ]` for its half-block ends. A view reads them
    ///   where it would read the glyph, when its context spells text in ASCII
    ///   (`TextSpelling.isASCII`). A
    ///   toggle's `[x]` is ``ToggleCharacterSet``'s own `.ascii`, and a
    ///   spinner's frames are its style's: each is chosen at the point that
    ///   already chooses those glyphs.
    /// - **One character for one**, ``spelling(of:)``: the lines, blocks,
    ///   arrows, brackets and marks the framework draws, as what they look
    ///   like. The folding at output writes each in the cells its glyph was
    ///   laid out in, and the transliteration before layout writes the same,
    ///   so a `▶` is `>` in a `Text` and in a stepper alike.
    package enum ASCII {
        /// A selected (or focused) radio button: `(*)`, where the glyph is `●`.
        ///
        /// Three cells, where `●` is one: the parentheses are what say "one of
        /// these", as `[ ]` says "any of these", and the star says which
        /// without colour.
        package static let radioSelected = "(*)"

        /// An unselected radio button: `( )`, where the glyph is `◯`.
        package static let radioUnselected = "( )"

        /// A disabled, unselected radio button: `( )`, as an enabled one. The
        /// dotted `◌` has no ASCII shape that would not read as a mark (`(.)`,
        /// `(-)`), so a disabled option says so by its dimmed colour alone, as
        /// its label does.
        package static let radioDisabledUnselected = "( )"

        /// A control's opening end, `[`, where the glyph is the half block
        /// ``TerminalSymbols/openCap`` (`▐`): a button's, a text field's, a
        /// segmented picker's or a tab chip's.
        ///
        /// Chosen where the ends are drawn, not by the folding: there `▐` is a
        /// block, `#`, as it must be in a Canvas or a picture, and a control
        /// walled in `#` does not read as one.
        package static let openCap: Character = "["

        /// A control's closing end, `]`, where the glyph is
        /// ``TerminalSymbols/closeCap`` (`▌`).
        package static let closeCap: Character = "]"

        /// A shape's rounded opening end, `(`, where the glyph is the half
        /// block ``TerminalSymbols/openCap`` (`▐`) that a one-row `Capsule` or
        /// `RoundedRectangle` fill ends in: a tag's,
        /// `.background(.blue, in: Capsule())`.
        ///
        /// Chosen where the shape draws it, as ``openCap`` is (CAPSULE-TAG): a
        /// parenthesis, as a one-row rounded stroke of the same shape ends, so
        /// a rounded end reads alike filled or stroked, and a tag does not read
        /// as a button. A shape two rows tall or more is a picture, and its
        /// quadrant corners are left to the folding, `#`.
        package static let roundOpenCap: Character = "("

        /// A shape's rounded closing end, `)`, where the glyph is
        /// ``TerminalSymbols/closeCap`` (`▌`).
        package static let roundCloseCap: Character = ")"

        /// `scalar` as ASCII in the cells it takes, or `nil` where the
        /// framework draws nothing like it.
        package static func spelling(of scalar: Unicode.Scalar) -> String? {
            if let spelled = shapes[scalar] { return spelled }
            switch scalar.value {
            case 0x2500...0x257F: return "+"  // the lines of `shapes`, and then the light and double corners
            case 0x2580...0x259F, 0x25A0...0x25A9: return "#"  // blocks, shades and squares
            case 0x2800...0x28FF: return braille(dots: scalar.value - 0x2800)
            default: return nil
            }
        }

        /// A Braille cell as what its dots look like from across the room:
        /// a blank one blank, dots only in its upper half `'`, only in its
        /// lower half `.`, in both `:`, and six dots or more `#`.
        ///
        /// By where the dots are, because that is what a Braille border, a
        /// dotted button face and a Braille picture all draw with: a dotted
        /// box's top edge is dots at the head of its cells and its bottom
        /// dots at their foot, so it reads `'''` above and `...` below,
        /// between walls of `:`. Every cell was `.`, a blank one too, so a
        /// Braille picture's empty sky was dots from end to end.
        private static func braille(dots: UInt32) -> String {
            // Unicode numbers a cell's dots down its left column and then its
            // right, and gives the bottom row the last two bits: the upper
            // half (rows 0 and 1) is 0x01, 0x02, 0x08 and 0x10.
            let upper: UInt32 = dots & 0x1B
            let lower: UInt32 = dots & 0xE4
            switch (upper != 0, lower != 0) {
            case (false, false): return " "
            case (true, false): return "'"
            case (false, true): return "."
            case (true, true): return dots.nonzeroBitCount >= 6 ? "#" : ":"
            }
        }

        private static let shapes: [Unicode.Scalar: String] = {
            var table: [Unicode.Scalar: String] = [:]
            for (spelled, scalars) in [
                // A line by its weight. Along, a light one `-` and a heavy or
                // a double one `=`, so a box in `.heavy` or `.doubleLine` is
                // not a box in `.line`. Down, a light or a double one `|`, one
                // column having no room for two lines, and a heavy one `#`, as
                // are its corners and junctions: `+=====+` is a double box's
                // top and `#=====#` a heavy one's. A dashed line down `:`, the
                // dots it looks like; a dashed line along has no one-cell
                // form but its weight's.
                ("-", "─╌┄┈╴╶╼╾‐‑‒–—―"), ("=", "━═╍┅┉╸╺"), ("|", "│║╵╷╽╿"), ("#", "┃╹╻┏┓┗┛┣┫┳┻╋"),
                (":", "╎╏┆┇┊┋"), ("/", "╱"), ("\\", "╲"), ("X", "╳"),
                // A rounded corner as an ASCII box rounds one: `.----.` above
                // and `'----'` below.
                (".", "╭╮"), ("'", "╰╯"),
                // The corner triangles by their long side: the barber pole's
                // stripes `◢◤` are `//`, a scrollbar's arrows `◢◣` and `◥◤`
                // a peak `/\` and a valley `\/`. They were blank.
                ("/", "◢◤"), ("\\", "◣◥"),
                ("<", "←◀◂◄‹«"), (">", "→▶▸►›»"), ("^", "↑▲△▴↰↱"), ("v", "↓▼▽▾"),
                ("\\", "↖↘"), ("/", "↗↙"),
                // The moon by its lit side, as the `.moon` spinner's ASCII
                // frames have it.
                ("C", "☾"), ("D", "☽"),
                // Control as terminals write it, `^Q`, for what is drawn without
                // being spelled before layout, where the other modifiers are
                // their names: one cell has no room for those.
                ("^", "⌃"),
                ("o", "●○◉◎◦◯◌"), ("*", "•∙★☆✱"), (".", "·"), ("x", "✓✔✗✘"),
                // Not the half blocks `▐ ▌`, which are `#` as every block is: a
                // half block is a shape, which a Canvas cell, a picture's glyph
                // and a track's fill are drawn in too. A control whose ends they
                // are draws its own brackets where it draws them (``openCap``).
                // Brackets, as an app or a button's `.brackets` shape draws
                // them: their ASCII counterparts, where `Latin-ASCII` has none.
                ("(", "❨❪⦅⸨"), (")", "❩❫⦆⸩"), ("<", "⟨〈❬❮⦉⟪⦑"), (">", "⟩〉❭❯⦊⟫⦒"),
                ("[", "⟦⦇❲⌜⌞⌈⌊⁅"), ("]", "⟧⦈❳⌟⌝⌉⌋⁆"), ("{", "❴"), ("}", "❵"),
                // The one-eighth blocks, a thin line at a cell's edge: the
                // brackets an app draws a compact control's ends in.
                ("|", "▏▕"),
                // The shades lightest first, so a track of `░` under a fill of
                // `█` reads as one, `#####.....`, where both were `#`.
                (".", "░"), (":", "▒"),
                // The marks of a toast's style and an alert's title, emoji two
                // cells wide, so each has room for its spelling; ⚠ and ℹ by their
                // base, the selector after it being part of the same character.
                ("!", "⚠"), ("i", "ℹ"), ("ok", "✅"), ("X", "❌🛑"),
            ] as [(String, String)] {
                for scalar in scalars.unicodeScalars { table[scalar] = spelled }
            }
            return table
        }()
    }
}
