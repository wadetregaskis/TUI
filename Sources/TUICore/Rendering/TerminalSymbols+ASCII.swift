//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalSymbols+ASCII.swift
//
//  The framework's own glyphs in ASCII, for a terminal that is sent plain text
//  (`TUI_PLAIN_TEXT`): one table, beside the glyphs, for the folding at output
//  and whatever else spells them. See
//  `Documentation/Historical/Text, editing and the clipboard/ASCII transliteration before layout.md`.
//
//  Created by Wade Tregaskis
//  License: MIT

extension TerminalSymbols {
    /// The ASCII forms of the framework's glyphs: the lines, blocks,
    /// arrows and marks it draws, one character for one, as what they look
    /// like (``spelling(of:)``), which the folding at output writes in the
    /// cells each glyph was laid out in.
    package enum ASCII {
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
                ("o", "●○◉◎◦"), ("*", "•∙★☆✱"), (".", "·"), ("x", "✓✔✗✘"),
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
