//  🖥️ TUI — A Terminal UI framework for Swift
//  ANSIRunSlicingStateTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

/// What a slice carries in front of its cells: the styling in force where it
/// starts, netted, not every SGR escape the columns before it held.
///
/// A slice used to open with the row's whole SGR history up to its first
/// column. Cut into one-cell runs, as a gradient background cuts a row, a row
/// with an SGR per cell then held about W²/2 escapes (CORE1-6). The netted
/// prefix is bounded, so these tests pin the size, and pin that the terminal
/// is left drawing exactly the same cells as the history drew: glyph,
/// foreground, background, attributes, underline shape and colour, and
/// hyperlink, cell by cell, and the state after the last cell. Bytes may
/// differ; the drawn result may not.
///
/// "The same" is asked in more than a fresh terminal. A slice is written after
/// other cells, and a painter puts its own fill back after every reset in it
/// (`ANSIRenderer.restating(_:afterResetsIn:)`), so a stated `ESC[49m` and a
/// reset are not interchangeable in a prefix, nor is a `22` that turns off a
/// bold the row never had. Each comparison is made from several prior states
/// with several fills restated after resets.
@Suite("ANSI run slicing: netted style")
struct ANSIRunSlicingStateTests {

    // MARK: - Size

    /// One cell per column, each in a colour of its own.
    private let perCellColoured = (0..<120).map { "\u{1B}[38;2;\($0);100;200mx" }.joined()

    @Test("one-cell runs of a row with an SGR per cell cost bytes linear in the width")
    func oneCellRunsAreLinear() {
        let pieces = perCellColoured.ansiAwareSlices(runWidths: Array(repeating: 1, count: 120))
        let bytes = pieces.map(\.utf8.count).reduce(0, +)
        // Each piece is its netted prefix (one 24-bit colour, ≈20 bytes) and
        // its own cell's escape and glyph (≈20). The history made it 137 KB.
        #expect(bytes < 120 * 48, "\(bytes) bytes for 120 one-cell pieces")
    }

    @Test("a slice far into a styled row carries one netted prefix")
    func farSliceIsBounded() {
        let slice = perCellColoured.ansiAwareSlice(visibleStart: 119, visibleCount: 1)
        #expect(slice.utf8.count < 48, "\(slice.utf8.count) bytes: \(slice.debugDescription)")
    }

    // MARK: - State equivalence

