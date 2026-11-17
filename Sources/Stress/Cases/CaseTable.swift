//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseTable.swift
//
//  Reads the perf-case table: one case a line, its columns separated by runs
//  of spaces, as `ScrollFitBaselineTable.swift` lays its rows out. Every
//  mistake is reported with the file and line it is on, all of them at once,
//  so a table with three typos is fixed in one pass.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A table of cases as written in a source file: its text, and where in the
/// file the text's first line is, so an error names the line a person edits.
struct CaseTableSource: Sendable {
    let file: String
    /// The file's line the text's first line is on.
    let firstLine: Int
    let text: String

    /// A table written as a multi-line literal that opens on the line of the
    /// call: `CaseTableSource(file: #fileID, line: #line, """` puts the
    /// table's first line on the next one.
    init(file: String, line: Int, _ text: String) {
        self.file = file
        self.firstLine = line + 1
        self.text = text
    }
}

/// A mistake in a case table, at the line it is on.
struct CaseTableError: Error, Sendable, CustomStringConvertible {
    let origin: CaseOrigin
    let message: String

    var description: String { "\(origin): \(message)" }
}

/// The parser.
enum CaseTable {
    /// The header every table starts with, column by column.
    static let columns = ["id", "composition", "in", "size", "n", "script", "scales", "timed", "tags"]

    /// Every case in `sources`, or every mistake in them.
    ///
    /// Ids are unique across all the sources, not only within one, since
    /// `--case` and the recorded counts name a case by its id alone.
    static func parse(_ sources: [CaseTableSource]) -> Result<[PerfCase], CaseTableErrors> {
        var cases: [PerfCase] = []
        var errors: [CaseTableError] = []
        var seen: [String: CaseOrigin] = [:]
        for source in sources {
            let (parsed, found) = parse(source)
            errors += found
            for perfCase in parsed {
                if let first = seen[perfCase.id] {
                    errors.append(CaseTableError(origin: perfCase.origin, message: "id '\(perfCase.id)' is also at \(first)"))
                } else {
                    seen[perfCase.id] = perfCase.origin
                    cases.append(perfCase)
                }
            }
        }
        return errors.isEmpty ? .success(cases) : .failure(CaseTableErrors(errors: errors))
    }

