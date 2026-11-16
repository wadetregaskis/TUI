//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseMatrix.swift
//
//  The `cases` matrix scenario: every perf case's page as a variant, at rest.
//  So the cases are in `--variants`, `--selfcheck` renders and memo-verifies
//  each page, and `--bench --scenario cases --variant <id>` (`sweep.py
//  --cases`) times one as the other scenarios are timed (design,
//  B-PERFCASE-3). Its script is the session's, `case:<id>` (`CaseSession`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// The perf cases, a variant each.
///
/// One registered scenario with one translated title, and no string per case
/// (B-PERFCASE-5): a variant's summary is its table line's columns, which
/// `--variants` prints, as every variant's summary is printed, in English.
@MainActor
enum CaseMatrix {
    static let scenarioID = "cases"

    static let descriptor = Scenario(
        id: scenarioID,
        title: "Perf Cases",
        blurb: "Every perf case's page at rest, one variant each; their scripts play as sessions.",
        stresses: "whatever each case is written to ask · lists, tables, tabs, splits, editors, conversations",
        make: { config in
            ScenarioVariants.resolve(config, in: scenarioID)?.make(config)
                ?? AnyView(Text(verbatim: "no perf cases: the case tables have mistakes (Stress --cases)"))
        }
    )

    /// A variant per case, in table order, grouped by the table it is in
    /// (`Tables/Lists.swift` is `lists`). An adopted case has none: its page
    /// is its scenario's, already a variant or a scenario of its own.
    ///
    /// The page is drawn at the bench's size, not the case's, as every
    /// variant is: `--cols` and `--rows` are the sweep's to choose. Its rows
    /// are made once per `make`, `n` of them times `--scale`.
    static var variants: [ScenarioVariant] {
        CaseTables.cases.filter { !$0.composition.isAdopted }.map { perfCase in
            ScenarioVariant(
                id: perfCase.id,
                summary: "\(perfCase.composition) in \(perfCase.container.rawValue), n \(perfCase.count), "
                    + "\(perfCase.size) [\(perfCase.tags.joined(separator: ","))]",
                axis: family(of: perfCase),
                make: { config in
                    let count = perfCase.count * max(1, config.scale)
                    let rows = CaseRows(
                        count: count, seed: CasePlayer.seed, keepsDocument: perfCase.composition.hasEditor,
                        keepsTree: perfCase.composition.hasOutline)
                    return perfCase.page(rows: rows, count: count, seed: CasePlayer.seed)
                        ?? AnyView(Text(verbatim: "Stress has no scenario \(perfCase.composition)"))
                })
        }
    }

    /// The table a case is written in, lowercased: `lists` for
    /// `Stress/Cases/Tables/Lists.swift`.
    private static func family(of perfCase: PerfCase) -> String {
        let file = perfCase.origin.file.split(separator: "/").last.map(String.init) ?? perfCase.origin.file
        return (file.hasSuffix(".swift") ? String(file.dropLast(".swift".count)) : file).lowercased()
    }
}
