//  🖥️ TUI — A Terminal UI framework for Swift
//  CountCheck+Record.swift
//
//  `TUI_RECORD_PERF_COUNTS=1 Stress --check-counts`: writes what the cases
//  did as the recorded counts, platform by platform.
//
//  Created by Wade Tregaskis
//  License: MIT

extension CountCheck {
    /// Writes `produced` to the file.
    ///
    /// A whole run's lines replace the file's for this platform. On macOS
    /// those are the shared lines, and the `@linux` ones are kept for the
    /// cases still played. On Linux the shared lines are kept as they are
    /// (they are macOS's), and each phase whose counts differ from its shared
    /// line, or has none, gets an `@linux` line. A run of some cases
    /// (`--case`) replaces only theirs.
    static func record(_ produced: [RecordedLine], cases: [PerfCase], options: Options, report: Report) -> Int32 {
        let existing = (try? RecordedCounts.read(options.path).get()) ?? [:]
        let whole = options.only.isEmpty
        let played = Set(produced.map { RecordedCounts.id($0.key, $0.phase) })
        let suffix = RecordedCounts.platformSuffix
        var lines: [String: RecordedLine] = [:]
        for (id, line) in existing {
            let isLinuxLine = line.key.hasSuffix("@linux")
            let isOtherPlatforms = isLinuxLine == suffix.isEmpty
            if isOtherPlatforms {
                // Kept, unless a whole macOS run finds its case is gone.
                if !whole || !suffix.isEmpty || played.contains(sharedID(of: line)) { lines[id] = line }
            } else if !whole {
                lines[id] = line
            }
        }
        for line in produced {
            if suffix.isEmpty {
                lines[RecordedCounts.id(line.key, line.phase)] = line
            } else {
                let own = RecordedLine(key: line.key + suffix, phase: line.phase, counts: line.counts)
                let shared = lines[RecordedCounts.id(line.key, line.phase)]
                lines[RecordedCounts.id(own.key, own.phase)] = shared?.counts == line.counts ? nil : own
            }
        }
        let order = lineOrder(cases)
        let ordered = lines.values.sorted { lhs, rhs in
            (order[sharedID(of: lhs)] ?? .max, lhs.key) < (order[sharedID(of: rhs)] ?? .max, rhs.key)
        }
        do {
            try RecordedCounts.write(ordered, to: options.path)
        } catch {
            print("check-counts: could not write \(options.path): \(error)")
            return 1
        }
        print("check-counts: recorded \(produced.count) lines to \(options.path)")
        return report.failures.isEmpty ? 0 : report.finish(cases: cases.count, lines: produced.count, path: options.path)
    }

    /// The id of the shared line a line stands for: its key less `@linux`.
    static func sharedID(of line: RecordedLine) -> String {
        RecordedCounts.id(String(line.key.dropLast(line.key.hasSuffix("@linux") ? "@linux".count : 0)), line.phase)
    }

    /// Where each line goes in the file: the tables' order, each case's
    /// phases in script order, its rerun's after them.
    private static func lineOrder(_ cases: [PerfCase]) -> [String: Int] {
        var order: [String: Int] = [:]
        for perfCase in cases {
            let keys = [perfCase.id] + (perfCase.scaling.factor.map { ["\(perfCase.id)@\($0)n"] } ?? [])
            for key in keys {
                for label in CasePlayer.labels(of: perfCase) { order[RecordedCounts.id(key, label)] = order.count }
            }
        }
        return order
    }
}
