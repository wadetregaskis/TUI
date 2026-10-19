//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ComplexScriptHostAdvanceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitTerminalHost
@testable import TUIkitTestSupport
import TUIkitWidthCorpus

// MARK: - Each host's claim, against what that host advanced

/// The complex-script rows' claim on each host, against the advance that host
/// was measured to make — the half of ``ComplexScriptWidthTests`` that reads
/// the terminals rather than the two rules.
///
/// ## Why the claim differs by host
///
/// A Devanagari conjunct is one grapheme cluster, and the hosts disagree about
/// what to do with it. Ghostty 1.3.1 with DEC mode 2027 set — a host that
/// clusters graphemes — advances स्त्र 2 cells. Apple Terminal 455.1, iTerm2
/// 3.7.6 and Warp v0.2026.09.30 advance it 3, one cell per consonant, and
/// स्त्री 4. So ``TerminalWidthTraits/textClusters`` is per host, and each host's
/// claim is asserted here against that host's own records, on every screen
/// they hold, rather than one number against all four.
///
/// The records are read, not restated: re-running the probe on a new version
/// and pointing ``hosts`` at the new files updates the assertion instead of
/// dating it.
///
/// ## What this does not measure
///
/// The ADVANCE is DSR: where the next character goes, and when the row wraps.
/// Where the glyph's ink lands inside the cells it advances is the paint, and
/// it is measured for none of these rows on any host — every one is listed in
/// `TerminalLedgerConformanceTests.awaitingLandingMeasurement`, which
/// ``ComplexScriptWidthTests/rowIsMeasuredOrRecordedAsAwaiting(row:)`` holds
/// to, so a claim that matches the advance cannot read as a row that is known
/// to render right.
@Suite("Complex script widths on each host")
struct ComplexScriptHostAdvanceTests {

    /// A host, and its current version's advance records — one per screen
    /// that version was measured on.
    struct Host: Sendable, CustomStringConvertible {
        let program: TerminalClient.Program
        let files: [String]
        var description: String { program.rawValue }
    }

    /// Every host with a record that carries the complex-script rows.
    ///
    /// Apple Terminal's primary-screen record is 2026-09-04's; its re-run of
    /// 2026-10-19 reproduced it row for row, as the alternate-screen record of
    /// that day did the 2026-08-28 one it replaced.
    static let hosts: [Host] = [
        Host(program: .ghostty, files: ["ghostty-1.3.1-advance.json", "ghostty-1.3.1-alternate.json"]),
        Host(
            program: .appleTerminal,
            files: ["Apple-Terminal-advance.json", "apple-terminal-455.1-alternate.json"]),
        Host(program: .iTerm2, files: ["iterm2-3.7.6-advance.json", "iterm2-3.7.6-alternate.json"]),
        Host(
            program: .warp,
            files: [
                "warpterminal-v0.2026.09.30.08.29.stable_01-advance.json",
                "warpterminal-v0.2026.09.30.08.29.stable_01-alternate.json",
            ]),
        Host(program: .tmux, files: ["tmux-3.7c-advance.json", "tmux-3.7c-alternate.json"]),
    ]

    /// Where a host's advance and its claim are measured to differ and nothing
    /// models it — recorded rather than excluded, so the debt is visible and a
    /// new divergence still fails. Each is the same on every screen measured.
    ///
    /// - Apple Terminal advances a ZWJ, a ZWNJ, an LRM and an RLM a cell
    ///   each, where the claim counts none: `a‍` and `a‌` are 2, the bare
    ///   marks 1, and ന്‍ (a chillu spelled with a ZWJ) 2.
    /// - Warp advances ரா 1: it gives the Tamil vowel sign U+0BBE no cell,
    ///   while it gives the Devanagari ी U+0940 one.
    /// - tmux 3.7c advances per code point, but by a table that gives every
    ///   spacing vowel sign (`Mc`) no cell: the six matra rows are 1 where
    ///   the claim is 2, and the conjuncts are 3, 3 and 3 — स्त्री's ी adding
    ///   nothing. Its traits keep the cluster rule; see `TerminalClient`'s
    ///   `.tmux` arm for why a per-code-point claim is not the fix there.
    static let knownDivergences: Set<String> = [
        "appleTerminal/latin_zwj", "appleTerminal/latin_zwnj",
        "appleTerminal/bidi_lrm", "appleTerminal/bidi_rlm",
        "appleTerminal/chillu_malayalam_zwj",
        "warp/matra_tamil_aa",
        "tmux/matra_deva_i", "tmux/matra_deva_o", "tmux/matra_deva_au",
        "tmux/matra_deva_i_anusvara", "tmux/matra_tamil_aa", "tmux/matra_khmer_aa",
        "tmux/conjunct_deva_stra", "tmux/conjunct_deva_shtra", "tmux/conjunct_deva_stri",
    ]

