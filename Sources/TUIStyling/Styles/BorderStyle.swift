//  🖥️ TUI — A Terminal UI framework for Swift
//  BorderStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Defines the visual style of a border.
///
/// Each style provides characters for all border components:
/// corners, edges, and T-junctions for complex layouts.
public struct BorderStyle: Sendable, Hashable {
    /// Top-left corner character.
    public let topLeft: Character

    /// Top-right corner character.
    public let topRight: Character

    /// Bottom-left corner character.
    public let bottomLeft: Character

    /// Bottom-right corner character.
    public let bottomRight: Character

    /// Horizontal edge character: the top edge's, and a divider's.
    public let horizontal: Character

    /// Vertical edge character: the left wall's.
    public let vertical: Character

    /// The bottom edge's character — ``horizontal`` unless the style draws its
    /// bottom apart, as ``braille(thickness:)`` does, its dots sitting at the
    /// foot of the cell there and at its head along the top.
    public let bottomHorizontal: Character

    /// The right wall's character — ``vertical`` unless the style draws its
    /// right side apart, as ``braille(thickness:)`` does.
    public let rightVertical: Character

    /// How thick a dotted border's lines are, in Braille dots — `nil` for a
    /// border of glyphs. Read by a bordered button, which draws its face in
    /// the same dots (``ButtonBorderShape``).
    public let brailleThickness: Int?

    /// Left T-junction character (├).
    public let leftT: Character

    /// Right T-junction character (┤).
    public let rightT: Character

    /// Whether this style's glyphs are opaque — paint the cell in the border's
    /// colour as well as the glyph.
    ///
    /// A `Bool` and not a `Color`, deliberately. A border's colour arrives per
    /// frame — `palette.border`, a container's override, or one step of an
    /// `AnimatedColor` pulse — so a colour stored on the style would be a
    /// second source of truth the pulse could not honour, and an animated wall
    /// would breathe over a frozen background. This says only "my glyph fills
    /// its cell; paint it in whatever colour you are drawing me in", which is
    /// exactly what ``TrackConfiguration/Background/solid`` means.
    ///
    /// True only for ``block``. `U+2588` does not cover its cell on every
    /// terminal — Terminal.app leaves hairline seams between adjacent full
    /// blocks, recorded in `Documentation/Terminals/Terminal compatibility survey.md` — and
    /// painting the cell the same colour as the glyph makes the pixels the
    /// glyph misses the right colour anyway. `TrackConfiguration.block` has
    /// always done this; a border made of the same glyph has the same problem.
    ///
    /// It must stay false for ``none``, whose whole contract is that whatever
    /// is behind it shows through: painting would make the quietest border the
    /// loudest.
    public let paintsBackground: Bool

    /// Creates a custom border style.
    public init(
        topLeft: Character,
        topRight: Character,
        bottomLeft: Character,
        bottomRight: Character,
        horizontal: Character,
        vertical: Character,
        leftT: Character? = nil,
        rightT: Character? = nil,
        bottomHorizontal: Character? = nil,
        rightVertical: Character? = nil,
        paintsBackground: Bool = false
    ) {
        self.init(
            topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight,
            horizontal: horizontal, vertical: vertical, leftT: leftT, rightT: rightT,
            bottomHorizontal: bottomHorizontal, rightVertical: rightVertical, paintsBackground: paintsBackground,
            brailleThickness: nil)
    }

    private init(
        topLeft: Character, topRight: Character, bottomLeft: Character, bottomRight: Character,
        horizontal: Character, vertical: Character, leftT: Character?, rightT: Character?,
        bottomHorizontal: Character?, rightVertical: Character?, paintsBackground: Bool, brailleThickness: Int?
    ) {
        self.paintsBackground = paintsBackground
        self.brailleThickness = brailleThickness
        self.bottomHorizontal = bottomHorizontal ?? horizontal
        self.rightVertical = rightVertical ?? vertical
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.horizontal = horizontal
        self.vertical = vertical
        // Default T-junctions based on the vertical character
        self.leftT = leftT ?? vertical
        self.rightT = rightT ?? vertical
    }

    // MARK: - Preset Styles

    /// Single line border (─ │ ┌ ┐ └ ┘ ├ ┤).
    ///
    /// ```
    /// ┌─────────┐
    /// │ Title   │
    /// ├─────────┤
    /// │ Content │
    /// └─────────┘
    /// ```
    public static let line = Self(
        topLeft: "┌",
        topRight: "┐",
        bottomLeft: "└",
        bottomRight: "┘",
        horizontal: "─",
        vertical: "│",
        leftT: "├",
        rightT: "┤"
    )

