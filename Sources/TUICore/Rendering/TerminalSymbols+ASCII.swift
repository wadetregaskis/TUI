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

        /// `scalar` as ASCII in the cells it takes, or `nil` where the
        /// framework draws nothing like it.
        package static func spelling(of scalar: Unicode.Scalar) -> String? {
            if let spelled = shapes[scalar] { return spelled }
            switch scalar.value {
            case 0x2500...0x257F: return "+"  // the lines of `shapes`, and then the corners
            case 0x2580...0x259F, 0x25A0...0x25A9: return "#"  // blocks, shades and squares
            case 0x2800...0x28FF: return "."  // Braille
            default: return nil
            }
        }

        private static let shapes: [Unicode.Scalar: String] = {
            var table: [Unicode.Scalar: String] = [:]
            for (spelled, scalars) in [
                ("-", "─━═╌╍┄┅┈┉╴╶╸╺╼╾‐‑‒–—―"), ("|", "│┃║╎╏┆┇┊┋╵╷╹╻╽╿"), ("/", "╱"), ("\\", "╲"), ("X", "╳"),
                ("<", "←◀◂◄‹«"), (">", "→▶▸►›»"), ("^", "↑▲△▴"), ("v", "↓▼▽▾"),
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