    /// The cases in one source, and the mistakes in it.
    static func parse(_ source: CaseTableSource) -> (cases: [PerfCase], errors: [CaseTableError]) {
        var cases: [PerfCase] = []
        var errors: [CaseTableError] = []
        var sawHeader = false
        for (offset, line) in source.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let origin = CaseOrigin(file: source.file, line: source.firstLine + offset)
            let fields = line.split(separator: " ").map(String.init)
            if fields.isEmpty || fields[0].hasPrefix("#") { continue }
            guard sawHeader else {
                sawHeader = true
                if fields != columns {
                    errors.append(
                        CaseTableError(
                            origin: origin, message: "the header must be '\(columns.joined(separator: " "))'"))
                }
                continue
            }
            do {
                cases.append(try parseCase(fields, at: origin))
            } catch {
                errors.append(error)
            }
        }
        if !sawHeader {
            errors.append(
                CaseTableError(origin: CaseOrigin(file: source.file, line: source.firstLine), message: "no header"))
        }
        return (cases, errors)
    }

    /// One case from its line's fields.
    static func parseCase(_ fields: [String], at origin: CaseOrigin) throws(CaseTableError) -> PerfCase {
        func fail(_ message: String) -> CaseTableError { CaseTableError(origin: origin, message: message) }
        guard fields.count == columns.count else {
            throw fail("\(fields.count) columns where the header has \(columns.count) (no column may hold a space)")
        }
        let id = fields[0]
        guard isKebabCase(id) else { throw fail("id '\(id)' is not kebab-case") }
        let composition = try parseComposition(fields[1], at: origin)
        guard let container = CaseContainer(rawValue: fields[2]) else {
            throw fail("in '\(fields[2])' is not one of \(CaseContainer.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        guard composition.isAdopted == (container == .none) else {
            throw fail(composition.isAdopted ? "an adopted scenario is in '-'" : "in '-' is for an adopted scenario only")
        }
        guard let size = CaseSize(fields[3]) else { throw fail("size '\(fields[3])' is not WIDTHxHEIGHT") }
        guard let count = Int(fields[4]), count >= 1 else { throw fail("n '\(fields[4])' is not a positive integer") }
        let phases = try parseScript(fields[5], at: origin)
        guard let scaling = CaseScaling(rawValue: fields[6]) else {
            throw fail("scales '\(fields[6])' is not one of \(CaseScaling.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        guard fields[7] == "t" || fields[7] == "-" else { throw fail("timed '\(fields[7])' is not 't' or '-'") }
        let tags = fields[8].split(separator: ",").map(String.init)
        if let unknown = tags.first(where: { !CaseTags.known.contains($0) }) {
            throw fail("tag '\(unknown)' is not in CaseTags.known (add it there if it is meant)")
        }
        return PerfCase(
            id: id, composition: composition, container: container, size: size, count: count, phases: phases,
            scaling: scaling, timed: fields[7] == "t", tags: tags, origin: origin)
    }

    /// Lowercase letters and digits in runs joined by single hyphens.
    static func isKebabCase(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix("-") && !id.hasSuffix("-") && !id.contains("--")
            && id.allSatisfy { ($0.isASCII && $0.isLowercase) || $0.isASCII && $0.isNumber || $0 == "-" }
    }

    // MARK: Compositions

    /// A composition: a leaf's name, `tabs(a,b,…)`, `split(a,b)`,
    /// `follows(a)` or `stress:<scenario>[/<variant>]`.
    static func parseComposition(_ text: String, at origin: CaseOrigin) throws(CaseTableError) -> CaseComposition {
        func fail(_ message: String) -> CaseTableError { CaseTableError(origin: origin, message: message) }
        if text.hasPrefix("stress:") {
            let name = text.dropFirst("stress:".count).split(separator: "/", omittingEmptySubsequences: false)
            guard (1...2).contains(name.count), name.allSatisfy({ !$0.isEmpty }) else {
                throw fail("'\(text)' is not stress:<scenario>[/<variant>]")
            }
            return .adopted(scenario: String(name[0]), variant: name.count == 2 ? String(name[1]) : nil)
        }
        if let open = text.firstIndex(of: "("), text.hasSuffix(")") {
            let head = text[..<open]
            var parts: [CaseComposition] = []
            let inside = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            for part in try splitArguments(inside, at: origin) { parts.append(try parseComposition(part, at: origin)) }
            if parts.contains(where: \.isAdopted) { throw fail("an adopted scenario cannot be a part") }
            if parts.contains(where: \.followsPointer) {
                throw fail("follows(…) is the scene's setting: it wraps the whole composition, never a part")
            }
            return try combine(String(head), parts, at: origin)
        }
        guard let leaf = CaseLeaf(rawValue: text) else {
            throw fail(
                "composition '\(text)' is not one of \(CaseLeaf.allCases.map(\.rawValue).joined(separator: ", ")), "
                    + "\(Self.combinators) or stress:<scenario>[/<variant>]")
        }
        return .leaf(leaf)
    }

    /// The composition a combinator `head` makes of `parts`.
    static func combine(
        _ head: String, _ parts: [CaseComposition], at origin: CaseOrigin
    ) throws(CaseTableError) -> CaseComposition {
        func fail(_ message: String) -> CaseTableError { CaseTableError(origin: origin, message: message) }
        switch head {
        case "tabs":
            guard parts.count >= 2 else { throw fail("tabs(…) takes two parts or more") }
            return .tabs(parts)
        case "split", "sheet", "sheetitem", "popover":
            guard parts.count == 2 else { throw fail("\(head)(…) takes two parts") }
            switch head {
            case "split": return .split(parts[0], parts[1])
            case "sheet": return .sheet(parts[0], parts[1])
            case "popover": return .popover(parts[0], parts[1])
            default: return .sheetItem(parts[0], parts[1])
            }
        case "follows", "alert":
            guard parts.count == 1 else { throw fail("\(head)(…) takes one composition") }
            return head == "alert" ? .alert(parts[0]) : .followsPointer(parts[0])
        case "nsplit":
            guard (2...3).contains(parts.count) else { throw fail("nsplit(…) takes two parts or three") }
            return .navigationSplit(parts)
        default:
            throw fail("'\(head)(…)' is not \(Self.combinators)")
        }
    }

    /// The combinators a composition can be written with, for an error.
    static let combinators = "tabs(…), split(…), follows(…), sheet(…), sheetitem(…), popover(…), alert(…), nsplit(…)"

    /// `a,b(c,d),e` as `a`, `b(c,d)`, `e`: commas inside parentheses belong to
    /// the part they are in.
    static func splitArguments(_ text: String, at origin: CaseOrigin) throws(CaseTableError) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for character in text {
            switch character {
            case "(": depth += 1
            case ")": depth -= 1
            case "," where depth == 0:
                parts.append(current)
                current = ""
                continue
            default: break
            }
            guard depth >= 0 else { throw CaseTableError(origin: origin, message: "unbalanced ')' in '\(text)'") }
            current.append(character)
        }
        guard depth == 0 else { throw CaseTableError(origin: origin, message: "unbalanced '(' in '\(text)'") }
        parts.append(current)
        guard parts.allSatisfy({ !$0.isEmpty }) else {
            throw CaseTableError(origin: origin, message: "an empty part in '\(text)'")
        }
        return parts
    }
}

/// Every mistake found in the tables, reported together.
struct CaseTableErrors: Error, Sendable, CustomStringConvertible {
    let errors: [CaseTableError]

    var description: String { errors.map(\.description).joined(separator: "\n") }
}
