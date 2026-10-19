//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ComplexScriptWidthTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore
import TUIkitTerminalHost
@testable import TUIkitTestSupport
import TUIkitWidthCorpus

// MARK: - Two width rules, one set of scalars

/// The complex-script corpus rows, with **both** of the framework's width rules
/// written down side by side for every one of them.
///
/// ## Why both numbers are pinned rather than compared
///
/// ``Swift/Character/terminalWidth`` answers a multi-scalar cluster with a flat
/// **2** as soon as any scalar past the first adds width. ``Unicode/Scalar/
/// loneTerminalWidth`` — the same file's per-scalar rule, and what the run
/// scanners use for every cluster they can prove standalone — prices each
/// scalar and sums. For all 78 rows the corpus held before 2026-09-04 the two
/// coincide, because an emoji sequence has exactly two advancing scalars and
/// 1 + 1 = 2.
///
/// Unicode 15.1's GB9c broke the coincidence, and Swift 6.2 implements it: a
/// Devanagari conjunct is ONE `Character` however many consonants it stacks, so
/// स्त्र reaches the cluster rule with three advancing scalars and is answered 2
/// where the per-scalar rule says 3. The framework therefore holds two answers
/// for the same text, and which one a caller gets depends only on whether the
/// standard library fused it — nothing about the terminal.
///
/// ## What the hosts measured
///
/// The answer is the host's, not one rule's. Ghostty 1.3.1 with DEC mode 2027
/// set — a host that clusters graphemes — advances every row here by the
/// cluster rule's number, the five disagreements included, on both screens
/// (2026-10-19; its primary screen gave the same on 2026-09-04).
/// ``claimIsGhosttysMeasuredAdvance(row:)`` asserts that from the records.
/// The hosts that advance per code point — Apple Terminal 455.1, iTerm2 3.6.11
/// and Warp v0.2026.09.02, on the primary screen on 2026-09-04 — gave the
/// three conjuncts the per-scalar numbers, and split on the jamo.
///
/// So the claim, which is the cluster rule's on every host, is measured right
/// on a host that clusters graphemes and a cell or two short on those three,
/// and nothing models that yet. The disagreements therefore stay pinned two
/// ways in `withKnownIssue`, which fails if a divergence silently disappears
/// just as loudly as a new one fails ``rulesAgreeExceptWhereRecorded``: a
/// change would be a per-host trait, and what it would rest on — the paint
/// (`landing_probe.py`) on every host, and the advance on the alternate screen
/// of the three per-code-point hosts — is unmeasured. The per-host numbers are
/// in `Documentation/Terminals/Terminal compatibility survey.md`, "Complex
/// scripts".
///
/// - Note: The direction of the error is not the same for every disagreement,
///   which is exactly why "make one rule call the other" is not the fix. For a
///   three-consonant conjunct the cluster rule's 2 is right on a host that
///   clusters graphemes and short on one that advances per code point, which
///   measured 3 (4 for स्त्री). For decomposed Hangul the cluster rule's 2 is
///   what three of the four hosts advance — 한 is two cells however it is
///   spelled — and the per-scalar rule's 3 and 4 are the suspect ones, because
///   it prices the conjoining V and T jamo at 1 each where `wcwidth` gives
///   U+1160…U+11FF zero.
@Suite("Complex script widths")
struct ComplexScriptWidthTests {

    /// One corpus row and the two answers.
    ///
    /// `cluster` and `perScalar` are transcribed, not computed from each other:
    /// a table that derived one from the other could not record a disagreement,
    /// which is the whole point of it. `advancing` is how many of the cluster's
    /// scalars price above zero — the quantity the cluster rule ignores.
    struct Row: Sendable, CustomStringConvertible {
        let id: String
        let cluster: Int
        let perScalar: Int
        let advancing: Int

        var description: String { id }
        /// Whether the two rules answer the same number for this row.
        var rulesAgree: Bool { cluster == perScalar }
    }

