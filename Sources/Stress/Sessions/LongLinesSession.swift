//  🖥️ TUI — A Terminal UI framework for Swift
//  LongLinesSession.swift
//
//  A TextEditor that scrolls sideways (`.textEditorWrapsLines(false)`) over
//  lines ten thousand characters long, typed into and moved about far to the
//  right: what a frame costs when each line on screen is much longer than the
//  window that shows it (H-88, TEXTIN-7).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUI

// MARK: - The page

/// A status line saying how long the text is, over an editor that scrolls
/// sideways rather than wrapping, which holds the focus.
struct LongLinesPage: View {
    let document: BigTextDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(document.text.utf8.count) bytes")
            TextEditor(
                text: Binding(get: { document.text }, set: { document.text = $0 }),
                selection: Binding(get: { document.selection }, set: { document.selection = $0 })
            )
            .textEditorWrapsLines(false)
        }
    }
}

// MARK: - The session

/// Someone editing a log or a minified file whose lines are far wider than the
/// screen, with the editor scrolled sideways to keep the caret in view: runs
/// of typing, corrections, the caret moved a few characters or lines, and the
/// odd jump to another far column, made by writing the selection. Every line
/// on screen is ``lineLength(_:)`` characters; a quarter are ASCII, a quarter
/// have tabs, a quarter wide CJK, and a quarter combining accents, a ZWJ
/// emoji and tabs, so a line's cells are not its characters.
@MainActor
final class LongLinesSession: StressSession {
    private let document: BigTextDocument
    private var script: LongLinesScript

    /// Lines in the document: more than a screen has rows.
    nonisolated static let lineCount = 30

    /// Characters a line: ten thousand at the default scale.
    static func lineLength(_ config: StressConfig) -> Int { config.sized(10_000) }

    /// The document: ``lineCount`` lines of ``lineLength(_:)`` characters each.
    static func documentText(_ config: StressConfig) -> String {
        (0..<lineCount).map { line(at: $0, length: lineLength(config), seed: config.seed) }.joined(separator: "\n")
    }

    /// Line `index`: words, and between them what its quarter puts there,
    /// `length` characters in all.
    static func line(at index: Int, length: Int, seed: UInt64) -> String {
        let words = ["alpha", "beta", "gamma", "delta", "log", "value", "id", "x"]
        let wide = ["漢字", "東京", "かな", "全角", "한국어"]
        let marked = ["cafe\u{301}", "nai\u{308}ve", "👩‍💻", "re\u{301}sume\u{301}"]
        var random = SessionRandom(seed: mix(seed, index))
        var line = ""
        var characters = 0
        while characters < length {
            var token = words[random.below(words.count)]
            switch index % 4 {
            case 1: token += random.below(3) == 0 ? "\t" : " "
            case 2: token += " " + wide[random.below(wide.count)] + " "
            case 3: token += (random.below(4) == 0 ? "\t" : " ") + marked[random.below(marked.count)] + " "
            default: token += " "
            }
            // Whole characters only: a token's own never join the next's.
            let taken = token.prefix(length - characters)
            line += taken
            characters += taken.count
        }
        return line
    }

    init(config: StressConfig) {
        let text = Self.documentText(config)
        document = BigTextDocument(text: text)
        script = LongLinesScript(seed: config.seed, bytes: text.utf8.count, lineLength: Self.lineLength(config))
    }

    var page: LongLinesPage { LongLinesPage(document: document) }

    func step(_ index: Int) -> SessionStep {
        script.step(index) { line, column in
            document.selection = TextSelection(insertionPoint: Self.index(ofColumn: column, inLine: line, of: document.text))
        }
    }

    /// The string index of the `column`th character of `line` of `text`.
    private static func index(ofColumn column: Int, inLine line: Int, of text: String) -> String.Index {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let chosen = lines[min(line, lines.count - 1)]
        return chosen.index(chosen.startIndex, offsetBy: column, limitedBy: chosen.endIndex) ?? chosen.endIndex
    }

