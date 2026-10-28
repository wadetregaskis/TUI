//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+LayoutBuilding.swift
//
//  A text's `Text.Layout`, read from its own drawing: the rows it drew, cut
//  into runs where the style or the custom attributes change, each run's
//  grapheme clusters at the cells they were drawn in. Built only for a text
//  drawn by a `TextRenderer`.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import TUICore

extension Text {
    /// The layout of `drawn`, this text's own drawing in `context`.
    ///
    /// Each drawn grapheme is matched, in order, to the text's words as they
    /// were laid out (cased and redacted as drawn), which says where its
    /// characters start (``Text/Layout/CharacterIndex``) and which run's
    /// custom attributes it carries. A drawn blank the words do not have
    /// there is alignment's padding, not a glyph; a word's space the drawing
    /// does not have was dropped at a wrap; a drawn character the words do not
    /// have (a truncation's ellipsis) is a glyph of the run before it. Words
    /// left over at the end mean the text was cut short.
    func layout(of drawn: FrameBuffer, context: RenderContext) -> Layout {
        let words = laidOutWords(context: context)
        var next = 0
        var lines: [Layout.Line] = []
        for (row, line) in drawn.lines.enumerated() {
            var runs: [Layout.Run] = []
            var glyphs: [Layout.Glyph] = []
            var runStyle = SGRState()
            var runAttributes: TextAttributes?
            var state = SGRState()
            var column = 0
            var firstColumn: Int?
            func closeRun() {
                if !glyphs.isEmpty { runs.append(Layout.Run(glyphs: glyphs, style: runStyle, attributes: runAttributes)) }
                glyphs = []
            }
            _ = line.forEachANSISegment { segment in
                switch segment {
                // A rendered line's escape, not a colour: the rule matches
                // `.ansi(` wherever it is written.
                // swiftlint:disable:next framework_colour_literal
                case .ansi(let sequence, let isSGR):
                    if isSGR { state.apply(sequence) }
                case .visible(let character):
                    let width = max(1, character.terminalWidth)
                    defer { column += width }
                    // Skip the words' blanks the drawing dropped at a wrap.
                    while next < words.count, words[next].character != character,
                        words[next].character.isWhitespace
                    {
                        next += 1
                    }
                    let index: Int
                    let attributes: TextAttributes?
                    if next < words.count, words[next].character == character {
                        index = next
                        attributes = words[next].attributes
                        next += 1
                    } else if character.isWhitespace {
                        return true  // alignment's padding
                    } else {
                        index = max(0, next - 1)
                        attributes = glyphs.last.map { _ in runAttributes } ?? words[safe: next - 1]?.attributes
                    }
                    if glyphs.isEmpty || state != runStyle || attributes != runAttributes {
                        closeRun()
                        runStyle = state
                        runAttributes = attributes
                    }
                    firstColumn = firstColumn ?? column
                    glyphs.append(
                        Layout.Glyph(
                            character: String(character), column: column, row: row, width: width,
                            characterIndex: Layout.CharacterIndex(offset: index)))
                }
                return true
            }
            closeRun()
            guard !runs.isEmpty else { continue }
            let start = firstColumn ?? 0
            lines.append(
                Layout.Line(
                    origin: CGPoint(x: CGFloat(start), y: CGFloat(row)), runs: runs,
                    width: (runs.last?.glyphs.last).map { $0.column + $0.width - start } ?? 0))
        }
        let cutShort = words[next...].contains { !$0.character.isWhitespace }
        return Layout(lines: lines, isTruncated: cutShort)
    }

    /// The words as this text lays them out — cased and redacted as drawn —
    /// a grapheme at a time, each with its run's custom attributes.
    private func laidOutWords(context: RenderContext) -> [(character: Character, attributes: TextAttributes?)] {
        let font = resolvedFont(stating: style.font, context: context)
        let textCase = cascadedAttributes(context: context, font: font).effectiveTextCase
        let redaction = context.environment.effectiveRedactionReasons
        let shown = shownWords(in: context.environment)
        guard let runs = shown.runs else {
            return Self.displayString(shown.content, textCase: textCase, redaction: redaction).map { ($0, nil) }
        }
        return runs.flatMap { run in
            Self.displayString(run.text, textCase: textCase, redaction: redaction).map { ($0, run.attributes) }
        }
    }
}

extension Array {
    /// The element at `index`, or `nil` past either end.
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