    /// Double line border (═ ║ ╔ ╗ ╚ ╝ ╠ ╣).
    ///
    /// ```
    /// ╔═════════╗
    /// ║ Title   ║
    /// ╠═════════╣
    /// ║ Content ║
    /// ╚═════════╝
    /// ```
    public static let doubleLine = Self(
        topLeft: "╔",
        topRight: "╗",
        bottomLeft: "╚",
        bottomRight: "╝",
        horizontal: "═",
        vertical: "║",
        leftT: "╠",
        rightT: "╣"
    )

    /// Rounded border with curved corners (─ │ ╭ ╮ ╰ ╯ ├ ┤).
    ///
    /// ```
    /// ╭─────────╮
    /// │ Title   │
    /// ├─────────┤
    /// │ Content │
    /// ╰─────────╯
    /// ```
    public static let rounded = Self(
        topLeft: "╭",
        topRight: "╮",
        bottomLeft: "╰",
        bottomRight: "╯",
        horizontal: "─",
        vertical: "│",
        leftT: "├",
        rightT: "┤"
    )

    /// Heavy/bold border (━ ┃ ┏ ┓ ┗ ┛ ┣ ┫).
    ///
    /// ```
    /// ┏━━━━━━━━━┓
    /// ┃ Title   ┃
    /// ┣━━━━━━━━━┫
    /// ┃ Content ┃
    /// ┗━━━━━━━━━┛
    /// ```
    public static let heavy = Self(
        topLeft: "┏",
        topRight: "┓",
        bottomLeft: "┗",
        bottomRight: "┛",
        horizontal: "━",
        vertical: "┃",
        leftT: "┣",
        rightT: "┫"
    )

    /// A border of Braille dots, `thickness` dots thick — `1`, a dotted line;
    /// `2`, a bolder one.
    ///
    /// ```
    /// ⡏⠉⠉⠉⠉⠉⠉⠉⢹       ⣿⠛⠛⠛⠛⠛⠛⠛⣿
    /// ⡇ Title ⢸       ⣿ Title ⣿
    /// ⣇⣀⣀⣀⣀⣀⣀⣀⣸       ⣿⣤⣤⣤⣤⣤⣤⣤⣿
    /// ```
    ///
    /// A Braille cell is two dots across and four down, so the top and bottom
    /// edges take up to four rows of dots and the walls up to two columns:
    /// `thickness` is held to `1...4`, and a wall to at most two. The top edge
    /// sits at the head of its cells and the bottom at the foot, so a box's
    /// lines run along its outside, as a line border's do.
    ///
    /// - Parameter thickness: The lines' thickness in dots.
    /// - Returns: A dotted border style.
    public static func braille(thickness: Int = 1) -> Self {
        let rows = min(max(thickness, 1), 4)
        let columns = min(rows, 2)
        // Each dot's bit, by row and column (Unicode's Braille numbering).
        let bits: [[UInt32]] = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]]
        func mask(rows: Range<Int>, columns: Range<Int>) -> UInt32 {
            rows.reduce(0) { sum, row in columns.reduce(sum) { $0 | bits[row][$1] } }
        }
        let top = mask(rows: 0..<rows, columns: 0..<2)
        let bottom = mask(rows: (4 - rows)..<4, columns: 0..<2)
        let left = mask(rows: 0..<4, columns: 0..<columns)
        let right = mask(rows: 0..<4, columns: (2 - columns)..<2)
        // In the Braille block for every mask a byte can hold, so never the blank.
        func glyph(_ mask: UInt32) -> Character { Unicode.Scalar(0x2800 + mask).map(Character.init) ?? " " }
        return Self(
            topLeft: glyph(top | left), topRight: glyph(top | right),
            bottomLeft: glyph(bottom | left), bottomRight: glyph(bottom | right),
            horizontal: glyph(top), vertical: glyph(left),
            leftT: glyph(top | left), rightT: glyph(top | right),
            bottomHorizontal: glyph(bottom), rightVertical: glyph(right),
            paintsBackground: false, brailleThickness: rows)
    }

    /// A solid bar of full blocks (█), drawn in the border colour.
    ///
    /// The heaviest border a terminal can draw: not a line around the content
    /// but a band of colour enclosing it. Its corners and junctions are the
    /// same glyph as its edges, because a full block has no direction to turn.
    public static let block = Self(
        topLeft: "█",
        topRight: "█",
        bottomLeft: "█",
        bottomRight: "█",
        horizontal: "█",
        vertical: "█",
        leftT: "█",
        rightT: "█",
        paintsBackground: true
    )

    /// No visible border (space characters).
    public static let none = Self(
        topLeft: " ",
        topRight: " ",
        bottomLeft: " ",
        bottomRight: " ",
        horizontal: " ",
        vertical: " ",
        leftT: " ",
        rightT: " "
    )
}
