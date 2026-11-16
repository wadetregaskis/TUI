//  🖥️ TUI — A Terminal UI framework for Swift
//  RecordedCounts.swift
//
//  The recorded counts file, `RecordedCounts.txt` beside this one: one line
//  per case and phase, read and written by `Stress --check-counts`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// One line of the recorded file: a case's phase and its counts.
///
/// The case column is the case's id, with `@10n` or `@2n` for its scaling
/// rerun and then `@linux` for a line that holds on Linux alone, where the
/// counts there differ from the line without it (design, "Fitting it into the
/// gate").
struct RecordedLine: Equatable, Sendable {
    let key: String
    let phase: String
    let counts: CaseCounts

    /// The line as the file holds it, its columns padded to `widths`.
    func formatted(widths: [Int]) -> String {
        let fields = [key, phase] + counts.values.map(String.init)
        return zip(fields, widths).map { field, width in field.padding(toLength: width, withPad: " ", startingAt: 0) }
            .joined(separator: "  ").trimmingCharacters(in: .whitespaces)
    }
}

/// The recorded file, read and written.
enum RecordedCounts {
    /// The column header.
    static let header = ["case", "phase"] + CaseCounts.names

    /// The platform suffix this build reads and writes, or `""` for the lines
    /// every platform shares.
    static var platformSuffix: String {
        #if os(Linux)
        "@linux"
        #else
        ""
        #endif
    }

    /// Where the file is: beside this source file, so the gate and CI, which
    /// build in the checkout they check, read the checkout's own.
    static var defaultPath: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("RecordedCounts.txt").path
    }

    /// The lines of the file at `path`, by key and phase, or why they could
    /// not be read. A missing file is no lines: every case is then unrecorded.
    static func read(_ path: String) -> Result<[String: RecordedLine], CaseTableErrors> {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return .success([:]) }
        var lines: [String: RecordedLine] = [:]
        var errors: [CaseTableError] = []
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let origin = CaseOrigin(file: path, line: offset + 1)
            let fields = line.split(separator: " ").map(String.init)
            if fields.isEmpty || fields[0].hasPrefix("#") || fields == header { continue }
            guard fields.count == header.count, let counts = CaseCounts(values: fields.dropFirst(2).compactMap { Int($0) })
            else {
                errors.append(CaseTableError(origin: origin, message: "not '\(header.joined(separator: " "))'"))
                continue
            }
            let recorded = RecordedLine(key: fields[0], phase: fields[1], counts: counts)
            lines[id(recorded.key, recorded.phase)] = recorded
        }
        return errors.isEmpty ? .success(lines) : .failure(CaseTableErrors(errors: errors))
    }

    /// A line's key and phase as one dictionary key.
    static func id(_ key: String, _ phase: String) -> String { "\(key) \(phase)" }

    /// Writes `lines` to `path` under the file's explanation and header, in
    /// the order given.
    static func write(_ lines: [RecordedLine], to path: String) throws {
        let rows = [header] + lines.map { [$0.key, $0.phase] + $0.counts.values.map(String.init) }
        let widths = header.indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
        let headerLine = zip(header, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
            .joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        let body = lines.map { $0.formatted(widths: widths) }
        let text = (preamble + [headerLine] + body).joined(separator: "\n") + "\n"
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// What the file says about itself, above its header.
    static let preamble = [
        "# The perf cases' recorded counts: `swift run Stress --check-counts` plays every case in",
        "# Sources/Stress/Cases/Tables/ and compares what each phase of its script did with the line here.",
        "# Totals over the phase's steps, not means: a total compares exactly. Written by",
        "# `TUI_RECORD_PERF_COUNTS=1 swift run Stress --check-counts`; the commit that re-records says, per",
        "# case, what moved and why. `git log -p` on this file is the ledger of what each change did.",
        "# <id>@10n / <id>@2n: the case's scaling rerun. <key>@linux: a line that holds on Linux alone.",
    ]
}
