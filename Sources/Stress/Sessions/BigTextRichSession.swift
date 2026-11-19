//  🖥️ TUI — A Terminal UI framework for Swift
//  BigTextRichSession.swift
//
//  `bigtext` over an AttributedString: the same 3.2 MB of JSON, its values
//  coloured, in an attributed TextEditor typed into in the middle, where a
//  key's cost should be the edit's and not the document's or its runs'.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUI

// MARK: - The document

/// The attributed text the editor edits, and the selection it exchanges with
/// the app.
@Observable
@MainActor
final class BigTextRichDocument {
    /// The text, observed as the macro observes a stored property, but written
    /// without the macro's equality check.
    ///
    /// The macro's setter notifies only a value that is not `==` the one
    /// before (`shouldNotifyObservers`), and `AttributedString`'s `==`
    /// compares two values in different storage a character at a time: up to
    /// the edit, half the document a key. That was 98.7% of this session's
    /// time (Time Profiler, release, 2026-11-19), the app's cost rather than
    /// the editor's, and it hid the editor's. An app that binds an attributed
    /// editor to a stored property of an `@Observable` pays it on every key.
    var text: AttributedString {
        get {
            access(keyPath: \.text)
            return storedText
        }
        set {
            withMutation(keyPath: \.text) { storedText = newValue }
        }
    }
    @ObservationIgnored private var storedText: AttributedString
    var selection = AttributedTextSelection()

    init(text: AttributedString) {
        storedText = text
    }

    /// How long the text is in bytes: its characters, the text being ASCII.
    /// Not its UTF-8 view, which macOS 15's Foundation does not have.
    var bytes: Int { text.characters.count }
}

// MARK: - The page

/// ``BigTextPage`` over the attributed text.
struct BigTextRichPage: View {
    let document: BigTextRichDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(document.bytes) bytes")
            TextEditor(
                text: Binding(get: { document.text }, set: { document.text = $0 }),
                selection: Binding(get: { document.selection }, set: { document.selection = $0 }))
        }
    }
}

// MARK: - The session

/// `bigtext`'s keys in an attributed editor: the same records, each line's
/// four values coloured: eight runs a line (its last plain run joins the
/// break and the next line's first), 320,000 at the default scale. Typed text takes
/// the attributes of the character before it, as macOS's text system gives
/// it.
@MainActor
final class BigTextRichSession: StressSession {
    private let document: BigTextRichDocument
    private var script: BigTextScript

    /// The colour each of a record's four values is drawn in, in order.
    private static let valueColours: [Color] = [.cyan, .green, .yellow, .magenta]

    /// `bigtext`'s document, its values coloured.
    static func document(_ config: StressConfig) -> AttributedString {
        var text = AttributedString("[\n")
        for (index, record) in BigTextSession.documentRecords(config).enumerated() {
            if index > 0 { text.append(AttributedString("\n")) }
            var value = 0
            for part in record.parts {
                var run = AttributedString(part.text)
                if part.isValue {
                    run.foregroundColor = valueColours[value]
                    value += 1
                }
                text.append(run)
            }
        }
        text.append(AttributedString("\n]"))
        return text
    }

    init(config: StressConfig) {
        document = BigTextRichDocument(text: Self.document(config))
        script = BigTextScript(seed: config.seed, bytes: document.bytes)
    }

    var page: BigTextRichPage { BigTextRichPage(document: document) }

    func step(_ index: Int) -> SessionStep {
        script.step(index, bytes: document.bytes) { offset in
            let text = document.text
            document.selection = AttributedTextSelection(
                insertionPoint: text.characters.index(text.startIndex, offsetBy: offset))
        }
    }

    /// The status line says the length the keys left, and so does the model.
    func check(_ screen: [String], after index: Int) -> String? {
        script.check(screen, bytes: document.bytes)
    }

    static let descriptor = SessionDescriptor(
        id: "bigtext-rich",
        summary: "bigtext over an AttributedString: 3.2 MB of JSON, its values coloured, typed into in the middle",
        exercises: "an attributed editor's key against the size of the document and its runs: the edit made in the value, "
            + "written back, laid out again, and the styles of the lines on screen read from the runs",
        make: { config, width, height, cold in
            DrivenSession(BigTextRichSession(config: config), width: width, height: height, cold: cold)
        })
}

// MARK: - A record's runs

extension BigTextRecord {
    /// The line, as runs of punctuation and keys (`false`) and of values
    /// (`true`), in order: the values are what `bigtext-rich` colours.
    var parts: [(text: String, isValue: Bool)] {
        [
            ("  {\"id\": ", false), ("\(id)", true), (", \"name\": ", false), ("\"\(name)\"", true),
            (", \"size\": ", false), ("\(size)", true), (", \"ok\": ", false), ("\(ok)", true), ("},", false),
        ]
    }
}