    /// Every row added to the corpus on 2026-09-04.
    ///
    /// ``tableCoversEveryComplexScriptRow`` fails if a row is added to one of
    /// these classes and not to this table, so the list cannot silently rot.
    static let rows: [Row] = [
        Row(id: "fullwidth_latin_a", cluster: 2, perScalar: 2, advancing: 1),
        Row(id: "combining_stack", cluster: 1, perScalar: 1, advancing: 1),

        // GB9c fuses these. The first, and the Bengali and Telugu rows, have
        // exactly two advancing scalars and so land on the cluster rule's 2 by
        // coincidence — which is why nothing caught the other three.
        Row(id: "conjunct_deva_ksha", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "conjunct_deva_stra", cluster: 2, perScalar: 3, advancing: 3),
        Row(id: "conjunct_deva_shtra", cluster: 2, perScalar: 3, advancing: 3),
        Row(id: "conjunct_deva_stri", cluster: 2, perScalar: 4, advancing: 4),
        Row(id: "conjunct_bengali_ksha", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "conjunct_telugu_ksha", cluster: 2, perScalar: 2, advancing: 2),

        // The half-forms GB9c does not fuse: virama is `Mn`, so the cluster is
        // its base and both rules say 1.
        Row(id: "virama_tamil_sa", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "virama_kannada_ka", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "virama_khmer_ka", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "matra_deva_i", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_deva_o", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_deva_au", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_deva_i_anusvara", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_tamil_aa", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_khmer_aa", cluster: 2, perScalar: 2, advancing: 2),

        Row(id: "nukta_deva_qa", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "nukta_deva_rra", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "chillu_malayalam_atomic", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "chillu_malayalam_zwj", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "thai_tone", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "thai_vowel_tone", cluster: 1, perScalar: 1, advancing: 1),
        // Sara am is a SPACING vowel, so it is width-adding where the tone
        // marks above are not — 2 from both rules, unlike its neighbours.
        Row(id: "thai_sara_am", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "lao_vowel_tone", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "tibetan_subjoined", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "tibetan_subjoined_vowel", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "arabic_lam_alef", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "arabic_harakat", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "arabic_shadda_harakat", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "hebrew_hiriq", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "hebrew_dagesh_qamats", cluster: 1, perScalar: 1, advancing: 1),

        // The other disagreement, and it points the OTHER way: the L jamo is
        // East-Asian Wide so the per-scalar rule starts at 2 and then charges
        // for the V and T jamo, which `wcwidth` gives zero.
        Row(id: "hangul_jamo_lvt", cluster: 2, perScalar: 4, advancing: 3),
        Row(id: "hangul_jamo_lv", cluster: 2, perScalar: 3, advancing: 2),

        Row(id: "latin_zwj", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "latin_zwnj", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "bidi_lrm", cluster: 0, perScalar: 0, advancing: 0),
        Row(id: "bidi_rlm", cluster: 0, perScalar: 0, advancing: 0),
    ]

    /// The corpus classes ``rows`` is the table for.
    static let classes: Set<String> = [
        "indic_conjunct", "virama_final", "spacing_vowel_sign", "nukta", "chillu",
        "thai_lao", "tibetan_stack", "arabic", "hebrew_points", "hangul_jamo",
        "format_control",
    ]

    /// The two rows added to classes that already existed.
    static let additionsToExistingClasses: Set<String> = ["fullwidth_latin_a", "combining_stack"]

    private static let corpus: [String: TerminalWidthCorpus.Entry] =
        Dictionary(uniqueKeysWithValues: TerminalWidthCorpus.all.map { ($0.id, $0) })

    private static func entry(for row: Row) throws -> TerminalWidthCorpus.Entry {
        try #require(corpus[row.id], "\(row.id) is not in the corpus")
    }

    // MARK: - The premise

    /// The fact everything else rests on. If Swift stopped fusing a conjunct,
    /// `स्त्र` would be three `Character`s of one cell each, the cluster rule
    /// would never see it, and there would be nothing here to disagree about —
    /// so this is checked rather than assumed. (It is also what makes
    /// ``TerminalWidthCorpus/Entry/character`` safe: that initialiser traps on
    /// anything but exactly one cluster.)
    @Test("Every complex-script row is exactly one grapheme cluster", arguments: rows)
    func rowIsOneCluster(row: Row) throws {
        let entry = try Self.entry(for: row)
        #expect(
            entry.text.count == 1,
            "\(row.id) (\(entry.codepoints)) segments into \(entry.text.count) clusters")
    }

