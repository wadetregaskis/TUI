//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseRows.swift
//
//  The model every composition of a perf case reads: rows synthesised from a
//  seed, which a case's script writes to outside any render, as an app's data
//  changes under it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUI

/// The rows a case's page shows, and the state its controls are bound to.
///
/// **Content repeats every ``period`` rows.** A row's text is a function of
/// its id modulo the period (and of its revision, which an edit bumps), never
/// of its id alone. So the rows at the end of a list of 10n are the rows at
/// the end of a list of n, and a case's rerun at 10n (`flat`) or 2n
/// (`linear`) draws the same text wherever it draws the same place: a
/// bottom-anchored case shows the same last rows, with the same heights, at
/// any n. With content keyed by the id alone, the rerun of a bottom-anchored
/// case drew other rows of other heights, and its counts moved for a reason
/// that is not the case's complexity.
@MainActor
@Observable
final class CaseRows {
    /// How often content repeats: a divisor of every `n` the table uses, and
    /// of ten times and twice it.
    nonisolated static let period = 100

    /// One row: an id, which never changes, and a revision, which an edit bumps.
    struct Row: Identifiable, Equatable, Sendable {
        let id: Int
        var revision: Int

        /// The hash every field of the row is synthesised from.
        func hash(seed: UInt64) -> UInt64 { mix(seed, id % CaseRows.period + revision * CaseRows.period) }
    }

    let seed: UInt64
    var rows: [Row]
    /// A search field's text, where a composition has one.
    var query = ""
    /// A list's or table's selection.
    var selection: Int?
    /// The open branches of an outline whose expansion the app keeps
    /// (`outline.bound`, `outline.open`, `outline.list.bound`,
    /// `outline.section.bound`), by row id: every branch from the start
    /// where the case opens its tree.
    var open: Set<Int> = []
    /// A tab view's selection.
    var tab = 0
    /// Whether a sheet, popover or alert bound to it is up (`present`,
    /// `dismiss`).
    var presented = false
    /// The row an item sheet is presented for (`item:i`), `nil` for none.
    var item: Row?
    /// The rows whose toggle is on, in a form.
    var checked: Set<Int> = []
    /// A stepper's value, a slider's, and a date picker's: a fixed instant,
    /// 2026-01-15 12:00 UTC, drawn in UTC, so no count depends on the day
    /// the case is played or the machine's time zone.
    var amount = 10
    var level = 50.0
    var day = Date(timeIntervalSince1970: 1_768_478_400)
    /// The rows as lines of text, for a `TextEditor`: written when the case is
    /// made and by every write to the rows, never in a body, so building it is
    /// not counted as the editor's cost.
    var document = ""
    /// Whether ``document`` is kept: only a page with an editor reads it.
    let keepsDocument: Bool

    /// ``document`` as an `AttributedString`, every third word coloured, for
    /// an attributed editor: made the first time it is read after the
    /// document changes, outside the editor's work, and kept with the
    /// document it was made from.
    var richDocument: AttributedString {
        get {
            if let rich, rich.document == document { return rich.value }
            let value = Self.coloured(document)
            // The caret at the start, the first time, as a `String` editor's
            // is: `AttributedTextSelection()` is the text's end.
            if rich == nil { richSelection = AttributedTextSelection(insertionPoint: value.startIndex) }
            rich = (document, value)
            return value
        }
        set {
            document = String(newValue.characters[...])
            rich = (document, newValue)
        }
    }
    @ObservationIgnored private var rich: (document: String, value: AttributedString)?
    /// The attributed editor's selection, which the editor writes as its
    /// caret moves: read by the editor alone, so not observed.
    @ObservationIgnored var richSelection = AttributedTextSelection()

    /// `text` with every third word in a colour of its own.
    private static func coloured(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        var word = 0
        var start = result.startIndex
        var index = start
        while index < result.endIndex {
            let next = result.characters.index(after: index)
            if result.characters[index] == " " || result.characters[index] == "\n" {
                if word.isMultiple(of: 3), start < index { result[start..<index].foregroundColor = .cyan }
                word += 1
                start = next
            }
            index = next
        }
        return result
    }

    /// The rows as a tree, for an outline: made when the case is, and only for
    /// a page with an outline, so neither a body nor another case pays for it.
    /// Not rebuilt by the writes: no case writes to an outline's rows.
    @ObservationIgnored private(set) var tree: [Node] = []
    /// The members of every group of ``tree``, as roots of their own: closed,
    /// an outline of 18 rows in every 100, more than a lazy stack draws whole.
    /// Made with ``tree``, so its storage is the same from pass to pass.
    @ObservationIgnored private(set) var forest: [Node] = []
    @ObservationIgnored private var nextID: Int