    @Test("pieces draw what the history-replaying slice drew, over random rows")
    func randomRowsDrawTheSame() {
        var generator = SplitMix(seed: 0x5_1CE5)
        for _ in 0..<400 {
            let row = Self.randomRow(using: &generator)
            let width = row.strippedLength
            let widths = Self.randomCuts(of: width, using: &generator)
            let pieces = row.ansiAwareSlices(runWidths: widths)
            var start = 0
            var referenceJoined = ""
            for (piece, runWidth) in zip(pieces, widths) {
                // A run at column zero carries nothing across a cut, so it is
                // not what this is about, and the cut and the slice function
                // already part company there: the slice keeps the escapes at
                // its right edge, which the cut hands to the next run, and
                // closes a link before the blanks of a wide glyph it cuts.
                guard start > 0 else {
                    referenceJoined += piece
                    start += max(0, runWidth)
                    continue
                }
                let reference = Self.historySlice(row, visibleStart: start, visibleCount: runWidth)
                referenceJoined += reference
                let single = row.ansiAwareSlice(visibleStart: start, visibleCount: runWidth)
                for context in Self.contexts {
                    let expected = Self.drawn(reference, in: context)
                    #expect(Self.drawn(single, in: context) == expected)
                    #expect(
                        Self.drawn(piece, in: context) == expected,
                        """
                        \(row.debugDescription) cut at \(widths), run at \(start): \(piece.debugDescription) \
                        against \(reference.debugDescription) in \(context)
                        """)
                }
                start += max(0, runWidth)
            }
            // And put back together, as a painter joins them.
            for context in Self.contexts {
                #expect(Self.drawn(pieces.joined(), in: context) == Self.drawn(referenceJoined, in: context))
            }
        }
    }

    // MARK: - The model terminal

    /// Where a piece is written: the state the terminal is already in, and what
    /// a painter restates after each reset in the piece.
    struct Context: CustomStringConvertible {
        let prior: String
        let restore: String
        var description: String { "prior \(prior.debugDescription), restoring \(restore.debugDescription)" }
    }

    static let contexts: [Context] = [
        Context(prior: "", restore: ""),
        Context(prior: "", restore: "\u{1B}[44m"),
        Context(prior: "\u{1B}[1;2;4;7;31;42;58:5:3m", restore: ""),
        Context(prior: "\u{1B}[1;3;9;38;5;100;48;2;1;2;3m", restore: "\u{1B}[2;48;5;17m"),
    ]

    /// One cell as drawn: its glyph (empty for a wide glyph's second cell), the
    /// styling, and the link it opens.
    struct Cell: Equatable {
        let glyph: String
        let style: Style
        let link: String?
    }

    /// A state, compared up to its unknown codes' repeats and order.
    ///
    /// `SGRState` keeps a code it does not model (53, 55, 73 …) verbatim and in
    /// order, so a replay that restates one holds it twice where the netting
    /// holds it once: a difference in the model, not on a terminal, which
    /// draws `53;53` as it draws `53`. Which of them are in force is compared;
    /// everything the model reads is compared exactly.
    struct Style: Equatable {
        let known: SGRState
        let unknown: Set<String>

        init(_ state: SGRState) {
            unknown = Set(state.passthrough)
            // The state without them: its own spelling with them left out,
            // read back.
            let spelled = state.parameters
            let lead = state.passthrough.joined(separator: ";")
            var rest = Substring(spelled)
            if !lead.isEmpty {
                rest = rest.dropFirst(lead.count)
                if rest.first == ";" { rest = rest.dropFirst() }
            }
            var known = SGRState()
            if !rest.isEmpty { known.apply("\u{1B}[" + rest + "m") }
            self.known = known
        }
    }

    struct Drawn: Equatable {
        var cells: [Cell] = []
        var final = Style(SGRState())
        var link: String?
    }

    /// What `text` draws, written in `context`.
    static func drawn(_ text: String, in context: Context) -> Drawn {
        var state = SGRState()
        state.apply(context.prior)
        var link = HyperlinkScan()
        var result = Drawn()
        text.forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                if isSGR {
                    if let after = SGRState.parametersAfterReset(in: sequence) {
                        state = SGRState()
                        if !context.restore.isEmpty { state.apply(context.restore) }
                        if !after.isEmpty { state.apply("\u{1B}[" + after + "m") }
                    } else {
                        state.apply(sequence)
                    }
                } else {
                    link.note(sequence)
                }
            case .visible(let character):
                for cell in 0..<character.terminalWidth {
                    result.cells.append(
                        Cell(glyph: cell == 0 ? String(character) : "", style: Style(state), link: link.opening))
                }
            }
            return true
        }
        result.final = Style(state)
        result.link = link.opening
        return result
    }

    // MARK: - The reference

    /// `ansiAwareSlice(visibleStart:visibleCount:)` as it was before the
    /// netting: the escapes before the window replayed one after another.
    static func historySlice(_ row: String, visibleStart: Int, visibleCount: Int) -> String {
        guard visibleCount > 0 else { return "" }
        guard visibleStart > 0 else { return row.ansiAwareSlice(visibleStart: 0, visibleCount: visibleCount) }
        let end = visibleStart + visibleCount
        var carried = ""
        var body = ""
        var visible = 0
        var link = HyperlinkScan()
        var entered = false
        func enter() {
            guard !entered else { return }
            entered = true
            body += link.reopening
        }
        row.forEachANSISegment { segment in
            guard visible < end else { return false }
            switch segment {
            case .ansi(let sequence, let isSGR):
                if visible < visibleStart {
                    if isSGR { carried += sequence } else { link.note(sequence) }
                } else {
                    enter()
                    body += sequence
                    if !isSGR { link.note(sequence) }
                }
            case .visible(let character):
                let charEnd = visible + character.terminalWidth
                if visible >= visibleStart && charEnd <= end {
                    enter()
                    body.append(character)
                } else if charEnd > visibleStart {
                    enter()
                    body += String(repeating: " ", count: min(charEnd, end) - max(visible, visibleStart))
                }
                visible = charEnd
            }
            return true
        }
        return carried + body + link.closingIfOpen
    }

    // MARK: - Random rows

    /// Every code `SGRState` models, in each spelling, with the malformed, the
    /// combined, and codes it passes through (53, 55, 73).
    private static let escapes: [String] = [
        "0", "", "1", "2", "22", "21", "3", "23", "4", "4:3", "4:0", "24", "5", "25", "7", "27", "8", "28", "9", "29",
        "31", "97", "39", "44", "103", "49", "38;5;196", "48;2;10;20;30", "38;2;0;0;0", "38:5:42", "48:2::1:2:3",
        "58:2::9:8:7", "58;5;4", "59", "53", "55", "0;1;31", "1;0;42", "22;1", ";4", "2;22;2", "31;0", "38;5", "73",
        "1;53;31",
    ].map { "\u{1B}[" + $0 + "m" }

    private static let glyphs = ["a", "b", " ", "  ", "漢", "👍🏽", "e\u{301}", "xyz"]

    private static let links = ["\u{1B}]8;;https://example.com/a\u{1B}\\", "\u{1B}]8;;\u{1B}\\", "\u{1B}[2C"]

    static func randomRow(using generator: inout SplitMix) -> String {
        var row = ""
        for _ in 0..<Int.random(in: 4...40, using: &generator) {
            switch Int.random(in: 0..<10, using: &generator) {
            case 0..<5: row += escapes.randomElement(using: &generator)!
            case 5: row += links.randomElement(using: &generator)!
            default: row += glyphs.randomElement(using: &generator)!
            }
        }
        return row
    }

    /// Run widths that tile the row, now and then running past its end, and
    /// now and then holding an empty run.
    static func randomCuts(of width: Int, using generator: inout SplitMix) -> [Int] {
        var widths: [Int] = []
        var covered = 0
        let target = width + (Bool.random(using: &generator) ? 0 : Int.random(in: 0...3, using: &generator))
        while covered < target {
            let next = Int.random(in: 0...4, using: &generator)
            widths.append(next)
            covered += next
        }
        return widths.isEmpty ? [0] : widths
    }

    /// A tiny deterministic generator, so the rows are the same each run.
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
