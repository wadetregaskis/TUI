//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseTables.swift
//
//  Every table of perf cases, one per family of situations, each in its own
//  file under `Tables/` so lanes adding cases to different families never
//  touch the same lines; and `Stress --cases`, which lists them.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The perf-case tables, in the order `--check-counts` plays them.
enum CaseTables {
    static let all: [CaseTableSource] = [lists, tables, outlines, scrolling, composites, editors, adopted]

    /// The tables read, once: every case, or every mistake.
    static let parsed = CaseTable.parse(all)

    /// Every case, in table order; none if the tables have mistakes, which
    /// `--cases` and `--check-counts` print. What the sessions (`case:<id>`)
    /// and the `cases` matrix scenario are made from.
    static var cases: [PerfCase] { (try? parsed.get()) ?? [] }

    /// `Stress --cases [--timed] [--tags a,b]`: every case, or those the
    /// timed sweep includes, or those with any of the tags, a line each in
    /// the table's columns. Machine-read, as `--variants` is: the first word
    /// of a line is the case's id (`ab_bench.py --cases`, `sweep.py
    /// --cases`), so there is no header line. The process's exit status: 1
    /// for a table with mistakes or a tag no case can have.
    static func list(timedOnly: Bool, tags: Set<String>) -> Int32 {
        let cases: [PerfCase]
        switch parsed {
        case .success(let all): cases = all
        case .failure(let errors):
            print("cases: the case tables have mistakes:\n\(errors)")
            return 1
        }
        let unknown = tags.subtracting(CaseTags.known)
        guard unknown.isEmpty else {
            print("cases: no case can have the tag \(unknown.sorted().joined(separator: ", ")). "
                + "Known: \(CaseTags.known.sorted().joined(separator: ", "))")
            return 1
        }
        let chosen = cases.filter { perfCase in
            (!timedOnly || perfCase.timed) && (tags.isEmpty || !tags.isDisjoint(with: perfCase.tags))
        }
        let lines = chosen.map { perfCase in
            [
                perfCase.id, perfCase.composition.description, perfCase.container.rawValue,
                perfCase.size.description, "\(perfCase.count)", perfCase.phases.map(\.spelling).joined(separator: ";"),
                perfCase.scaling.rawValue, perfCase.timed ? "t" : "-", perfCase.tags.joined(separator: ","),
            ]
        }
        // Padded to each column's widest, never to a constant, so no id is cut.
        let widths = (0..<CaseTable.columns.count).map { column in lines.map { $0[column].count }.max() ?? 0 }
        for line in lines {
            let padded = zip(line, widths).map { field, width in
                field + String(repeating: " ", count: max(0, width - field.count))
            }
            print(padded.joined(separator: "  ").trimmingTrailingSpaces)
        }
        return 0
    }
}

extension String {
    /// The string without the spaces at its end.
    fileprivate var trimmingTrailingSpaces: String {
        String(self[..<(lastIndex { $0 != " " }.map(index(after:)) ?? startIndex)])
    }
}