    private static let corpus: [String: TerminalWidthCorpus.Entry] =
        Dictionary(uniqueKeysWithValues: TerminalWidthCorpus.all.map { ($0.id, $0) })

    // MARK: - The claim is the advance

    /// Asked under the host's own traits — the claim its users get — for
    /// every complex-script row, on every screen the host's records hold.
    @Test(
        "Each host's claim for a complex-script row is the advance it measured",
        arguments: hosts, ComplexScriptWidthTests.rows)
    func claimIsTheHostsMeasuredAdvance(host: Host, row: ComplexScriptWidthTests.Row) throws {
        let entry = try #require(Self.corpus[row.id], "\(row.id) is not in the corpus")
        let claim = TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: host.program)) {
            entry.character.terminalWidth
        }
        for (file, record) in try AdvanceRecord.load(host.files) {
            let measured = try #require(
                record.advances[row.id]?.advance, "\(file) has no advance for \(row.id)")
            withKnownIssue(
                "\(host)/\(row.id) is a recorded divergence", isIntermittent: false
            ) {
                #expect(
                    claim == measured,
                    """
                    \(row.id) (\(entry.codepoints)): claimed \(claim) on \(host), which \
                    advanced \(measured) on the \(record.stamp.screen) screen (\(file))
                    """)
            } when: {
                Self.knownDivergences.contains("\(host)/\(row.id)")
            }
        }
    }

    /// Only with mode 2027 set: reset, Ghostty advances per code point and
    /// moves six of eleven emoji classes (the survey's "Ghostty's model is
    /// conditional on mode 2027"), so a record taken that way would be asking
    /// another question, and fails here instead of being read as this one.
    /// TUIkit sets the mode on Ghostty at startup when it is off.
    @Test("Ghostty's records were taken with grapheme clustering on")
    func ghosttyRecordsClusterGraphemes() throws {
        let ghostty = try #require(Self.hosts.first { $0.program == .ghostty })
        for (file, record) in try AdvanceRecord.load(ghostty.files) {
            #expect(
                record.stamp.graphemeClustering == "set",
                "\(file) was taken with mode 2027 \(record.stamp.graphemeClustering ?? "unread")")
        }
    }

    /// The divergence table cannot outlive its rows: an entry for a row or a
    /// host that is not asked about any more fails here.
    @Test("Every recorded divergence names a host and a row this suite asks about")
    func divergencesNameRealRows() {
        let rows = Set(ComplexScriptWidthTests.rows.map(\.id))
        let programs = Set(Self.hosts.map(\.program.rawValue))
        for key in Self.knownDivergences {
            let parts = key.split(separator: "/").map(String.init)
            #expect(
                parts.count == 2 && programs.contains(parts[0]) && rows.contains(parts[1]),
                "\(key) names no host and row this suite asks about")
        }
    }

    // MARK: - The trait leaves emoji alone

    /// ``TerminalWidthTraits/textClusters`` is about TEXT: every emoji cluster
    /// has measured rules of its own (``TerminalWidthTraits/ZWJSequences``,
    /// ``TerminalWidthTraits/SkinTone``), and a per-code-point sum would
    /// re-price them. So, on every host, flipping the trait must leave every
    /// corpus cluster outside the complex-script classes exactly as claimed.
    @Test(
        "The text-cluster trait changes no claim outside the complex-script rows",
        arguments: TerminalClient.Program.allCases)
    func emojiClaimsIgnoreTheTrait(program: TerminalClient.Program) {
        let complex = Set(ComplexScriptWidthTests.rows.map(\.id))
        var clustered = TerminalClient.widthTraits(of: program)
        clustered.textClusters = .clustered
        var perCodePoint = clustered
        perCodePoint.textClusters = .perCodePoint
        for entry in TerminalWidthCorpus.all where !complex.contains(entry.id) {
            let asCluster = TerminalWidthTraits.withTraits(clustered) { entry.character.terminalWidth }
            let perPoint = TerminalWidthTraits.withTraits(perCodePoint) { entry.character.terminalWidth }
            #expect(
                asCluster == perPoint,
                "\(program.rawValue)/\(entry.id) (\(entry.codepoints)): \(asCluster) clustered, \(perPoint) per code point")
        }
    }

    /// A flag carrying a Fitzpatrick modifier is ONE cluster — the modifier is
    /// `Extend` — and an emoji one, so the skin-tone rule prices it, as it did
    /// before the text-cluster trait existed: the flag's 2 and the swatch's 2
    /// on a host that detaches every swatch (Warp), and the composed 2 where
    /// the rule wants a modifier base (Apple Terminal's separation), a BMP base
    /// (iTerm2, tmux) or nothing (merging hosts). The shortcut that answers a
    /// PLAIN regional-indicator pair before reading the traits once caught
    /// these first and claimed 2 on Warp too — an emoji claim moved by a change
    /// that was only about text, and one the trait flip above cannot see, since
    /// the shortcut does not read the trait and the corpus has no toned flag.
    /// No host's advance over a toned flag is measured; this pins the rule,
    /// not a record.
    @Test(
        "A toned flag is priced by the skin-tone rule, not cut to a flag's two",
        arguments: TerminalClient.Program.allCases)
    func tonedFlagKeepsTheSkinToneRule(program: TerminalClient.Program) throws {
        let traits = TerminalClient.widthTraits(of: program)
        let expected = traits.skinTone == .detached ? 4 : 2
        // 🇺🇸 + 🏽, and a lone 🇦 + 🏽 (a lone indicator is two cells too).
        for text in ["\u{1F1FA}\u{1F1F8}\u{1F3FD}", "\u{1F1E6}\u{1F3FD}"] {
            try #require(text.count == 1, "one grapheme cluster")
            let character = Character(text)
            let claim = TerminalWidthTraits.withTraits(traits) { character.terminalWidth }
            #expect(
                claim == expected,
                "\(program.rawValue) \(text.unicodeScalars.map { String($0.value, radix: 16) }): \(claim)")
        }
    }
}

