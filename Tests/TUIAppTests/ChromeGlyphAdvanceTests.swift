//  🖥️ TUI — A Terminal UI framework for Swift
//  ChromeGlyphAdvanceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore  // `isOverhangingChromeGlyph` — internal to the width layer
@testable import TUIFoundation
@testable import TUITestSupport

/// The framework's own chrome, against what four terminals actually did with it.
///
/// Every glyph TUI draws in a status bar, a border, a scrollbar, a track, a
/// radio group or a stepper is claimed at one cell — and until 2026-09-04 that
/// claim had never been checked on any host. Fifteen of the twenty-nine are East
/// Asian **Ambiguous**, whose width is a terminal SETTING rather than a property
/// of the character, so the claim was not obviously safe; and `↵` (U+21B5) was
/// reported painting two cells in Ghostty despite being EAW *Neutral*, which no
/// width table predicts.
///
/// Measured: **all twenty-nine advance exactly one cell on all four hosts.** No
/// row shifts anywhere. Whatever Ghostty does with `↵` it does to the INK
/// alone, which is a different measurement — read from the overhang card on
/// 2026-09-04 (`ChromeOverhangTests`), and the reason the claim asserted here
/// is now the claim of the host whose record is being read rather than one
/// number for all four.
///
/// This reads the `advance_probe.py` records rather than restating their
/// numbers, so re-running the probe on a new version of a host updates the test
/// rather than dating it.
///
/// It reads each host's ALTERNATE-screen record, the screen every TUI app
/// draws on: the 2026-10-19 runs, the first to read every chrome row on all
/// four hosts (the keyboard symbols of 2026-10-05, the drop badges of
/// 2026-10-13 and the button faces' glyphs of 2026-10-15 had waited in
/// ``awaitingAdvanceMeasurement`` until then). Apple Terminal's primary-screen
/// record is older than all three.
@Suite("Chrome glyph advance")
struct ChromeGlyphAdvanceTests {

    private struct Advance: Decodable { let advance: Int }
    private struct Record: Decodable { let advances: [String: Advance] }

    /// The chrome classes, which is what this suite is about — the rest of the
    /// corpus is measured by `TerminalLedgerConformanceTests` against the
    /// richer landing records.
    private static let chromeClasses: Set<String> = ["chrome_key", "chrome_glyph"]

    /// The program is carried alongside the record because the CLAIM is per
    /// host now: since 2026-09-04 the overhang card's reading widens `↵` on
    /// Ghostty and seven other glyphs on Warp, so "what does the framework
    /// claim for this row" cannot be asked without saying whose terminal.
    private static let hosts: [(name: String, file: String, program: TerminalClient.Program)] = [
        ("Ghostty", "ghostty-1.3.1-alternate.json", .ghostty),
        ("iTerm2", "iterm2-3.7.6-alternate.json", .iTerm2),
        ("Apple Terminal", "apple-terminal-455.1-alternate.json", .appleTerminal),
        ("Warp", "warpterminal-v0.2026.09.30.08.29.stable_01-alternate.json", .warp),
        ("GNOME Terminal", "gnome-terminal-3.56.2-alternate.json", .gnomeTerminal),
    ]

    private typealias HostRecord = (
        name: String, program: TerminalClient.Program, advances: [String: Advance]
    )

    private static let records: [HostRecord] = {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TUIAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Tools/TerminalProbes/data")
        return hosts.map { host in
            let url = directory.appendingPathComponent(host.file)
            guard let data = try? Data(contentsOf: url),
                let record = try? JSONDecoder().decode(Record.self, from: data)
            else {
                // Same rule as the landing ledgers: a missing record is not a
                // skipped test, because "not measured" must not look like
                // "measured and fine".
                fatalError("Cannot read the advance record \(url.path)")
            }
            return (host.name, host.program, record.advances)
        }
    }()

    private static let chromeRows = WidthCorpus.clusters.filter { chromeClasses.contains($0.category) }

