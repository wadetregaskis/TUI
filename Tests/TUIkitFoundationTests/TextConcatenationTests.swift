//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextConcatenationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

/// One text, several styles: `Text`s interpolated into a `Text`, each keeping
/// its own (SwiftUI's replacement for the deprecated `Text + Text`).
///
/// The fragments are *styling*, not layout: the result wraps, truncates and
/// measures as a single piece of text, which is what makes it different from
/// an `HStack` of Texts and is the reason the styling has to be re-applied
/// after the wrap rather than before it.
@MainActor
@Suite("Text of several runs")
struct TextConcatenationTests {

    /// The SGR parameters the renderer emits for a foreground colour — the
    /// form a rendered line actually carries.
    private func codes(_ color: Color) -> String {
        color.foregroundCodes().joined(separator: ";")
    }

    // MARK: - The property the whole design rests on

    @Test("Wrapping preserves every non-whitespace character, in order")
    func wrapPreservesCharacters() {
        // Re-attributing wrapped lines to runs walks a cursor through the
        // source. That is only sound because the wrap picks break points and
        // drops whitespace at them — it never reorders, substitutes or
        // invents. If that ever stops being true, per-run styling silently
        // mis-colours, so the property is pinned here rather than assumed.
        let alphabets = [
            "abcdefghij ",  // ascii prose
            "abc  def   ghi ",  // runs of spaces
            "  leading and trailing  ",  // indents
            "日本語のテキストです",  // wide, no break opportunities
            "mixed 日本語 and ascii ",  // both walks in one string
            "supercalifragilistic short ",  // a word longer than the width
        ]
        var seed: UInt64 = 0x2026_0810
        func rnd(_ n: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(max(1, n)))
        }
        for alphabet in alphabets {
            let chars = Array(alphabet)
            for _ in 0..<120 {
                let text = String((0..<rnd(40)).map { _ in chars[rnd(chars.count)] })
                for width in [1, 2, 3, 5, 8, 13, 21] {
                    let wrapped = TextWrapping.wrapMeasured(text, width: width)
                    #expect(
                        wrapped.lines.joined().filter { !$0.isWhitespace }
                            == text.filter { !$0.isWhitespace },
                        "width \(width), source \(text.debugDescription)")
                }
            }
        }
    }

    // MARK: - Composition

    @Test("The joined text reads as one string")
    func contentIsJoined() {
        let joined = Text("\(Text(verbatim: "Name: ").bold())\(Text(verbatim: "Ada"))")
        #expect(joined.content == "Name: Ada")
        #expect(joined.runs?.count == 2)
    }

    @Test("Each fragment keeps its own styling")
    func fragmentsKeepTheirStyle() {
        let context = makeRenderContext(width: 40, height: 3)
        let joined = Text("\(Text(verbatim: "bold").bold())\(Text(verbatim: "plain"))")
        let line = renderToBuffer(joined, context: context).lines[0]

        // "bold" carries SGR 1 and "plain" does not — which means the styling
        // was re-applied per fragment, not once for the whole line.
        guard let split = line.range(of: "plain") else {
            Issue.record("the second fragment did not render: \(line.debugDescription)")
            return
        }
        let head = String(line[line.startIndex..<split.lowerBound])
        let tail = String(line[split.lowerBound...])
        #expect(head.contains("\u{1B}[") && head.contains("1"))
        #expect(!tail.contains("1m"))
        #expect(line.stripped == "boldplain")
    }

    @Test("Colours stay with their own fragment")
    func coloursAreLocal() {
        let context = makeRenderContext(width: 40, height: 3)
        let red = Text(verbatim: "red").foregroundStyle(Color.rgb(200, 20, 20))
        let joined = Text("\(red)\(Text(verbatim: "blue").foregroundStyle(Color.rgb(20, 20, 200)))")
        let line = renderToBuffer(joined, context: context).lines[0]
        #expect(line.contains(codes(Color.rgb(200, 20, 20))))
        #expect(line.contains(codes(Color.rgb(20, 20, 200))))
    }

    @Test("A fragment of several runs splices in flat rather than nesting")
    func flattening() {
        let inner = Text("\(Text(verbatim: "a").bold())\(Text(verbatim: "b").italic())")
        let joined = Text("\(inner)\(Text(verbatim: "c").underline())")
        #expect(joined.content == "abc")
        #expect(joined.runs?.count == 3)
        #expect(joined.runs?.map(\.text) == ["a", "b", "c"])
    }

    // MARK: - Where a modifier lands

    @Test("A modifier on the result is the base beneath every fragment")
    func modifierOnTheResult() {
        // SwiftUI: the outer modifier applies to the whole, and a fragment's
        // own attribute still wins. `.italic()` here must reach both, and the
        // first must stay bold.
        let context = makeRenderContext(width: 40, height: 3)
        let joined = Text("\(Text(verbatim: "one").bold())\(Text(verbatim: "two"))").italic()
        let line = renderToBuffer(joined, context: context).lines[0]
        // Compare exact SGR PARAMETERS, not substrings: a truecolour code
        // like `38;2;51;255;51` contains both a "1" and a "3", so a substring
        // test would answer yes to bold and italic for every coloured run.
        let parameterSets: [Set<String>] = line.ansiSegments().compactMap { segment in
            guard case .ansi(let sequence, let isSGR) = segment, isSGR,
                sequence != ANSIRenderer.reset
            else { return nil }
            return Set(sequence.dropFirst(2).dropLast().split(separator: ";").map(String.init))
        }
        // Both fragments italic (SGR 3), only the first bold (SGR 1).
        #expect(parameterSets.count >= 2)
        #expect(parameterSets.allSatisfy { $0.contains("3") }, "not every fragment is italic")
        #expect(parameterSets.filter { $0.contains("1") }.count == 1, "bold reached both")
    }

    @Test("A fragment's colour wins over the result's")
    func fragmentColourWins() {
        let context = makeRenderContext(width: 40, height: 3)
        let own = Text(verbatim: "own").foregroundStyle(Color.rgb(200, 20, 20))
        let joined = Text("\(own)\(Text(verbatim: "inherited"))").foregroundStyle(Color.rgb(20, 20, 200))
        let line = renderToBuffer(joined, context: context).lines[0]
        #expect(line.contains(codes(Color.rgb(200, 20, 20))))
        #expect(line.contains(codes(Color.rgb(20, 20, 200))))
    }

    // MARK: - It is one text, not two views

    @Test("It wraps as a single piece of text")
    func wrapsAsOne() {
        // The whole point of one text over an HStack: a break may fall inside
        // a fragment, and the words either side of a boundary are considered
        // together.
        let context = makeRenderContext(width: 10, height: 5)
        let joined = Text("\(Text(verbatim: "alpha beta ").bold())\(Text(verbatim: "gamma delta"))")
        let buffer = renderToBuffer(joined, context: context)
        #expect(buffer.lines.count > 1)
        let text = buffer.lines.map(\.stripped).joined(separator: " ")
        for word in ["alpha", "beta", "gamma", "delta"] {
            #expect(text.contains(word), "lost \(word) in \(text)")
        }
    }

    @Test("Styling survives a break inside a fragment")
    func styleSurvivesAWrap() {
        // A fragment that spans two lines must be styled on BOTH: the SGR that
        // opened it sat on the first line, so the second needs its own.
        let context = makeRenderContext(width: 8, height: 6)
        let head = Text(verbatim: "aaaa bbbb cccc").foregroundStyle(Color.rgb(200, 20, 20))
        let joined = Text("\(head)\(Text(verbatim: " tail"))")
        let buffer = renderToBuffer(joined, context: context)
        let redLines = buffer.lines.filter { $0.contains(codes(Color.rgb(200, 20, 20))) }
        #expect(redLines.count >= 2, "the colour did not carry onto the wrapped lines")
    }

    @Test("It measures as one text")
    func measuresAsOne() {
        let context = makeRenderContext(width: 40, height: 5)
        let proposal = ProposedSize(width: 40, height: 5)
        let joined = Text("\(Text(verbatim: "Name: ").bold())\(Text(verbatim: "Ada"))")
        let plain = Text(verbatim: "Name: Ada")
        #expect(
            measureChild(joined, proposal: proposal, context: context)
                == measureChild(plain, proposal: proposal, context: context))
    }

    @Test("Truncation still marks the cut")
    func truncation() {
        let context = makeRenderContext(width: 6, height: 1)
        let joined = Text("\(Text(verbatim: "aaaaaa").bold())\(Text(verbatim: "bbbbbb"))")
        let line = renderToBuffer(joined, context: context).lines[0]
        #expect(line.stripped.contains("…"))
        #expect(line.stripped.count <= 6)
    }

    // MARK: - The single-run path is untouched

    @Test("A plain Text renders exactly as it did")
    func singleFragmentIsByteIdentical() {
        // `runs` is nil for almost every Text in existence; that case must not
        // pay for this feature, or even be perturbed by it.
        let context = makeRenderContext(width: 30, height: 4)
        for view in [
            Text(verbatim: "hello"),
            Text(verbatim: "hello").bold().foregroundStyle(.red),
            Text(verbatim: "a longer line that will wrap at this width"),
        ] {
            #expect(view.runs == nil)
            // The same thing as one run must agree with it — the two paths
            // differ in mechanism, not in result.
            var asRuns = view
            asRuns.runs = [Text.Run(text: view.content, style: view.style)]
            #expect(
                renderToBuffer(asRuns, context: context).lines
                    == renderToBuffer(view, context: context).lines)
        }
    }

    @Test("Empty fragments do not disturb the rest")
    func emptyFragments() {
        let context = makeRenderContext(width: 20, height: 3)
        let joined = Text("\(Text(verbatim: ""))\(Text(verbatim: "middle").bold())\(Text(verbatim: ""))")
        let line = renderToBuffer(joined, context: context).lines[0]
        #expect(line.stripped == "middle")
        #expect(line.contains("1"))
    }

    @Test("A fragment of pure whitespace keeps its place")
    func whitespaceFragment() {
        let context = makeRenderContext(width: 20, height: 3)
        let joined = Text("\(Text(verbatim: "a").bold())\(Text(verbatim: " ").italic())\(Text(verbatim: "b"))")
        #expect(renderToBuffer(joined, context: context).lines[0].stripped == "a b")
    }

    // MARK: - Attribution directly

    @Test("Attribution splits a line at fragment boundaries")
    func attributionSplits() {
        var cursor = (run: 0, offset: 0)
        let parts = TextRunAttribution.fragments(
            of: "abcdef", runTexts: ["abc", "def"], cursor: &cursor)
        #expect(parts.map(\.text) == ["abc", "def"])
        #expect(parts.map(\.run) == [0, 1])
    }

    @Test("Attribution carries its cursor across lines")
    func attributionAcrossLines() {
        // Each line resumes where the last left off, including mid-fragment.
        var cursor = (run: 0, offset: 0)
        let first = TextRunAttribution.fragments(
            of: "aa", runTexts: ["aaaa", "bb"], cursor: &cursor)
        #expect(first.map(\.run) == [0])
        let second = TextRunAttribution.fragments(
            of: "aabb", runTexts: ["aaaa", "bb"], cursor: &cursor)
        #expect(second.map(\.text) == ["aa", "bb"])
        #expect(second.map(\.run) == [0, 1])
    }

    @Test("Attribution skips the whitespace a wrap dropped")
    func attributionSkipsDroppedWhitespace() {
        // The break ate the space between the words; the cursor has to step
        // over it or every later fragment lands one character out.
        var cursor = (run: 0, offset: 0)
        _ = TextRunAttribution.fragments(of: "aa", runTexts: ["aa bb", "cc"], cursor: &cursor)
        let next = TextRunAttribution.fragments(
            of: "bbcc", runTexts: ["aa bb", "cc"], cursor: &cursor)
        #expect(next.map(\.text) == ["bb", "cc"])
        #expect(next.map(\.run) == [0, 1])
    }

    @Test("Chrome appended past the end of the source survives")
    func attributionKeepsTrailingChrome() {
        // The other insertion branch: here the ellipsis arrives when the source
        // is already spent, so there is no run left to compare against. Dropping
        // it would silently eat the one mark that says the text was cut.
        var cursor = (run: 0, offset: 0)
        let parts = TextRunAttribution.fragments(
            of: "abcd…", runTexts: ["abcd"], cursor: &cursor)
        #expect(parts.map(\.text).joined() == "abcd…")
    }

    @Test("A line that is the runs end to end is answered whole, exactly as the walk answers it")
    func wholeRunsAgreesWithTheWalk() {
        // `fragments` recognises a line that IS the runs from its bytes and
        // skips the walk. Where it does, the fragments AND the cursor it
        // leaves must be the walk's — and where a run edge falls inside a
        // grapheme, it must decline and leave the line to the walk.
        func walked(_ line: String, _ runs: [String]) -> ([String], [Int], Int, Int) {
            var cursor = (run: 0, offset: 0)
            let parts = TextRunAttribution.walkedFragments(of: line, runTexts: runs, cursor: &cursor)
            return (parts.map(\.text), parts.map(\.run), cursor.run, cursor.offset)
        }
        func answered(_ line: String, _ runs: [String]) -> ([String], [Int], Int, Int) {
            var cursor = (run: 0, offset: 0)
            let parts = TextRunAttribution.fragments(of: line, runTexts: runs, cursor: &cursor)
            return (parts.map(\.text), parts.map(\.run), cursor.run, cursor.offset)
        }

        // Edges inside a grapheme: a combining mark opening a run, a Prepend
        // (U+0600) before an ASCII run, a flag's two regional indicators in
        // two runs, a ZWJ sequence split at the joiner, CR | LF.
        for runs in [
            ["e", "\u{301}x"], ["\u{600}", "1"], ["\u{1F1E6}", "\u{1F1FA}"],
            ["\u{1F468}\u{200D}", "\u{1F469}"], ["a\r", "\nb"],
        ] {
            #expect(TextRunAttribution.wholeRuns(of: runs.joined(), runTexts: runs) == nil, "\(runs)")
            #expect(answered(runs.joined(), runs) == walked(runs.joined(), runs), "\(runs)")
        }
        // Not vacuous: the plain case IS answered, empty runs and all.
        #expect(TextRunAttribution.wholeRuns(of: "Ada in active", runTexts: ["", "Ada", "", " in active", ""])?
            .map(\.run) == [1, 3])
        #expect(answered("Ada in active", ["", "Ada", "", " in active", ""]) == walked(
            "Ada in active", ["", "Ada", "", " in active", ""]))

        // Then thousands of random run lists over pieces that make the
        // segmentation interesting either side of an edge — combining marks,
        // regional indicators, ZWJ sequences, a Prepend, a conjunct (GB9c),
        // CR LF, wide text — each against the runs end to end and against
        // lines that are not (a prefix, an ellipsis, an extra space).
        let pieces = [
            "a", "b", " ", "日", "e\u{301}", "\u{301}", "\u{1F1E6}", "\u{1F1FA}", "\u{1F468}",
            "\u{200D}", "\u{1F469}", "\u{600}", "\u{915}", "\u{94D}", "\u{937}", "\r", "\n", "x",
        ]
        var seed: UInt64 = 0x2026_1004
        func rnd(_ n: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(max(1, n)))
        }
        var wholeAnswers = 0
        for _ in 0..<3_000 {
            let runs = (0..<rnd(5)).map { _ in (0..<rnd(4)).map { _ in pieces[rnd(pieces.count)] }.joined() }
            let joined = runs.joined()
            for line in [joined, String(joined.prefix(max(0, joined.count - 1))), joined + "…", " " + joined] {
                if let whole = TextRunAttribution.wholeRuns(of: line, runTexts: runs) {
                    wholeAnswers += 1
                    let walk = walked(line, runs)
                    #expect(whole.map(\.text) == walk.0, "\(runs.map(\.debugDescription)) / \(line.debugDescription)")
                    #expect(whole.map(\.run) == walk.1, "\(runs.map(\.debugDescription)) / \(line.debugDescription)")
                }
                #expect(answered(line, runs) == walked(line, runs), "\(runs.map(\.debugDescription))")
            }
        }
        #expect(wholeAnswers > 1_000, "only \(wholeAnswers) lines took the fast path")
    }

    @Test("Inserted chrome stays with the fragment being cut")
    func attributionKeepsTheEllipsis() {
        // The ellipsis is not in the source; it must not be dropped, and it
        // belongs to whatever was being truncated.
        var cursor = (run: 0, offset: 0)
        let parts = TextRunAttribution.fragments(
            of: "ab…", runTexts: ["abcd", "efgh"], cursor: &cursor)
        #expect(parts.map(\.text).joined() == "ab…")
        #expect(parts.allSatisfy { $0.run == 0 })
    }
}