// MARK: - A border after a conjunct

/// The finding at the scale it is seen: a bordered row of text carrying the
/// five clusters the two width rules disagree about, laid out under a host's
/// traits, emitted through that host's output walk, and then advanced the way
/// the host was MEASURED to advance it — so the right border lands where the
/// host puts it, not where TUIkit's own model says it does.
///
/// With a claim of 2 for each conjunct, the layout put the border at one
/// column and Apple Terminal, iTerm2 and Warp drew it four columns further
/// right — 1 + 1 + 2 cells the claim left out — sheared off its row.
@Suite("A border after a complex-script cluster")
@MainActor
struct ComplexScriptBorderTests {

    /// The five disagreement rows, which are the clusters whose claim moved.
    private static let disagreements = ComplexScriptWidthTests.rows.filter { !$0.rulesAgree }

    @Test(
        "A border after the disagreement rows lands where the host's cursor does",
        arguments: ComplexScriptHostAdvanceTests.hosts)
    func borderLandsWhereTheHostPutsIt(host: ComplexScriptHostAdvanceTests.Host) throws {
        let texts = try Self.disagreements.map { row in
            try #require(
                TerminalWidthCorpus.all.first { $0.id == row.id }?.text, "\(row.id) not in the corpus")
        }
        // The host's name leads the text so each case measures a string no
        // other case does: the wrap memo is process-wide and does not see a
        // task-local traits pin.
        let text = "\(host): " + texts.joined(separator: ", ") + " end"
        let traits = TerminalClient.widthTraits(of: host.program)
        let row = try TerminalWidthTraits.withTraits(traits) {
            let buffer = renderToBuffer(
                Text(verbatim: text).border(), context: makeBareRenderContext(width: 80))
            return try #require(buffer.lines.first { $0.contains("\(host):") })
        }
        // The alternate screen's record, because that is the screen an app
        // draws on.
        let records = try AdvanceRecord.load(host.files)
        let record = try #require(records.first { $0.record.stamp.screen == "alternate" })
        let measured = record.record.advanceByCluster

