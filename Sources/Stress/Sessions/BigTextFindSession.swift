//  🖥️ TUI — A Terminal UI framework for Swift
//  BigTextFindSession.swift
//
//  `bigtext` with its find bar up: the same 3.2 MB of JSON with a query that
//  matches on every line, typed into (`bigtext-find`), the query itself typed
//  and stepped through (`bigtext-find-query`), and every match replaced
//  (`bigtext-replace-all`). What a key costs while every match is tinted and
//  counted, and what one Replace All costs against the matches it replaces.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - The page

/// ``BigTextPage`` with its editor's find bar up from the first frame, as an
/// app presenting it would have it.
struct BigTextFindPage: View {
    let document: BigTextDocument

    var body: some View {
        BigTextPage(document: document).findNavigator(isPresented: .constant(true))
    }
}

/// What the find bar's counter says on `screen`: the current match and how
/// many there are, read from the row that holds Done (`3/40000`), or `nil`
/// where no such row is drawn.
@MainActor
private func findCounter(on screen: [String]) -> (current: Int, total: Int)? {
    for row in screen where row.contains("Done") {
        for word in row.split(separator: " ") {
            let parts = word.split(separator: "/")
            if parts.count == 2, let current = Int(parts[0]), let total = Int(parts[1]) { return (current, total) }
        }
    }
    return nil
}

// MARK: - Typing with the bar up

/// `bigtext`'s keys with the find bar up on a query that every record
/// matches: the first steps type the query and click into the text, and
/// `bigtext`'s script plays from there. A key's cost should still be the
/// edit's and the screen's, not the document's or its matches'.
@MainActor
final class BigTextFindSession: StressSession {
    private let document: BigTextDocument
    private var script: BigTextScript
    private let records: Int

    /// The query: every record has an `"ok"` key, so every line matches.
    static let query = "ok"
    /// The steps before the script's: the query's characters, then a click.
    private static var prelude: Int { query.count + 1 }

    init(config: StressConfig) {
        document = BigTextDocument(text: BigTextSession.documentText(config))
        script = BigTextScript(seed: config.seed, bytes: document.text.utf8.count)
        records = BigTextSession.records(config)
    }

    var page: BigTextFindPage { BigTextFindPage(document: document) }

    func step(_ index: Int) -> SessionStep {
        let query = Array(Self.query)
        if index < query.count { return SessionStep(action: "query", keys: [KeyEvent(key: .character(query[index]))]) }
        if index == query.count {
            // Into the text, below the bar's three rows and the status line.
            let (x, y) = (10, 12)
            return SessionStep(
                action: "focus",
                mouse: [
                    MouseEvent(button: .left, phase: .pressed, x: x, y: y),
                    MouseEvent(button: .left, phase: .released, x: x, y: y),
                ])
        }
        return script.step(index - Self.prelude, bytes: document.text.utf8.count) { offset in
            let text = document.text
            document.selection = TextSelection(insertionPoint: text.utf8.index(text.startIndex, offsetBy: offset))
        }
    }

    /// `bigtext`'s check, and the bar counts a match for every record once
    /// the query is typed.
    func check(_ screen: [String], after index: Int) -> String? {
        if index >= Self.query.count - 1 {
            guard let counter = findCounter(on: screen) else { return "the find bar's counter is not drawn" }
            guard counter.total >= records else {
                return "the find bar counts \(counter.total) matches of \"\(Self.query)\" in \(records) records"
            }
        }
        return script.check(screen, bytes: document.text.utf8.count)
    }

    static let descriptor = SessionDescriptor(
        id: "bigtext-find",
        summary: "bigtext with the find bar up on a query every line matches, typed into in the middle",
        exercises: "a key with every match tinted and counted: the matches found again after the edit, "
            + "the bar's count, the rows' tints, against the size of the document and how many matches it has",
        make: { config, width, height, cold in
            DrivenSession(BigTextFindSession(config: config), width: width, height: height, cold: cold)
        },
        // Keys as a person types them, ten a second.
        stepNanos: 100_000_000)
}

// MARK: - Typing the query

/// The find bar's own field typed into over the same document: a query
/// spelled a character at a time, stepped through with Return, and taken
/// back, over and over. Every key changes what matches, so the whole
/// document is searched; what the step costs beyond that one search is what
/// the session prices.
@MainActor
final class BigTextFindQuerySession: StressSession {
    private let document: BigTextDocument
    private let records: Int
    /// The query as the keys so far left it.
    private var typed = ""

    /// The query spelled out: every record has a `"size"` key.
    static let query = "size"
    /// How many times Return steps to the next match before the query is
    /// taken back.
    private static let returns = 3

    init(config: StressConfig) {
        document = BigTextDocument(text: BigTextSession.documentText(config))
        records = BigTextSession.records(config)
    }

    var page: BigTextFindPage { BigTextFindPage(document: document) }