    /// The status line says the length the keys left, and so does the model.
    func check(_ screen: [String], after index: Int) -> String? {
        script.check(screen, bytes: document.text.utf8.count)
    }

    static let descriptor = SessionDescriptor(
        id: "longlines",
        summary: "a TextEditor scrolled sideways over 30 lines of 10,000 characters, typed into far to the right",
        exercises: "a sideways editor's rows against the length of its lines: tabs, wide and combining characters",
        make: { config, width, height, cold in
            DrivenSession(LongLinesSession(config: config), width: width, height: height, cold: cold)
        })
}

// MARK: - The script

/// The keys `longlines` plays, and the length they leave. A correction takes
/// back only letters typed since the caret last moved, so every Backspace
/// takes one ASCII byte, whatever the line holds around it.
struct LongLinesScript {
    private var random: SessionRandom
    private let lineLength: Int
    /// Characters left in the run being typed.
    private var run = 0
    /// Backspaces left in the correction being made.
    private var erasing = 0
    /// Letters typed since the caret last moved: what a correction may take.
    private var typedHere = 0
    /// How long the text should be, in bytes, from the keys the session sent.
    private var expectedBytes: Int

    init(seed: UInt64, bytes: Int, lineLength: Int) {
        random = SessionRandom(seed: seed)
        expectedBytes = bytes
        self.lineLength = lineLength
    }

    /// Step `index`'s keys. A jump has the app put the caret at a character
    /// of a line (`placeCaret`) and sends no key.
    mutating func step(_ index: Int, placeCaret: (_ line: Int, _ column: Int) -> Void) -> SessionStep {
        if index == 0 { return jump(placeCaret) }
        if run > 0 {
            run -= 1
            return typed()
        }
        if erasing > 0 {
            erasing -= 1
            return erase()
        }
        switch random.pick([("type", 50), ("erase", 10), ("move", 30), ("jump", 2)]) {
        case "type":
            run = random.within(3...30)
            return typed()
        case "erase" where typedHere > 0:
            erasing = min(typedHere, random.within(1...6)) - 1
            return erase()
        case "move", "erase":
            typedHere = 0
            let key: Key = [.up, .down, .left, .right][random.below(4)]
            return SessionStep(action: "move", keys: Array(repeating: KeyEvent(key: key), count: random.within(1...3)))
        default:
            return jump(placeCaret)
        }
    }

    /// The next character typed: a letter, or a space every so often.
    private mutating func typed() -> SessionStep {
        expectedBytes += 1
        typedHere += 1
        let roll = random.below(26 + 5)
        let key = roll < 26 ? KeyEvent(key: .character(Character(UnicodeScalar(UInt8(97 + roll))))) : KeyEvent(key: .space)
        return SessionStep(action: "type", keys: [key])
    }

    /// Backspace, which takes a letter typed since the caret moved.
    private mutating func erase() -> SessionStep {
        expectedBytes -= 1
        typedHere -= 1
        return SessionStep(action: "backspace", keys: [KeyEvent(key: .backspace)])
    }

    /// The caret put far along a line, by the app: between 60% and 90% of
    /// the way, so the editor scrolls thousands of cells sideways.
    private mutating func jump(_ placeCaret: (Int, Int) -> Void) -> SessionStep {
        typedHere = 0
        let column = lineLength * 6 / 10 + random.below(max(1, lineLength * 3 / 10))
        placeCaret(random.below(LongLinesSession.lineCount), column)
        return SessionStep(action: "jump")
    }

    /// The status line says the length the keys left, and so does the model,
    /// whose text is `bytes` long.
    func check(_ screen: [String], bytes: Int) -> String? {
        guard bytes == expectedBytes else { return "the text is \(bytes) bytes, not the \(expectedBytes) the keys left" }
        guard screen.first?.hasPrefix("\(bytes) bytes") == true else {
            return "the status line does not say \(bytes) bytes"
        }
        return nil
    }
}