    init(count: Int, seed: UInt64, keepsDocument: Bool, keepsTree: Bool = false, opensTree: Bool = false) {
        self.seed = seed
        self.keepsDocument = keepsDocument
        rows = (0..<count).map { Row(id: $0, revision: 0) }
        nextID = count
        rewriteDocument()
        if keepsTree {
            tree = [Self.tree(of: rows)]
            forest = tree.flatMap { $0.children ?? [] }.flatMap { $0.children ?? [] }
        }
        if opensTree { open = Self.branchIDs(of: tree) }
    }

    // MARK: The tree

    /// A node of ``tree``: a row, and the rows beneath it, `nil` for a leaf.
    /// A value with its children stored, as an app's tree is, so a `Table`
    /// keeps its outline from pass to pass while the tree is the same.
    struct Node: Identifiable, Sendable {
        let row: Row
        var children: [Self]?
        var id: Int { row.id }
    }

    /// Rows per group, and per group within a group: a divisor of ``period``.
    nonisolated static let outlineFanOut = 10

    /// One root over every row: a group every `fanOut²` rows, in each a group
    /// every `fanOut` rows, and the rest leaves — so opened all the way, the
    /// tree shows every row and one more, three deep. The root is a row of its
    /// own, with an id no row has.
    private static func tree(of rows: [Row]) -> Node {
        let fanOut = outlineFanOut
        let group = fanOut * fanOut
        var groups: [Node] = []
        var start = 0
        while start < rows.count {
            let end = min(start + group, rows.count)
            var members: [Node] = []
            var index = start + 1
            while index < end {
                if index.isMultiple(of: fanOut) {
                    let inner = rows[(index + 1)..<min(index + fanOut, end)].map { Node(row: $0) }
                    members.append(Node(row: rows[index], children: inner))
                    index += fanOut
                } else {
                    members.append(Node(row: rows[index]))
                    index += 1
                }
            }
            groups.append(Node(row: rows[start], children: members))
            start = end
        }
        return Node(row: Row(id: -1, revision: 0), children: groups)
    }

    /// The ids of every branch in `nodes`, however deep.
    private static func branchIDs(of nodes: [Node]) -> Set<Int> {
        var ids = Set<Int>()
        var stack = nodes
        while let node = stack.popLast() {
            guard let children = node.children else { continue }
            ids.insert(node.id)
            stack += children
        }
        return ids
    }

    // MARK: Content

    /// A row's title: two to five words.
    func title(_ row: Row) -> String {
        let hash = row.hash(seed: seed)
        return Synth.sentence(hash, words: 2 + Int(hash % 4))
    }

    /// A row's name, slug and status, for a table's columns.
    func name(_ row: Row) -> String { Synth.name(row.hash(seed: seed)) }
    func slug(_ row: Row) -> String { Synth.slug(row.hash(seed: seed)) }
    func status(_ row: Row) -> String { Synth.status(row.hash(seed: seed)) }

    /// A number from the row, as a table's size column shows it.
    func size(_ row: Row) -> Int { Int(row.hash(seed: seed) % 100_000) }

    /// A line of the editor's document: eight to nineteen words, so some
    /// lines wrap at a hundred columns and some do not.
    func line(_ row: Row) -> String {
        let hash = row.hash(seed: seed)
        return Synth.sentence(hash, words: 8 + Int(hash % 12))
    }

    /// A message's lines: one to three.
    func message(_ row: Row) -> String {
        let hash = row.hash(seed: seed)
        return (0...Int(hash % 3)).map { Synth.sentence(hash >> (8 * $0), words: 3 + $0) }.joined(separator: "\n")
    }

    /// The rows the search shows: those whose title holds the query, filtered
    /// in the app's own code, O(n), as an app filters.
    var shown: [Row] {
        query.isEmpty ? rows : rows.filter { title($0).contains(query) }
    }

    // MARK: Writes

    /// `k` new rows at the end.
    func append(_ count: Int) {
        rows += (0..<count).map { Row(id: nextID + $0, revision: 0) }
        nextID += count
        rewriteDocument()
    }

    /// The middle row's content changed.
    func editMiddle() {
        guard !rows.isEmpty else { return }
        rows[rows.count / 2].revision += 1
        rewriteDocument()
    }

    /// The row at `index` removed, if there is one.
    func remove(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
        rewriteDocument()
    }

    /// The row at `from` moved to `to`, both clamped to the rows there are.
    func move(from: Int, to: Int) {
        guard !rows.isEmpty else { return }
        let row = rows.remove(at: min(from, rows.count - 1))
        rows.insert(row, at: min(to, rows.count))
        rewriteDocument()
    }

    /// Every row given new content.
    func replace() {
        for index in rows.indices { rows[index].revision += 1 }
        rewriteDocument()
    }

    private func rewriteDocument() {
        guard keepsDocument else { return }
        document = rows.map { line($0) }.joined(separator: "\n")
    }
}
