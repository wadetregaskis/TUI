//  🖥️ TUI — A Terminal UI framework for Swift
//  BigTextSession.swift
//
//  A source pane over a large document: one TextEditor holding a few
//  megabytes of JSON, typed into in the middle, where a key's cost should be
//  the edit's and not the document's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUI

// MARK: - The document

/// The text the editor edits, and the caret the session puts in it.
@Observable
@MainActor
final class BigTextDocument {
    var text: String
    var selection: TextSelection?

    init(text: String) {
        self.text = text
    }
}

// MARK: - The page

/// A status line saying how long the text is, over a `TextEditor` of the whole
/// of it, which holds the focus.
struct BigTextPage: View {
    let document: BigTextDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(document.text.utf8.count) bytes")
            TextEditor(
                text: Binding(get: { document.text }, set: { document.text = $0 }),
                selection: Binding(get: { document.selection }, set: { document.selection = $0 }))
        }
    }
}

// MARK: - The script

/// Someone editing a record in the middle of a 3 MB JSON file, as tuitree's
/// source pane is (its M4 feedback, item 3): runs of typing, corrections, a
/// new line now and then, the caret moved a line or a few, and the odd jump
/// to another record, which the session makes by writing the selection, as a
/// problems list's Return does.
@MainActor
final class BigTextSession: StressSession {
    private let document: BigTextDocument
    private var random: SessionRandom
    /// Characters left in the run being typed.
    private var run = 0
    /// Backspaces left in the correction being made.
    private var erasing = 0
    /// How long the text should be, in bytes, from the keys the session sent:
    /// what the status line and the model must say.
    private var expectedBytes: Int

    /// Records in the document: forty thousand at the default scale, 3.2 MB.
    static func records(_ config: StressConfig) -> Int { config.sized(40_000) }

    init(config: StressConfig) {
        let seed = config.seed
        let text = (0..<Self.records(config)).map { index in
            let h = mix(seed, index)
            let name = Synth.sentence(h, words: 2 + Int(h % 3))
            return "  {\"id\": \(index), \"name\": \"\(name)\", \"size\": \(h % 100_000), \"ok\": \(h & 1 == 0)},"
        }.joined(separator: "\n")
        document = BigTextDocument(text: "[\n" + text + "\n]")
        expectedBytes = document.text.utf8.count
        random = SessionRandom(seed: seed)
    }

    var page: BigTextPage { BigTextPage(document: document) }

    func step(_ index: Int) -> SessionStep {
        if index == 0 { return jump(to: document.text.utf8.count / 2) }
        if run > 0 {
            run -= 1
            return typed()
        }
        if erasing > 0 {
            erasing -= 1
            return erase()
        }
        switch random.pick([("type", 50), ("erase", 10), ("newline", 4), ("move", 20), ("jump", 2)]) {
        case "type":
            run = random.within(3...30)
            return typed()
        case "erase":
            erasing = random.within(1...6)
            return erase()
        case "newline":
            expectedBytes += 1
            return SessionStep(action: "newline", keys: [KeyEvent(key: .enter)])
        case "move":
            let key: Key = [.up, .down, .left, .right][random.below(4)]
            return SessionStep(action: "move", keys: Array(repeating: KeyEvent(key: key), count: random.within(1...3)))
        default:
            // Into the middle half, so no key reaches either end.
            let bytes = document.text.utf8.count
            return jump(to: bytes / 4 + random.below(bytes / 2))
        }
    }

    /// The next character typed: letters, and a space every so often.
    private func typed() -> SessionStep {
        expectedBytes += 1
        let roll = random.below(26 + 5)
        let key = roll < 26 ? KeyEvent(key: .character(Character(UnicodeScalar(UInt8(97 + roll))))) : KeyEvent(key: .space)
        return SessionStep(action: "type", keys: [key])
    }

    /// Backspace, which takes a byte: the text is ASCII, and the caret is
    /// never at its start.
    private func erase() -> SessionStep {
        expectedBytes -= 1
        return SessionStep(action: "backspace", keys: [KeyEvent(key: .backspace)])
    }

    /// The caret put at the `offset`th byte, by the app: the text is ASCII,
    /// so a byte is a character.
    private func jump(to offset: Int) -> SessionStep {
        let text = document.text
        let place = text.utf8.index(text.startIndex, offsetBy: max(1, offset))
        document.selection = TextSelection(insertionPoint: place)
        return SessionStep(action: "jump")
    }

    /// The status line says the length the keys left, and so does the model.
    func check(_ screen: [String], after index: Int) -> String? {
        let bytes = document.text.utf8.count
        guard bytes == expectedBytes else { return "the text is \(bytes) bytes, not the \(expectedBytes) the keys left" }
        guard screen.first?.hasPrefix("\(bytes) bytes") == true else {
            return "the status line does not say \(bytes) bytes"
        }
        return nil
    }

    static let descriptor = SessionDescriptor(
        id: "bigtext",
        summary: "a TextEditor holding 3.2 MB of JSON, typed into in the middle",
        exercises: "a key's edit, the text written back and laid out again, against the size of the document",
        make: { config, width, height, cold in
            DrivenSession(BigTextSession(config: config), width: width, height: height, cold: cold)
        })
}
