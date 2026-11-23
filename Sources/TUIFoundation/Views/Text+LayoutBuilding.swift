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

@MainActor extension Text {
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
        // A text that draws another in its place — relocalized, or a live
        // text's reading at this frame (`drawn(context:…)`) — is laid out from
        // the words that one draws, or every glyph would be matched against
        // words that are not there. The reading is the pure one: the frame's
        // own draw has already declared when it next changes.
        if localization != nil, let read = relocalized(in: context) {
            return read.layout(of: drawn, context: context)
        }
        if isLive, let read = readingLive(at: context.liveFrameDate, in: LiveTextEnvironment(context.environment)) {
            return read.text.layout(of: drawn, context: context)
        }
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
                    let width = character.terminalWidth
                    // Skip the words' blanks the drawing dropped at a wrap.
                    while next < words.count, words[next].character != character,
                        words[next].character.isWhitespace
                    {
                        next += 1
                    }
                    // A zero-width grapheme of its own (a zero-width space, a
                    // bidi mark) takes no cell: it is part of the glyph before
                    // it, or dropped where there is none, and still counts
                    // among the words. A glyph 0 cells wide would put the rest
                    // of the row a column right, and stall the surface's walk.
                    guard width > 0 else {
                        if next < words.count, words[next].character == character { next += 1 }
                        if !glyphs.isEmpty {
                            glyphs[glyphs.count - 1].character.append(character)
                        } else if let run = runs.last, var last = run.glyphs.last {
                            last.character.append(character)
                            runs[runs.count - 1] = Layout.Run(
                                glyphs: Array(run.glyphs.dropLast()) + [last], style: run.style, attributes: run.attributes)
                        }
                        return true
                    }
                    defer { column += width }
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
                            characterIndex: Layout.CharacterIndex(offset: index),
                            claims: Self.claims(over: column, row: row, width: width, in: drawn.opacityRegions)))
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

    /// The claims of `regions` over the `width` cells from (`column`, `row`),
    /// each moved to cover those cells alone, from their top-left: the text
    /// wrote its translucent colours opaque and the alpha as claims
    /// (`opacityRegions`), which a glyph drawn by a renderer must keep.
    private static func claims(over column: Int, row: Int, width: Int, in regions: [OpacityRegion]) -> [OpacityRegion] {
        guard !regions.isEmpty else { return [] }
        return regions.compactMap { region in
            guard region.offsetY <= row, row < region.offsetY + region.height, region.offsetX < column + width,
                column < region.offsetX + region.width
            else { return nil }
            var claim = region
            (claim.offsetX, claim.offsetY, claim.width, claim.height) = (0, 0, width, 1)
            return claim
        }
    }

    /// The words as this text lays them out — transliterated, cased and
    /// redacted as drawn — a grapheme at a time, each with its run's custom
    /// attributes.
    private func laidOutWords(context: RenderContext) -> [(character: Character, attributes: TextAttributes?)] {
        let font = resolvedFont(stating: style.font, context: context)
        let textCase = cascadedAttributes(context: context, font: font).effectiveTextCase
        let redaction = context.environment.effectiveRedactionReasons
        let spelling = context.textSpelling
        let shown = shownWords(in: context.environment)
        guard let runs = shown.runs else {
            return Self.displayString(
                shown.content, textCase: textCase, redaction: redaction, spelling: spelling,
                keepingEscapes: context.environment.textKeepsEscapeSequences
            ).map { ($0, nil) }
        }
        return runs.flatMap { run in
            Self.displayString(
                run.text, textCase: textCase, redaction: redaction, spelling: spelling,
                keepingEscapes: context.environment.textKeepsEscapeSequences
            ).map { ($0, run.attributes) }
        }
    }
}

extension Array {
    /// The element at `index`, or `nil` past either end.
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
