//  🖥️ TUI — A Terminal UI framework for Swift
//  SGRColorRewrite+Pictures.swift
//
//  A line's colours rewritten where it may draw pictures, whose cells name
//  their image in their foreground rather than a colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

extension SGRColorRewrite {
    /// ``rewriting(_:defaultForeground:defaultBackground:transform:)`` for a
    /// line that may draw pictures: each picture cell draws a copy of its
    /// picture changed by `pictures` (`DerivedImages`), and where there is no
    /// copy to draw — no store, no transform for pictures, or a picture the
    /// store cannot copy — the picture as it was.
    ///
    /// A picture cell's foreground is its image's id (Kitty's Unicode
    /// placeholders), so the plain rewrite turned the id into one no image
    /// has, and the terminal drew nothing there: `LinearGradient(…)
    /// .grayscale(1)` was a blank strip in Ghostty, which draws a gradient as
    /// a picture. A transform that happened to leave the id's bytes alone
    /// drew the picture unchanged instead.
    ///
    /// - Parameters:
    ///   - line: A rendered line, escapes and all.
    ///   - defaultForeground: What `39` (default foreground) means here.
    ///   - defaultBackground: What `49` (default background) means here.
    ///   - pictures: What `transform` does to a picture's pixels, or `nil`
    ///     where it has no such form.
    ///   - images: The pictures the app has put in the terminal.
    ///   - transform: The colour effect. Called with resolved colours only.
    package static func rewriting(
        _ line: String, defaultForeground: Color, defaultBackground: Color,
        pictures: ImageTransform?, images: TerminalImageStore?, transform: (Color) -> Color
    ) -> String {
        guard line.unicodeScalars.contains(.terminalImagePlaceholder) else {
            return rewriting(
                line, defaultForeground: defaultForeground, defaultBackground: defaultBackground,
                transform: transform)
        }
        func rewritten(_ sequence: String) -> String {
            rewritingSGR(
                sequence, defaultForeground: defaultForeground, defaultBackground: defaultBackground,
                transform: transform)
        }
        var result = ""
        result.reserveCapacity(line.utf8.count)
        // What the line itself says is in force, to read each picture cell's
        // image by: the rewritten escapes no longer say it.
        var state = SGRState()
        line.forEachANSISegment { segment in
            switch segment {
            case .visible(let character):
                // A pattern reading the ink's channels, not a colour this draws with.
                // swiftlint:disable:next framework_colour_literal
                guard case .rgb(let red, let green, let blue)? = state.foregroundColour,
                    let cell = KittyGraphics.placeholderCell(
                        character,
                        foreground: (UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue)))
                else {
                    result.append(character)
                    return true
                }
                let drawn = pictures.flatMap { pictures in images?.derived(cell, by: pictures) } ?? cell
                // The cell, its id stated, and then the line's own state put
                // back, rewritten, for whatever follows: the next picture cell,
                // which a picture's row does not restate the id for, or the
                // `ESC[39m` its row ends with.
                result += drawn.spelled + "\u{1B}[39m" + rewritten(state.rendered)
            // A rendered line's escape segment, not a colour: the rule matches
            // `.ansi(` wherever it is written.
            // swiftlint:disable:next framework_colour_literal
            case .ansi(let sequence, _):
                state.apply(sequence)
                result += rewritten(sequence)
            }
            return true
        }
        return result
    }
}