/// Resync past DROPPED source: a truncation leaves the attribution cursor
/// inside the cut span, and without a forward scan every later character
/// mismatched forever — the rest of the text wore whichever run was current
/// at the desync.
@MainActor
@Suite("Run attribution resyncs past truncation")
struct RunAttributionResyncTests {

    @Test("An over-wide word cut mid-line does not poison the next line")
    func tailCutResyncs() {
        // Line 1 truncates inside "supercalifragilistic"; line 2 must still
        // attribute "OK" to the bold run, not the red one.
        let runs = ["supercalifragilistic done ", "OK"]
        var cursor = (run: 0, offset: 0)
        _ = TextRunAttribution.fragments(of: "supercali…", runTexts: runs, cursor: &cursor)
        let second = TextRunAttribution.fragments(of: "done OK", runTexts: runs, cursor: &cursor)
        #expect(second.count == 2, "\(second)")
        #expect(second.last?.text == "OK")
        #expect(second.last?.run == 1, "OK wore run \(second.last?.run ?? -1)")
    }

    @Test("A head truncation lands the tail in the right run")
    func headCutResyncs() {
        // "…" + the tail of run 1: the ellipsis is chrome (kept with the run
        // in hand); the tail's characters belong to run 1.
        let runs = ["path/to/some/", "filename.txt"]
        var cursor = (run: 0, offset: 0)
        let fragments = TextRunAttribution.fragments(
            of: "…name.txt", runTexts: runs, cursor: &cursor)
        #expect(fragments.last?.run == 1, "\(fragments)")
        #expect(fragments.last?.text.hasSuffix("name.txt") == true, "\(fragments)")
    }
}
