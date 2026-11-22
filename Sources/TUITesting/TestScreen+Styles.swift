//  🖥️ TUI — A Terminal UI framework for Swift
//  TestScreen+Styles.swift
//
//  What a TestApp's screen draws a cell in: its colours, weight, slant,
//  underline and strike, read from the escape codes of its row (B-ATTRED-62),
//  so a test can ask whether a word is drawn in a colour without parsing SGR.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension TestScreen {
    /// How a cell is drawn: as the terminal is told to draw it.
    public struct CellStyle: Equatable, Sendable {
        /// A colour as the terminal is sent it.
        public enum Colour: Equatable, Sendable {
            /// One of the sixteen named colours, by its SGR code: 30 to 37
            /// and 90 to 97 for a foreground, 40 to 47 and 100 to 107 for a
            /// background.
            case named(Int)
            /// One of the 256 indexed colours.
            case indexed(Int)
            /// A 24-bit colour, each component 0 to 255: how a ``TestApp``'s
            /// terminal, which draws through a theme at 24 bits, sends most.
            case rgb(red: Int, green: Int, blue: Int)
        }

        /// The ink, or `nil` for the terminal's default.
        public var foreground: Colour?
        /// The field, or `nil` for the terminal's default.
        public var background: Colour?
        public var isBold: Bool
        public var isFaint: Bool
        public var isItalic: Bool
        /// The underline, as SGR `4:n` numbers its shape: 1 single, 2 double,
        /// 3 curly, 4 dotted, 5 dashed; `nil` for none.
        public var underline: Int?
        public var isStruckThrough: Bool
        /// Whether the cell is drawn in reverse video.
        public var isReversed: Bool
    }

    /// How the cell at `point` is drawn, or `nil` past its row's last
    /// character. A wide character's two cells are both its.
    public func style(at point: CellPoint) -> CellStyle? {
        guard styledLines.indices.contains(point.y), point.x >= 0 else { return nil }
        var column = 0
        for (character, state) in Self.cells(of: styledLines[point.y]) {
            let width = max(1, String(character).strippedLength)
            if point.x < column + width { return CellStyle(state) }
            column += width
        }
        return nil
    }

    /// How the first character of the first place `text` shows is drawn, or
    /// `nil` if it does not show.
    public func style(of text: String) -> CellStyle? {
        location(of: text).flatMap { style(at: $0) }
    }

    /// Each visible character of a styled row, with the state its codes
    /// leave the terminal in.
    private static func cells(of line: String) -> [(character: Character, state: SGRState)] {
        var state = SGRState()
        var cells: [(character: Character, state: SGRState)] = []
        for segment in line.ansiSegments() {
            switch segment {
            // Not ink: an escape sequence read back off the screen.
            // swiftlint:disable:next framework_colour_literal
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible(let character): cells.append((character, state))
            }
        }
        return cells
    }
}

extension TestScreen.CellStyle {
    init(_ state: SGRState) {
        foreground = state.foregroundColour.map(Colour.init)
        background = state.backgroundColour.map(Colour.init)
        isBold = state.isBold
        isFaint = state.isFaint
        isItalic = state.isItalic
        underline = state.underline
        isStruckThrough = state.isStruckThrough
        isReversed = state.reversesVideo
    }
}

extension TestScreen.CellStyle.Colour {
    init(_ colour: SGRState.Colour) {
        switch colour {
        case .named(let code): self = .named(code)
        case .indexed(let index): self = .indexed(index)
        // Not ink: a colour read back off the screen, as the terminal was sent it.
        // swiftlint:disable:next framework_colour_literal
        case .rgb(let red, let green, let blue): self = .rgb(red: red, green: green, blue: blue)
        }
    }
}