        TerminalWidthTraits.withTraits(traits) {
            let emitted = TerminalClient.compensating(row, for: host.program)
            guard let rowBorder = row.lastIndex(of: "│"), let emittedBorder = emitted.lastIndex(of: "│")
            else {
                Issue.record("\(host): no right border in \(row.debugDescription)")
                return
            }
            let laidOut = String(row[..<rowBorder]).strippedLength
            #expect(laidOut + 1 == row.strippedLength, "\(host): the border is not the row's last cell")
            let landed = String(emitted[..<emittedBorder]).cursorAdvance { character in
                if let advance = measured[String(character)] { return advance }
                // Everything else on the row is printable ASCII, one cell by
                // definition; anything that is not would need a record.
                #expect(character.isASCII, "\(host): \(character) has no measured advance")
                return 1
            }
            withKnownIssue(
                "\(host) is recorded as advancing these clusters differently from its claim",
                isIntermittent: false
            ) {
                #expect(
                    landed == laidOut,
                    "\(host): the layout put the right border at column \(laidOut), the host draws it at \(landed)")
            } when: {
                Self.disagreements.contains {
                    ComplexScriptHostAdvanceTests.knownDivergences.contains("\(host)/\($0.id)")
                }
            }
        }
    }
}

// MARK: - Reading an advance record

/// As much of an `advance_probe.py` record as the complex-script suites read.
/// At file scope rather than inside a suite, which would nest its coding keys
/// one level deeper than the project allows.
struct AdvanceRecord: Decodable, Sendable {
    struct Stamp: Decodable, Sendable {
        let screen: String
        /// What DECRQM said of mode 2027 before the run: `set`, `reset`, or why
        /// it was not asked.
        let graphemeClustering: String?

        enum CodingKeys: String, CodingKey {
            case screen
            case graphemeClustering = "mode_2027_grapheme_clustering"
        }
    }

    struct Advance: Decodable, Sendable {
        /// The cluster as the probe wrote it: `U+0938 U+094D …`.
        let cluster: String
        let advance: Int
    }

    let stamp: Stamp
    let advances: [String: Advance]

    /// Each row's advance keyed by the cluster's own text, for walking a
    /// string the way the host was measured to.
    var advanceByCluster: [String: Int] {
        var table: [String: Int] = [:]
        for advance in advances.values {
            var text = ""
            for token in advance.cluster.split(separator: " ") {
                guard let value = UInt32(token.dropFirst(2), radix: 16),
                    let scalar = Unicode.Scalar(value)
                else { continue }
                text.unicodeScalars.append(scalar)
            }
            table[text] = advance.advance
        }
        return table
    }

    /// The named records under `Tools/TerminalProbes/data/`. A missing or
    /// unreadable one throws: "not measured" must not look like "measured
    /// and fine".
    static func load(_ files: [String]) throws -> [(file: String, record: Self)] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TUIkitAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Tools/TerminalProbes/data")
        return try files.map { file in
            let data = try Data(contentsOf: directory.appendingPathComponent(file))
            return (file, try JSONDecoder().decode(Self.self, from: data))
        }
    }
}
