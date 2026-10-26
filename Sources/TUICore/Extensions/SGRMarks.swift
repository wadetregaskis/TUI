//  🖥️ TUI — A Terminal UI framework for Swift
//  SGRMarks.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A private SGR parameter some cells carry

/// The reading and writing every cell mark shares: a private SGR parameter a
/// run of cells carries as styling, through every stage that rewrites cells,
/// which the diff writer reads back off the finished frame and takes out
/// before anything reaches the terminal (``HairlineMarker`` says why the cells
/// carry it, and why a private parameter).
///
/// A mark is `ESC [ <parameter> : <field> : … m`, its fields colon
/// sub-parameters. ``SGRState`` keeps a parameter it does not know verbatim
/// among its passthrough codes, which every splitter and collapser restates
/// with the rest of a cell's styling, and which ends only at a reset.
package enum SGRMarks {

    /// Whether `line` may carry a mark of `parameter`: a byte search, so a
    /// line without one pays one pass over its bytes and no decoding.
    ///
    /// - Parameter parameterBytes: The parameter's digits and its colon,
    ///   `7744:`.
    package static func mayCarry(_ line: String, parameterBytes needle: [UInt8]) -> Bool {
        var line = line
        return line.withUTF8 { bytes in
            guard bytes.count >= needle.count + 3 else { return false }
            var index = 0
            let last = bytes.count - needle.count
            while index <= last {
                // Only after the `[` or `;` that starts a parameter: the digits in
                // a cell's text are text, and a sanitised row's text holds no ESC
                // to make them anything else.
                if bytes[index] == needle[0], index > 0, bytes[index - 1] == 0x5B || bytes[index - 1] == 0x3B {
                    var matched = 1
                    while matched < needle.count, bytes[index + matched] == needle[matched] { matched += 1 }
                    if matched == needle.count { return true }
                }
                index += 1
            }
            return false
        }
    }

    /// `line` without the marks `payload` reads, handing each cell under one
    /// to `cell` in column order — its column, its width in cells, and what
    /// its mark said.
    ///
    /// Every mark parameter is taken out of the escape it sits in; an escape
    /// left with no parameter at all goes with it — an emptied `ESC[m` would
    /// be a reset. A reset ends a mark, as it ends any passthrough code.
    ///
    /// - Parameters:
    ///   - payload: What a parameter says, or `nil` for one that is not this
    ///     kind's mark.
    ///   - cell: Called for each cell with a width that a mark is in force on.
    package static func extracting<Payload>(
        _ line: String, payload: (Substring) -> Payload?, cell: (_ column: Int, _ width: Int, Payload) -> Void
    ) -> String {
        var result = ""
        result.reserveCapacity(line.utf8.count)
        var mark: Payload?
        var column = 0
        line.forEachANSISegment { segment in
            switch segment {
            case .ansi(let text, let isSGR):
                guard isSGR else {
                    result += text
                    return true
                }
                let parameters = text.dropFirst(2).dropLast().split(separator: ";", omittingEmptySubsequences: false)
                var kept: [Substring] = []
                var removed = false
                var index = 0
                while index < parameters.count {
                    let span = span(parameters, at: index)
                    if let said = payload(parameters[index]) {
                        mark = said
                        removed = true
                    } else {
                        if isReset(parameters, at: index) { mark = nil }
                        kept += parameters[index..<(index + span)]
                    }
                    index += span
                }
                if !removed {
                    result += text
                } else if !kept.isEmpty {
                    result += "\u{1B}[" + kept.joined(separator: ";") + "m"
                }
            case .visible(let character):
                let width = character.terminalWidth
                if let mark, width > 0 { cell(column, width, mark) }
                result.append(character)
                column += width
            }
            return true
        }
        return result
    }

    /// A mark's fields, if `parameter` is a mark of `number` with `count` of
    /// them, each a number: `7744:1:2:3` read with `count` 3 is `[1, 2, 3]`.
    package static func fields(of parameter: Substring, number: Int, count: Int) -> [Int]? {
        let parts = parameter.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == count + 1, parts[0] == "\(number)" else { return nil }
        var values: [Int] = []
        values.reserveCapacity(count)
        for part in parts.dropFirst() {
            guard let value = Int(part) else { return nil }
            values.append(value)
        }
        return values
    }

    /// Whether SGR `sequence` ends a passthrough code: a reset among its
    /// parameters (``isReset(_:at:)``).
    package static func resets(_ sequence: String) -> Bool {
        let parameters = sequence.dropFirst(2).dropLast().split(separator: ";", omittingEmptySubsequences: false)
        var index = 0
        while index < parameters.count {
            if isReset(parameters, at: index) { return true }
            index += span(parameters, at: index)
        }
        return false
    }

    /// Whether the parameter at `index` is SGR 0: empty (`ESC[m`, `ESC[;1m`)
    /// or all zeroes. Asked only at a parameter's own start, so the 0 of
    /// `38;5;0` — a colour's index — is never read as one.
    private static func isReset(_ parameters: [Substring], at index: Int) -> Bool {
        let parameter = parameters[index]
        return parameter.isEmpty || parameter.allSatisfy { $0 == "0" }
    }

    /// How many parameters the one at `index` takes up: a `38`, `48` or `58`
    /// in its semicolon form takes its colour's arguments with it (`5;n`,
    /// `2;r;g;b`), as ``SGRState`` reads it; everything else is one.
    private static func span(_ parameters: [Substring], at index: Int) -> Int {
        let parameter = parameters[index]
        guard parameter == "38" || parameter == "48" || parameter == "58", index + 1 < parameters.count else {
            return 1
        }
        switch parameters[index + 1] {
        case "5": return min(3, parameters.count - index)
        case "2": return min(5, parameters.count - index)
        default: return 1
        }
    }
}