    /// The chrome rows a host's record does not have yet, host by host: a row
    /// whose advance no probe has taken is named here, and a row named here
    /// that the record now has fails until it is removed — the rule
    /// `TerminalLedgerConformanceTests.awaitingLandingMeasurement` follows.
    /// Per host because a re-run is.
    ///
    /// The four three-quadrant glyphs of a solid face and a Braille border's
    /// glyphs joined on 2026-10-19. A DSR probe of their own read them at one
    /// cell on all four hosts (the survey's "Braille borders and faces"), but
    /// no `advance_probe.py` record has them, so they wait on every host. So
    /// does the search field's clear button, `✗`, which joined the same day,
    /// and a file panel's enclosing-folder button, `↰`, and a switch's `○ ⦗ ⦘`
    /// under Lines, which joined on 2026-10-24.
    private static let awaitingAdvanceMeasurement: [TerminalClient.Program: Set<String>] = {
        let solidAndBraille = Set(
            WidthCorpus.clusters.map(\.id).filter {
                $0.hasPrefix("chrome_quadrant_not_") || $0.hasPrefix("chrome_braille_")
                    || $0 == "chrome_cross" || $0 == "chrome_enclosing_folder" || $0.hasPrefix("chrome_switch_")
            })
        return [
            .ghostty: solidAndBraille, .iTerm2: solidAndBraille,
            .appleTerminal: solidAndBraille, .warp: solidAndBraille,
            // Its record (3.56.2) has every row but the clear button, the
            // enclosing-folder button and the switch's glyphs, which joined
            // after that probe run.
            .gnomeTerminal: [
                "chrome_cross", "chrome_enclosing_folder", "chrome_switch_knob_off", "chrome_switch_cap_open",
                "chrome_switch_cap_close",
            ],
        ]
    }()

    @Test("Every chrome glyph is a corpus row of one of the two chrome classes")
    func theSuiteHasSomethingToMeasure() {
        #expect(Self.chromeRows.count == 66, "\(Self.chromeRows.count) chrome rows")
    }

    /// The probes measure the corpus and nothing else (`advance_probe.py`'s
    /// battery and `overhang_card.py` both draw its chrome rows), so a symbol
    /// the formatter draws with no row is one no probe can be pointed at.
    /// That is how `↩ ↖ ↘ ⇞ ⇟` shipped on 2026-10-05: drawn everywhere, and
    /// measurable only by hand.
    @Test("Every key symbol the framework draws is a keyboard-symbol row the probes measure")
    func everyDrawnKeySymbolIsACorpusRow() {
        let keys: [Key] = [
            .escape, .enter, .tab, .backspace, .delete,
            .up, .down, .left, .right, .home, .end, .pageUp, .pageDown,
        ]
        let modifiers: [EventModifiers] = [.control, .option, .shift, .command]
        let drawn = keys.map(KeySymbols.key) + modifiers.map(KeySymbols.modifiers)
        let rows = Set(WidthCorpus.clusters(in: "chrome_key").map(\.text))
        for symbol in drawn {
            #expect(rows.contains(symbol), "\(symbol) is drawn, and no chrome_key row measures it")
        }
    }

    @Test("Every host advances one cell for every chrome glyph")
    func chromeAdvancesOneCellEverywhere() {
        for host in Self.records {
            let awaiting = Self.awaitingAdvanceMeasurement[host.program] ?? []
            for id in awaiting where host.advances[id] != nil {
                Issue.record("\(host.name)/\(id) is measured now — remove it from awaitingAdvanceMeasurement")
            }
            for row in Self.chromeRows {
                guard let measured = host.advances[row.id] else {
                    if !awaiting.contains(row.id) {
                        Issue.record("\(host.name)/\(row.id): the probe recorded no advance")
                    }
                    continue
                }
                #expect(
                    measured.advance == 1,
                    "\(host.name)/\(row.id) \(row.text) advanced \(measured.advance)")
            }
        }
    }

    @Test("The framework claims what the terminals do, unless that host's ink says otherwise")
    func theClaimCoversTheMeasurement() {
        for host in Self.records {
            // Under THIS host's claims, because since 2026-09-04 they differ:
            // a glyph in the overhang tables (`ChromeOverhang.swift`) claims
            // the two cells its ink covers on the host that was measured to
            // smear it, while every host still advances it one. Asking the
            // question under the default traits — which is what this test did
            // when the table was empty and host-independent — would assert the
            // claim of a host that is not the one whose record it is reading.
            TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: host.program)) {
                for row in Self.chromeRows {
                    let character = Character(row.text)
                    let claimed = character.terminalWidth
                    guard let measured = host.advances[row.id] else { continue }
                    // The shortfall on a smeared row is what the ECH+CUF walk
                    // exists to close, and `ChromeOverhangTests` is where that
                    // pair is checked. For every other row the two must still
                    // be equal: an unexplained gap is the shear this suite was
                    // written to catch.
                    #expect(
                        claimed >= measured.advance,
                        "\(row.id) \(row.text): claimed \(claimed), \(host.name) advanced \(measured.advance)")
                    if !character.isOverhangingChromeGlyph {
                        #expect(
                            claimed == measured.advance,
                            "\(row.id) \(row.text): claimed \(claimed), \(host.name) advanced \(measured.advance)")
                    }
                }
            }
        }
    }
}
