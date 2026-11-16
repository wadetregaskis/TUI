//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseTable+Script.swift
//
//  Reads a case's script column: phases separated by `;`, each a step with an
//  optional `*k` to take it k times in a row (`open;wheel:+5*20`).
//
//  Created by Wade Tregaskis
//  License: MIT

extension CaseTable {
    /// The phases `text` spells, `open` first: added when the script leaves
    /// it out, refused anywhere else.
    static func parseScript(_ text: String, at origin: CaseOrigin) throws(CaseTableError) -> [CasePhase] {
        func fail(_ message: String) -> CaseTableError { CaseTableError(origin: origin, message: message) }
        var phases: [CasePhase] = []
        for spelling in text.split(separator: ";", omittingEmptySubsequences: false).map(String.init) {
            guard !spelling.isEmpty else { throw fail("an empty phase in script '\(text)'") }
            phases.append(try parsePhase(spelling, at: origin))
        }
        if phases.first?.step != .open { phases.insert(CasePhase(step: .open, repeats: 1), at: 0) }
        if phases[0].repeats != 1 { throw fail("'open' is the first frame, and taken once") }
        if phases.dropFirst().contains(where: { $0.step == .open }) { throw fail("'open' may only be the first phase") }
        return phases
    }

    /// One phase: a step, then `*k` if it is taken k times. A `*` followed by
    /// anything but digits is part of the step (`type:a*b`).
    static func parsePhase(_ text: String, at origin: CaseOrigin) throws(CaseTableError) -> CasePhase {
        if let star = text.lastIndex(of: "*"), let repeats = Int(text[text.index(after: star)...]) {
            guard repeats >= 1 else {
                throw CaseTableError(origin: origin, message: "'\(text)' repeats a step \(repeats) times")
            }
            return CasePhase(step: try parseStep(String(text[..<star]), at: origin), repeats: repeats)
        }
        return CasePhase(step: try parseStep(text, at: origin), repeats: 1)
    }

    /// One step, as ``CaseStep/description`` spells it.
    static func parseStep(_ text: String, at origin: CaseOrigin) throws(CaseTableError) -> CaseStep {  // swiftlint:disable:this cyclomatic_complexity
        func fail(_ expected: String) -> CaseTableError {
            CaseTableError(origin: origin, message: "step '\(text)': \(expected)")
        }
        let name = text.prefix { $0 != ":" }
        let argument = text.count > name.count ? String(text.dropFirst(name.count + 1)) : nil
        switch (name, argument) {
        case ("open", nil): return .open
        case ("idle", nil): return .idle
        case ("replace", nil): return .replace
        case ("wheel", let argument?):
            guard let ticks = signed(argument), ticks != 0 else { throw fail("wheel:+k or wheel:-k") }
            return .wheel(ticks)
        case ("hover", let argument?):
            guard let rows = signed(argument), rows != 0 else { throw fail("hover:+k or hover:-k") }
            return .hover(rows)
        case ("key", let argument?):
            guard let key = CaseKey(rawValue: argument) else {
                throw fail("a key is one of \(CaseKey.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return .key(key)
        case ("type", let argument?):
            guard !argument.isEmpty, argument.allSatisfy({ $0.isASCII && !$0.isWhitespace && $0 != ";" }) else {
                throw fail("type:<text>, printable ASCII without spaces")
            }
            return .type(argument)
        case ("resize", let argument?):
            guard let size = CaseSize(argument) else { throw fail("resize:WIDTHxHEIGHT") }
            return .resize(size)
        case ("tick", let argument?):
            guard let milliseconds = Int(argument), milliseconds > 0 else { throw fail("tick:<milliseconds>") }
            return .tick(milliseconds)
        case ("append", let argument?):
            guard let count = Int(argument), count > 0 else { throw fail("append:<count>") }
            return .append(count)
        case ("edit", let argument?) where argument == "mid": return .editMiddle
        case ("remove", let argument?):
            guard let index = Int(argument), index >= 0 else { throw fail("remove:<index>") }
            return .remove(index)
        case ("move", let argument?):
            let ends = argument.split(separator: ">", omittingEmptySubsequences: false).compactMap { Int($0) }
            guard ends.count == 2, ends.allSatisfy({ $0 >= 0 }) else { throw fail("move:<from>><to>") }
            return .move(from: ends[0], to: ends[1])
        default:
            throw fail(
                "not one of open, idle, wheel:±k, key:<name>, type:<text>, hover:±k, resize:WxH, tick:<ms>, "
                    + "append:k, edit:mid, remove:i, move:a>b, replace")
        }
    }

    /// `+k` or `-k`: a sign is required, so the direction is always written.
    private static func signed(_ text: String) -> Int? {
        guard let sign = text.first, sign == "+" || sign == "-", let magnitude = Int(text.dropFirst()), magnitude > 0
        else { return nil }
        return sign == "-" ? -magnitude : magnitude
    }
}