    // MARK: - What each rule claims today

    /// Traits are pinned to ``TerminalWidthTraits/composing`` throughout: the
    /// widening arms only fire for clusters carrying a joiner or a Fitzpatrick
    /// modifier, but pinning makes these numbers independent of whatever host
    /// the tests happen to run under.
    @Test("The cluster rule claims what is recorded here", arguments: rows)
    func clusterRuleClaim(row: Row) throws {
        let entry = try Self.entry(for: row)
        TerminalWidthTraits.withTraits(.composing) {
            #expect(
                entry.character.terminalWidth == row.cluster,
                """
                \(row.id) (\(entry.codepoints)): the cluster rule now says \
                \(entry.character.terminalWidth), recorded \(row.cluster)
                """)
        }
    }

    @Test("The per-scalar rule sums to what is recorded here", arguments: rows)
    func perScalarRuleSum(row: Row) throws {
        let entry = try Self.entry(for: row)
        TerminalWidthTraits.withTraits(.composing) {
            let sum = entry.text.unicodeScalars.reduce(0) { $0 + $1.loneTerminalWidth }
            let advancing = entry.text.unicodeScalars.count { $0.loneTerminalWidth > 0 }
            #expect(
                sum == row.perScalar,
                """
                \(row.id) (\(entry.codepoints)): the per-scalar rule now sums to \(sum), \
                recorded \(row.perScalar)
                """)
            #expect(
                advancing == row.advancing,
                "\(row.id): \(advancing) scalars advance, recorded \(row.advancing)")
        }
    }

    // MARK: - Where they disagree

    /// The assertion the finding is about, run for every row and expected to
    /// fail for exactly the five recorded in ``rows``.
    ///
    /// A `withKnownIssue` fails when the issue does NOT occur, so this is a
    /// two-way pin: a sixth divergence fails here, and any of the five quietly
    /// resolving fails here too. The hosts measured say 2 and 3 (and 2 and 4)
    /// are each right somewhere — 2 where graphemes are clustered, the
    /// per-scalar number for a conjunct where they are not — so neither rule
    /// may simply become the other (the suite's "What the hosts measured").
    @Test("The cluster rule and the per-scalar rule agree, except where recorded",
          arguments: rows)
    func rulesAgreeExceptWhereRecorded(row: Row) throws {
        let entry = try Self.entry(for: row)
        TerminalWidthTraits.withTraits(.composing) {
            withKnownIssue(
                """
                \(row.id) (\(entry.codepoints)): the cluster rule says \(row.cluster), \
                the per-scalar rule \(row.perScalar). Measured: a host that clusters \
                graphemes (Ghostty 1.3.1, mode 2027 set) advances the cluster rule's \
                number on both screens (claimIsGhosttysMeasuredAdvance); the hosts that \
                advance per code point gave the conjuncts the per-scalar number on the \
                primary screen. Still unmeasured: the paint (`landing_probe.py` + \
                `landing_analyze.py`) on every host, and those hosts' alternate screen. \
                Change a rule only as a per-host trait, from both — see "Complex scripts" \
                in Documentation/Terminals/Terminal compatibility survey.md.
                """,
                isIntermittent: false
            ) {
                #expect(entry.character.terminalWidth == row.perScalar)
            } when: {
                !row.rulesAgree
            }
        }
    }

    // MARK: - What a host that clusters graphemes measured

    /// Ghostty's advance records, one per screen, read rather than restated:
    /// a re-run on a new version updates the assertion instead of dating it.
    private static let ghosttyRecords: [(file: String, record: AdvanceRecord)] = {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TUIkitAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Tools/TerminalProbes/data")
        return ["ghostty-1.3.1-advance.json", "ghostty-1.3.1-alternate.json"].map { file in
            let url = directory.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url),
                let record = try? JSONDecoder().decode(AdvanceRecord.self, from: data)
            else {
                // A missing record is not a skipped test: "not measured" must
                // not look like "measured and fine".
                fatalError("Cannot read the advance record \(url.path)")
            }
            return (file, record)
        }
    }()

    /// The part of the question a measurement has settled: on a host that
    /// clusters graphemes, the claim is what the terminal advances, for every
    /// row — the five where the two rules disagree included, each of which
    /// Ghostty advanced by the cluster rule's number.
    ///
    /// Only with mode 2027 set: reset, Ghostty advances per code point and
    /// moves six of eleven emoji classes (the survey's "Ghostty's model is
    /// conditional on mode 2027"), so a record taken that way would be asking
    /// another question, and fails here instead of being read as this one.
    /// Asked under Ghostty's own traits, the claim its users get.
    @Test("On a host that clusters graphemes, the claim is the measured advance", arguments: rows)
    func claimIsGhosttysMeasuredAdvance(row: Row) throws {
        let entry = try Self.entry(for: row)
        let claim = TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .ghostty)) {
            entry.character.terminalWidth
        }
        for (file, record) in Self.ghosttyRecords {
            #expect(
                record.stamp.graphemeClustering == "set",
                "\(file) was taken with mode 2027 \(record.stamp.graphemeClustering ?? "unread")")
            let measured = try #require(
                record.advances[row.id]?.advance, "\(file) has no advance for \(row.id)")
            #expect(
                claim == measured,
                """
                \(row.id) (\(entry.codepoints)): claimed \(claim), Ghostty advanced \(measured) \
                on the \(record.stamp.screen) screen (\(file))
                """)
        }
    }

    // MARK: - The rows' paint is known to be unmeasured

    /// Until a landing record measures a row, its absence must be recorded
    /// rather than invisible — otherwise "no landing record has it" reads
    /// exactly like "every model passes", which is the failure mode
    /// ``TerminalLedgerConformanceTests/awaitingLandingMeasurement`` exists to
    /// prevent. This is the other end of that: a row this suite reasons about
    /// is either measured somewhere or listed there. (Its advance is in the
    /// advance records, and ``claimIsGhosttysMeasuredAdvance(row:)`` reads
    /// Ghostty's; a landing record adds the paint.)
    @Test("Every complex-script row is measured, or recorded as awaiting measurement",
          arguments: rows)
    func rowIsMeasuredOrRecordedAsAwaiting(row: Row) {
        let measured = TerminalLedgerConformanceTests.ledgers.contains {
            $0.measurements[row.id] != nil
        }
        #expect(
            measured
                || TerminalLedgerConformanceTests.awaitingLandingMeasurement.contains(row.id),
            "\(row.id): no host has measured it and it is not recorded as awaiting measurement")
    }

    // MARK: - The table cannot rot

    @Test("Every corpus row in a complex-script class is in this table")
    func tableCoversEveryComplexScriptRow() {
        let tabled = Set(Self.rows.map(\.id))
        for entry in TerminalWidthCorpus.all
        where Self.classes.contains(entry.category) || Self.additionsToExistingClasses.contains(entry.id) {
            #expect(tabled.contains(entry.id), "\(entry.id) is in the corpus but not in this table")
        }
        for id in tabled where Self.corpus[id] == nil {
            Issue.record("\(id) is in this table but no longer in the corpus")
        }
    }

    // MARK: - The clusters that are NOT one cluster

    /// The conjuncts GB9c leaves alone, and the lam-alef a keyboard produces.
    ///
    /// These read as one unit to anyone who reads the script and are two
    /// `Character`s to Swift, which is why the corpus holds their halves
    /// instead: GB9c's `InCB=Linker` property is defined for six scripts, and
    /// Tamil, Kannada and Khmer are not among them. Pinned because the whole
    /// shape of a width bug in this text depends on which it is — a shear once
    /// per conjunct, or once per half.
    @Test("A conjunct outside GB9c's linker set is two clusters, not one",
          arguments: [
            ("tamil_ksha", "\u{B95}\u{BCD}\u{BB7}", 2, 2),
            ("tamil_shri", "\u{BB8}\u{BCD}\u{BB0}\u{BC0}", 2, 2),
            ("kannada_ksha", "\u{C95}\u{CCD}\u{CB7}", 2, 2),
            ("khmer_kaka", "\u{1780}\u{17D2}\u{1780}", 2, 2),
            ("arabic_lam_alef_spelled", "\u{644}\u{627}", 2, 2),
          ])
    func outsideTheLinkerSet(name: String, text: String, clusters: Int, width: Int) {
        TerminalWidthTraits.withTraits(.composing) {
            #expect(text.count == clusters, "\(name): \(text.count) clusters")
            #expect(text.strippedLength == width, "\(name): \(text.strippedLength) cells")
        }
    }

    // MARK: - What it costs a whole word

    /// The divergence at the scale it is actually seen: `राष्ट्र` is two clusters
    /// — `रा` (base + matra, both rules 2) and `ष्ट्र` (three consonants, cluster
    /// rule 2, per-scalar 3) — so the word claims four cells while its scalars
    /// price five.
    ///
    /// Which number is right is the host's: `conjunct_deva_shtra` advanced 2
    /// on Ghostty with mode 2027 set (both screens, 2026-10-19) and 3 on the
    /// three hosts that advance per code point (primary screen, 2026-09-04).
    /// `रा` is no corpus row, so the word itself is unmeasured. Every column
    /// after this word on a row is placed by the claim, so on a host whose
    /// advance is wider it shears the rest of the row by one cell per such
    /// cluster and clips a truncation one cell late.
    @Test("A word of two conjunct clusters carries the divergence")
    func wordCarriesTheDivergence() {
        let word = "\u{930}\u{93E}\u{937}\u{94D}\u{91F}\u{94D}\u{930}"  // राष्ट्र
        TerminalWidthTraits.withTraits(.composing) {
            #expect(word.count == 2)
            let perScalar = word.unicodeScalars.reduce(0) { $0 + $1.loneTerminalWidth }
            #expect(perScalar == 5)
            withKnownIssue(
                """
                राष्ट्र claims 4 cells (रा 2 + ष्ट्र 2) against a per-scalar 5. \
                `conjunct_deva_shtra` is measured: Ghostty 1.3.1 with mode 2027 set \
                advances it 2, the hosts that advance per code point 3 (primary screen \
                only). The paint is unmeasured on every host; change either number \
                only as a per-host trait.
                """,
                isIntermittent: false
            ) {
                #expect(word.strippedLength == perScalar)
            }
            #expect(word.strippedLength == 4, "the claim the layout uses today")
        }
    }
}

// MARK: - Reading an advance record

/// As much of an `advance_probe.py` record as ``ComplexScriptWidthTests``
/// reads. At file scope rather than inside the suite, which would nest its
/// coding keys one level deeper than the project allows.
private struct AdvanceRecord: Decodable {
    struct Stamp: Decodable {
        let screen: String
        /// What DECRQM said of mode 2027 before the run: `set`, `reset`, or why
        /// it was not asked.
        let graphemeClustering: String?

        enum CodingKeys: String, CodingKey {
            case screen
            case graphemeClustering = "mode_2027_grapheme_clustering"
        }
    }

    struct Advance: Decodable { let advance: Int }

    let stamp: Stamp
    let advances: [String: Advance]
}
