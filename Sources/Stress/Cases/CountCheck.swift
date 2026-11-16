//  🖥️ TUI — A Terminal UI framework for Swift
//  CountCheck.swift
//
//  `Stress --check-counts`: plays every perf case, twice, and again at a
//  larger n for its scaling class, and compares what each phase did with the
//  recorded counts. A count that rises fails; one that falls passes and is
//  printed, with both numbers, until it is re-recorded (owner, A-PERFCASE-1).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

enum CountCheck {
    /// The variable that re-records the file, as `TUI_RECORD_SNAPSHOTS`
    /// re-records the golden snapshots.
    static let recordVariable = "TUI_RECORD_PERF_COUNTS"

    /// The counts that may move by 1% before failing: the value memo keys
    /// some values by an address, and its hits vary by a few in a thousand
    /// between runs of one build. Every other count is exact.
    static let toleratedCounts: Set<String> = ["served", "misses"]

    /// The counts a case's scaling rerun is held to. `bytes` is not one: a
    /// scroll bar's thumb is a different size and place at 10n, and writes
    /// other cells for the same rows.
    static let scaledCounts = ["listed", "built", "served", "bodies", "cells", "misses"]

    // MARK: The environment

    /// Pins what the counts depend on for the whole process, before anything
    /// reads it: called from `main.swift` before the localization service is
    /// made, and only for `--check-counts`.
    ///
    /// - The language and locale: English, US. TUI's own words (a search
    ///   field's prompt) and an adopted scenario's are drawn in it, and their
    ///   bytes differ by language; a stored language is not read, because
    ///   `TUI_CONFIG_DIR` names a folder that does not exist.
    /// - Every `TUI_` variable but ``recordVariable`` unset, and `NO_COLOR`,
    ///   `COLUMNS` and `LINES` with them: a person's `TUI_PLAIN_TEXT`, or the
    ///   gate's `TUI_VERIFY_RENDER_MEMO`, would change what is drawn or done.
    ///
    /// The colour depth is pinned per frame (``CasePlayer``).
    static func pinEnvironment() {
        for name in ProcessInfo.processInfo.environment.keys
        where (name.hasPrefix("TUI_") || name.hasPrefix("TUIKIT_")) && name != recordVariable {
            unsetenv(name)
        }
        for name in ["NO_COLOR", "FORCE_COLOR", "CLICOLOR_FORCE", "COLUMNS", "LINES"] { unsetenv(name) }
        setenv("LANGUAGE", "en", 1)
        setenv("LC_ALL", "en_US.UTF-8", 1)
        setenv("LANG", "en_US.UTF-8", 1)
        setenv("TUI_CONFIG_DIR", NSTemporaryDirectory() + "stress-check-counts-has-no-settings", 1)
    }

    // MARK: The check

    /// What `--check-counts` was asked to do.
    struct Options {
        /// Only these cases, or every case when empty.
        var only: Set<String> = []
        var path = RecordedCounts.defaultPath
        /// Write the counts rather than compare them.
        var records = false
        /// Print each case's last frame, styling stripped: what the script
        /// did, for the person writing a case.
        var shows = false
    }

    /// Plays the cases and checks them; the process's exit status.
    @MainActor
    static func run(_ options: Options) -> Int32 {
        let cases: [PerfCase]
        switch CaseTable.parse(CaseTables.all) {
        case .success(let parsed): cases = parsed
        case .failure(let errors):
            print("check-counts: the case tables have mistakes:\n\(errors)")
            return 1
        }
        let unknown = options.only.subtracting(cases.map(\.id))
        guard unknown.isEmpty else {
            print("check-counts: no case \(unknown.sorted().joined(separator: ", ")). Known: \(cases.map(\.id).joined(separator: ", "))")
            return 1
        }
        let chosen = options.only.isEmpty ? cases : cases.filter { options.only.contains($0.id) }
        var report = Report()
        var produced: [RecordedLine] = []
        for perfCase in chosen {
            let started = DispatchTime.now().uptimeNanoseconds
            guard let lines = play(perfCase, showing: options.shows, into: &report) else { continue }
            produced += lines
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
            print("  played \(perfCase.id) (\(lines.count) lines, \(seconds.formatted(.fixed(1))) s)")
        }
        if options.records {
            return record(produced, cases: cases, options: options, report: report)
        }
        switch RecordedCounts.read(options.path) {
        case .failure(let errors):
            print("check-counts: \(options.path) has mistakes:\n\(errors)")
            return 1
        case .success(let recorded):
            compare(produced, with: recorded, checkingStale: options.only.isEmpty, into: &report)
        }
        return report.finish(cases: chosen.count, lines: produced.count, path: options.path)
    }

