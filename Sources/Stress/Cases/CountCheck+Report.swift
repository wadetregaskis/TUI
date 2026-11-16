//  🖥️ TUI — A Terminal UI framework for Swift
//  CountCheck+Report.swift
//
//  What `Stress --check-counts` found, and how it says so: every failure with
//  the lines and the commands a person needs next, every improvement with
//  both numbers, and one last line the gate reads.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CountCheck {
    /// The failures and improvements of a run.
    struct Report {
        /// Each failure, described in full.
        private(set) var failures: [String] = []
        /// The cases with a failure.
        private(set) var failedCases: Set<String> = []
        /// Each count that fell, as `IMPROVED <case> <phase> <count> <old> → <new>`.
        private(set) var improvements: [String] = []
        /// Each case that breaks its scaling class in the counts its known
        /// issue names (``CaseKnownIssues``), described: printed, not failed.
        private(set) var known: [String] = []

        /// Notes a known issue the run showed.
        mutating func noteKnown(_ description: String) { known.append(description) }

        /// A failure of the case as a whole: it could not be played, two
        /// plays disagreed, or its scaling class broke.
        mutating func fail(_ perfCase: PerfCase, _ message: String) {
            failedCases.insert(perfCase.id)
            failures.append("FAIL \(perfCase.id): \(message)\n" + Self.commands(for: perfCase.id))
        }

        /// A failure of one recorded line.
        mutating func fail(_ line: RecordedLine, _ message: String) {
            let id = Self.caseID(of: line.key)
            failedCases.insert(id)
            failures.append("FAIL \(line.key) \(line.phase): \(message)\n" + Self.commands(for: id))
        }

        /// Compares a line with the one recorded for it: a count past its
        /// tolerance above the recorded one fails, below it is an
        /// improvement, and a different number of steps means the script
        /// changed, which only a re-record settles.
        mutating func compare(old: RecordedLine, new: RecordedLine) {
            var rises: [String] = []
            for (name, before, after) in zip3(CaseCounts.names, old.counts.values, new.counts.values) {
                let slack = CountCheck.toleratedCounts.contains(name) ? before / 100 : 0
                if name == "steps", before != after {
                    rises.append("steps \(before) → \(after): the script changed")
                } else if after > before + slack {
                    rises.append("\(name) \(before) → \(after)")
                } else if after < before - slack {
                    improvements.append("IMPROVED \(new.key) \(new.phase) \(name) \(before) → \(after)")
                }
            }
            guard !rises.isEmpty else { return }
            let id = Self.caseID(of: new.key)
            failedCases.insert(id)
            let widths = RecordedCounts.header.indices.map { column in
                ([RecordedCounts.header] + [old, new].map { [$0.key, $0.phase] + $0.counts.values.map(String.init) })
                    .map { $0[column].count }.max() ?? 0
            }
            // Where nobody can re-record (CI's Linux lanes), the line a person
            // would paste to record this platform's counts apart.
            let suffix = RecordedCounts.platformSuffix
            let own = RecordedLine(key: new.key + suffix, phase: new.phase, counts: new.counts)
            let paste = suffix.isEmpty ? "" : "  for \(suffix) alone: \(own.formatted(widths: widths))\n"
            failures.append(
                "FAIL \(new.key) \(new.phase): \(rises.joined(separator: ", "))\n"
                    + "  recorded: \(old.formatted(widths: widths))\n"
                    + "  now:      \(new.formatted(widths: widths))\n" + paste + Self.commands(for: id))
        }

        /// Prints what the run found, and the last line the gate reads; the
        /// exit status.
        func finish(cases: Int, lines: Int, path: String) -> Int32 {
            for failure in failures { print(failure) }
            for improvement in improvements { print(improvement) }
            for issue in known { print(issue) }
            let improved = improvements.isEmpty ? "" : "; \(improvements.count) counts improved, re-record to keep them"
            guard failures.isEmpty else {
                print(
                    "check-counts: FAILED — \(failures.count) problems in \(failedCases.count) of \(cases) cases "
                        + "(\(failedCases.sorted().joined(separator: ", ")))\(improved)")
                return 1
            }
            print("check-counts: all \(cases) cases match \(path) (\(lines) lines\(improved))")
            return 0
        }

        /// The case a recorded key belongs to: the key up to its first `@`.
        private static func caseID(of key: String) -> String {
            String(key.prefix { $0 != "@" })
        }

        /// How to see a case again, and how to record what it does now.
        private static func commands(for id: String) -> String {
            "  again:     swift run Stress --check-counts --case \(id)\n"
                + "  re-record: \(CountCheck.recordVariable)=1 swift run Stress --check-counts --case \(id)"
                + "  (and say in the commit what moved and why)"
        }
    }
}