    func step(_ index: Int) -> SessionStep {
        let query = Array(Self.query)
        let phase = index % (2 * query.count + Self.returns)
        if phase < query.count {
            typed.append(query[phase])
            return SessionStep(action: "query", keys: [KeyEvent(key: .character(query[phase]))])
        }
        if phase < query.count + Self.returns { return SessionStep(action: "next", keys: [KeyEvent(key: .enter)]) }
        typed.removeLast()
        return SessionStep(action: "query-erase", keys: [KeyEvent(key: .backspace)])
    }

    /// The text is untouched, and the bar counts a match for every record
    /// while the whole query is typed, and none while there is no query.
    func check(_ screen: [String], after index: Int) -> String? {
        guard index >= 0 else { return nil }
        guard let counter = findCounter(on: screen) else { return "the find bar's counter is not drawn" }
        if typed.isEmpty, counter.total != 0 { return "the find bar counts \(counter.total) matches of no query" }
        if typed == Self.query, counter.total < records {
            return "the find bar counts \(counter.total) matches of \"\(typed)\" in \(records) records"
        }
        guard screen.first?.hasPrefix("\(document.text.utf8.count) bytes") == true else {
            return "the status line does not say \(document.text.utf8.count) bytes"
        }
        return nil
    }

    static let descriptor = SessionDescriptor(
        id: "bigtext-find-query",
        summary: "bigtext's find bar typed into: a query spelled, stepped through and taken back, over 3.2 MB",
        exercises: "a key in the find bar's field: the document searched for the new query, its first match "
            + "selected and scrolled to, every match on screen tinted, Return stepping to the next",
        make: { config, width, height, cold in
            DrivenSession(BigTextFindQuerySession(config: config), width: width, height: height, cold: cold)
        },
        // Keys as a person types them, ten a second.
        stepNanos: 100_000_000)
}

// MARK: - Replace All

/// Replace All over a document where every record matches: the query finds
/// `ok` whatever its case, and each step retypes the replacement in the
/// other case and presses Replace All, so every step replaces every match.
/// A sixteenth of `bigtext`'s document at the default scale (2,500 records,
/// 200 KB, as many matches): the Replace All this session was written to
/// price took a second there and would not have finished at `bigtext`'s size.
/// `--scale 16` is that size.
@MainActor
final class BigTextReplaceAllSession: StressSession {
    private let document: BigTextDocument
    /// How many times Replace All has been pressed.
    private var replaced = 0

    static let query = "ok"
    /// The steps before the first Replace All: the query's characters, then
    /// the focus moved to the replacement field.
    private static var prelude: Int { query.count + 1 }
    /// The focus stops from the query field to the replacement field: the
    /// two arrows, Done, the case toggle and the placement button between.
    private static let stopsToReplacement = 6

    /// Records in the document.
    static func records(_ config: StressConfig) -> Int { config.sized(2_500) }

    init(config: StressConfig) {
        let records = BigTextSession.documentRecords(config, count: Self.records(config))
        document = BigTextDocument(text: "[\n" + records.map(\.line).joined(separator: "\n") + "\n]")
    }

    var page: BigTextFindPage { BigTextFindPage(document: document) }

    /// What the replacement is on the `count`th Replace All.
    private static func replacement(_ count: Int) -> String { count.isMultiple(of: 2) ? "OK" : "ok" }

    func step(_ index: Int) -> SessionStep {
        let query = Array(Self.query)
        if index < query.count { return SessionStep(action: "query", keys: [KeyEvent(key: .character(query[index]))]) }
        if index == query.count {
            return SessionStep(
                action: "focus", keys: Array(repeating: KeyEvent(key: .tab), count: Self.stopsToReplacement))
        }
        // The replacement retyped in the field, Replace All reached and
        // pressed, and the focus put back on the field for the next step.
        var keys: [KeyEvent] = []
        if replaced > 0 { keys += Array(repeating: KeyEvent(key: .backspace), count: Self.query.count) }
        keys += Self.replacement(replaced).map { KeyEvent(key: .character($0)) }
        keys += [KeyEvent(key: .tab), KeyEvent(key: .tab), KeyEvent(key: .enter)]
        keys += [KeyEvent(key: .tab, shift: true), KeyEvent(key: .tab, shift: true)]
        replaced += 1
        return SessionStep(action: "replace-all", keys: keys)
    }

    /// Every record's key is in the case the last Replace All wrote, and none
    /// in the other.
    func check(_ screen: [String], after index: Int) -> String? {
        guard index >= Self.prelude, replaced > 0 else { return nil }
        let written = Self.replacement(replaced - 1)
        let other = Self.replacement(replaced)
        let text = document.text
        guard text.contains("\"\(written)\": "), !text.contains("\"\(other)\": ") else {
            return "after Replace All \(replaced) the records' keys are not all \"\(written)\""
        }
        return nil
    }

    static let descriptor = SessionDescriptor(
        id: "bigtext-replace-all",
        summary: "the find bar's Replace All over 2,500 records that all match, every step",
        exercises: "one Replace All of thousands of matches: the matches found, the text built with each "
            + "replaced, written back as one undo step and laid out again",
        make: { config, width, height, cold in
            DrivenSession(BigTextReplaceAllSession(config: config), width: width, height: height, cold: cold)
        },
        // Keys as a person types them, ten a second.
        stepNanos: 100_000_000)
}
