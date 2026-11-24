//  🖥️ TUI — A Terminal UI framework for Swift
//  BigTextRichFindSession.swift
//
//  `bigtext-rich` with its find bar up: the same 3.2 MB of coloured JSON in
//  an attributed TextEditor, with a query that matches on every line, typed
//  into in the middle. What a key costs an attributed editor while every
//  match is tinted and counted, where `bigtext-find` prices a `String` one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - The page

/// ``BigTextRichPage`` with its editor's find bar up from the first frame.
struct BigTextRichFindPage: View {
    let document: BigTextRichDocument

    var body: some View {
        BigTextRichPage(document: document).findNavigator(isPresented: .constant(true))
    }
}

// MARK: - The session

/// `bigtext-rich`'s keys with the find bar up on a query every record
/// matches: the first steps type the query and click into the text, as
/// `bigtext-find`'s do, and `bigtext-rich`'s script plays from there.
@MainActor
final class BigTextRichFindSession: StressSession {
    private let document: BigTextRichDocument
    private var script: BigTextScript
    private let records: Int

    /// The query: every record has an `"ok"` key, so every line matches.
    static let query = BigTextFindSession.query
    /// The steps before the script's: the query's characters, then a click.
    private static var prelude: Int { query.count + 1 }

    init(config: StressConfig) {
        document = BigTextRichDocument(text: BigTextRichSession.document(config))
        script = BigTextScript(seed: config.seed, bytes: document.bytes)
        records = BigTextSession.records(config)
    }

    var page: BigTextRichFindPage { BigTextRichFindPage(document: document) }

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
        return script.step(index - Self.prelude, bytes: document.bytes) { offset in
            let text = document.text
            document.selection = AttributedTextSelection(
                insertionPoint: text.characters.index(text.startIndex, offsetBy: offset))
        }
    }

    /// `bigtext-rich`'s check, and the bar counts a match for every record
    /// once the query is typed.
    func check(_ screen: [String], after index: Int) -> String? {
        if index >= Self.query.count - 1 {
            guard let counter = findCounter(on: screen) else { return "the find bar's counter is not drawn" }
            guard counter.total >= records else {
                return "the find bar counts \(counter.total) matches of \"\(Self.query)\" in \(records) records"
            }
        }
        return script.check(screen, bytes: document.bytes)
    }

    static let descriptor = SessionDescriptor(
        id: "bigtext-rich-find",
        summary: "bigtext-rich with the find bar up on a query every line matches, typed into in the middle",
        exercises: "an attributed editor's key with every match tinted and counted: the matches brought up to date "
            + "with the edit, the bar's count read of the value's characters, the rows' tints",
        make: { config, width, height, cold in
            DrivenSession(BigTextRichFindSession(config: config), width: width, height: height, cold: cold)
        },
        // Keys as a person types them, ten a second, as `bigtext-find`'s.
        stepNanos: 100_000_000)
}
