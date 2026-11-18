//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+ParagraphStyle.swift
//
//  An attributed text's paragraphs, each aligned its own way: which paragraph
//  each drawn line is of, and the alignment it takes (G3 L4, A-ATTRED-3).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@MainActor extension Text {
    /// `wrapped`'s lines aligned within the block's own width, `blockWidth`
    /// (the widest line), and their widths.
    ///
    /// `multilineTextAlignment`: for `.center` / `.trailing` over more than
    /// one line, pad each line into the block's own width so shorter lines
    /// shift right or centre relative to it — SwiftUI's line-to-line
    /// alignment. `.leading` (the default) and single-line text keep the
    /// ragged, unpadded lines exactly as before (no snapshot churn; the padding
    /// would be invisible trailing space anyway), and the block width the
    /// measure pass reported is unchanged in every case. An attributed
    /// string's paragraph `alignment` aligns its own lines the same way, in
    /// place of the environment's (``lineAlignments(of:in:width:lineCount:otherwise:)``).
    static func aligned(
        _ wrapped: TextWrapping.Wrapped, blockWidth: Int, runs: [Run]?, text: String, width: Int,
        alignment: TextAlignment
    ) -> (lines: [String], widths: [Int]) {
        guard wrapped.lines.count > 1, blockWidth > 0 else { return (wrapped.lines, wrapped.widths) }
        let perLine = runs.flatMap {
            lineAlignments(of: $0, in: text, width: width, lineCount: wrapped.lines.count, otherwise: alignment)
        }
        guard alignment != .leading || perLine != nil else { return (wrapped.lines, wrapped.widths) }
        var aligned: [String] = []
        aligned.reserveCapacity(wrapped.lines.count)
        for (index, (line, lineWidth)) in zip(wrapped.lines, wrapped.widths).enumerated() {
            let leadingPad = (perLine?[index] ?? alignment).leadingPad(
                lineWidth: lineWidth, blockWidth: blockWidth)
            let trailingPad = max(0, blockWidth - lineWidth - leadingPad)
            aligned.append(String.spaces(leadingPad) + line + String.spaces(trailingPad))
        }
        return (aligned, Array(repeating: blockWidth, count: aligned.count))
    }

    /// The alignment of each of `lineCount` lines `text` wraps to at `width`,
    /// where `runs` state a paragraph's alignment: the alignment of the
    /// paragraph each line is of, or `fallback` (the environment's
    /// ``View/multilineTextAlignment(_:)``) for a paragraph that states none.
    /// `nil` where no run states one, which is every text but an attributed
    /// one with an `alignment`: those pay one scan of their runs' flags.
    ///
    /// - Parameters:
    ///   - text: The words as wrapped, cased as drawn.
    ///   - lineCount: The lines the fit kept. A line limit folds the rest into
    ///     the last one, which is aligned as the paragraph it starts in.
    static func lineAlignments(
        of runs: [Run], in text: String, width: Int, lineCount: Int, otherwise fallback: TextAlignment
    ) -> [TextAlignment]? {
        guard runs.contains(where: { $0.alignment != nil }) else { return nil }
        let paragraphs = paragraphAlignments(of: runs)
        var lines: [TextAlignment] = []
        lines.reserveCapacity(lineCount)
        for (alignment, count) in zip(paragraphs, TextWrapping.paragraphLineCounts(text, width: width)) {
            let aligned = alignment?.multilineAlignment ?? fallback
            lines.append(contentsOf: repeatElement(aligned, count: min(count, lineCount - lines.count)))
            if lines.count == lineCount { break }
        }
        lines.append(contentsOf: repeatElement(fallback, count: lineCount - lines.count))
        return lines
    }

    /// Each paragraph's alignment: that of the run its first character is in.
    /// The attribute is bounded by paragraphs, so every run of a paragraph
    /// states the same one; a trailing empty paragraph states none.
    nonisolated static func paragraphAlignments(of runs: [Run]) -> [AttributedString.TextAlignment?] {
        var paragraphs: [AttributedString.TextAlignment?] = []
        var atParagraphStart = true
        for run in runs {
            for character in run.text {
                if atParagraphStart {
                    paragraphs.append(run.alignment)
                    atParagraphStart = false
                }
                // The breaks `TextWrapping` splits paragraphs at.
                if character == "\n" || character == "\r\n" || character == "\r" { atParagraphStart = true }
            }
        }
        if atParagraphStart { paragraphs.append(nil) }
        return paragraphs
    }
}