    /// Plays `perfCase` twice at its n and once at its scaling rerun's,
    /// noting in `report` what differs between the two and what breaks its
    /// scaling class; its lines, or `nil` if it could not be played.
    @MainActor
    private static func play(_ perfCase: PerfCase, showing: Bool, into report: inout Report) -> [RecordedLine]? {
        guard let first = CasePlayer(perfCase, count: perfCase.count)?.play(perfCase),
            let second = CasePlayer(perfCase, count: perfCase.count)?.play(perfCase)
        else {
            report.fail(perfCase, "\(perfCase.origin): Stress has no scenario \(perfCase.composition)")
            return nil
        }
        if showing { print("  \(perfCase.id), last frame:\n" + first.lastScreen.map { "  | " + $0 }.joined(separator: "\n")) }
        // Counted twice, they must agree: a count is deterministic, so a
        // difference is flakiness, which exact counts exist to catch (B-PERFCASE-4).
        for ((label, a), (_, b)) in zip(first.phases, second.phases) {
            for (name, x, y) in zip3(CaseCounts.names, a.values, b.values) where !agree(name, x, y) {
                report.fail(perfCase, "\(label): \(name) was \(x) and then \(y) in two plays of one build")
            }
        }
        var lines = first.phases.map { RecordedLine(key: perfCase.id, phase: $0.label, counts: $0.counts) }
        if let factor = perfCase.scaling.factor,
            let rerun = CasePlayer(perfCase, count: perfCase.count * factor)?.play(perfCase)
        {
            checkScaling(perfCase, first, rerun, factor: factor, into: &report)
            lines += rerun.phases.map {
                RecordedLine(key: "\(perfCase.id)@\(factor)n", phase: $0.label, counts: $0.counts)
            }
        }
        return lines
    }

    /// Whether two plays' readings of the count `name` agree.
    private static func agree(_ name: String, _ x: Int, _ y: Int) -> Bool {
        abs(x - y) <= (toleratedCounts.contains(name) ? max(x, y) / 100 : 0)
    }

    /// `flat`: every count of the rerun at 10n is the count at n: O(1).
    /// `linear`: every count of the rerun at 2n is either the count at n or
    /// twice it, ±10%: O(1) or O(n), never worse, and never shrinking. A
    /// count the case's known issues name (``CaseKnownIssues``) — in every
    /// phase, or in the one phase they name with it — is printed as known
    /// rather than failed.
    private static func checkScaling(
        _ perfCase: PerfCase, _ base: CasePlay, _ rerun: CasePlay, factor: Int, into report: inout Report
    ) {
        let known = CaseKnownIssues.scaling[perfCase.id]
        var brokenKnown: [String] = []
        for ((label, a), (_, b)) in zip(base.phases, rerun.phases) {
            for name in scaledCounts {
                guard let index = CaseCounts.names.firstIndex(of: name) else { continue }
                let (x, y) = (a.values[index], b.values[index])
                let scaled = Double(x) * Double(factor)
                let keeps: Bool
                switch perfCase.scaling {
                case .flat: keeps = agree(name, x, y)
                case .linear: keeps = agree(name, x, y) || (scaled * 0.9...scaled * 1.1).contains(Double(y))
                case .none: keeps = true
                }
                guard !keeps else { continue }
                let what = "\(label): \(name) \(x) at n but \(y) at \(factor)n"
                if let known, known.counts.contains(name) || known.counts.contains("\(label) \(name)") {
                    brokenKnown.append(what)
                } else {
                    report.fail(perfCase, "\(what), and the case is \(perfCase.scaling.rawValue)")
                }
            }
        }
        if let known, !brokenKnown.isEmpty {
            report.noteKnown(
                "KNOWN \(perfCase.id) is not \(perfCase.scaling.rawValue): \(known.finding)\n  "
                    + brokenKnown.joined(separator: "\n  "))
        }
    }

    // MARK: Comparing

    /// Compares each produced line with the recorded one for this platform:
    /// its `@linux` line on Linux where there is one, else the shared one.
    static func compare(
        _ produced: [RecordedLine], with recorded: [String: RecordedLine], checkingStale: Bool,
        into report: inout Report
    ) {
        let suffix = RecordedCounts.platformSuffix
        for line in produced {
            let own = suffix.isEmpty ? nil : recorded[RecordedCounts.id(line.key + suffix, line.phase)]
            guard let old = own ?? recorded[RecordedCounts.id(line.key, line.phase)] else {
                report.fail(line, "not recorded")
                continue
            }
            report.compare(old: old, new: line)
        }
        guard checkingStale else { return }
        let played = Set(produced.map { RecordedCounts.id($0.key, $0.phase) })
        for (id, line) in recorded where !played.contains(id.replacingOccurrences(of: "@linux", with: "")) {
            report.fail(line, "recorded, but no case plays it: re-record to drop it")
        }
    }
}

/// Three sequences in step.
func zip3<A: Sequence, B: Sequence, C: Sequence>(_ a: A, _ b: B, _ c: C) -> [(A.Element, B.Element, C.Element)] {
    zip(zip(a, b), c).map { ($0.0, $0.1, $1) }
}
