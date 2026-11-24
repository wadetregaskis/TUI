//  🖥️ TUI — A Terminal UI framework for Swift
//  BigTextUndoSession.swift
//
//  `bigtext` undone and redone: the same 3.2 MB of JSON, two runs of typing
//  in the middle, then both undone and both redone, over and over. What an
//  undo and a redo cost against the size of the document.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Two runs of typing, the caret moved a character between them so each is
/// a step of its own, then Ctrl-Z twice and Ctrl-Shift-Z twice, over and
/// over, in `bigtext`'s document. An undo or a redo should cost what the step
/// changed and the screen, not the document.
@MainActor
final class BigTextUndoSession: StressSession {
    private let document: BigTextDocument
    private var random: SessionRandom
    /// The steps left in the cycle being played, the next first.
    private var pending: [SessionStep] = []
    /// How long the text should be, in bytes, from the keys sent.
    private var expectedBytes: Int
    /// The lengths of the runs the next undos take back, the newest last, and
    /// of the runs the next redos put back, the next last.
    private var undoable: [Int] = []
    private var redoable: [Int] = []

    private static let undoKey = KeyEvent(key: .character("z"), ctrl: true)
    private static let redoKey = KeyEvent(key: .character("Z"), ctrl: true, shift: true)

    init(config: StressConfig) {
        document = BigTextDocument(text: BigTextSession.documentText(config))
        random = SessionRandom(seed: config.seed)
        expectedBytes = document.text.utf8.count
    }

    var page: BigTextPage { BigTextPage(document: document) }

    func step(_ index: Int) -> SessionStep {
        if index == 0 {
            // Into the middle, as `bigtext` starts.
            let text = document.text
            document.selection = TextSelection(
                insertionPoint: text.utf8.index(text.startIndex, offsetBy: text.utf8.count / 2))
            return SessionStep(action: "jump")
        }
        if pending.isEmpty { pending = cycle().reversed() }
        let step = pending.removeLast()
        switch step.action {
        case "type": expectedBytes += 1
        case "undo":
            let run = undoable.removeLast()
            expectedBytes -= run
            redoable.append(run)
        case "redo":
            let run = redoable.removeLast()
            expectedBytes += run
            undoable.append(run)
        default: break
        }
        return step
    }

    /// One cycle's steps: a run typed, the caret moved left, another run, both
    /// undone, both redone.
    private func cycle() -> [SessionStep] {
        let first = random.within(3...20)
        let second = random.within(3...20)
        // A new edit forgets redo.
        undoable += [first, second]
        redoable.removeAll()
        var steps = (0..<first).map { _ in typed() }
        steps.append(SessionStep(action: "move", keys: [KeyEvent(key: .left)]))
        steps += (0..<second).map { _ in typed() }
        steps += [SessionStep(action: "undo", keys: [Self.undoKey]), SessionStep(action: "undo", keys: [Self.undoKey])]
        steps += [SessionStep(action: "redo", keys: [Self.redoKey]), SessionStep(action: "redo", keys: [Self.redoKey])]
        return steps
    }

    /// A letter typed. Counted when it is played (``step(_:)``), not when
    /// the cycle is made.
    private func typed() -> SessionStep {
        let letter = Character(UnicodeScalar(UInt8(97 + random.below(26))))
        return SessionStep(action: "type", keys: [KeyEvent(key: .character(letter))])
    }

    /// The model's text and the status line say the length the keys left.
    func check(_ screen: [String], after index: Int) -> String? {
        let bytes = document.text.utf8.count
        guard bytes == expectedBytes else { return "the text is \(bytes) bytes, not the \(expectedBytes) the keys left" }
        guard screen.first?.hasPrefix("\(bytes) bytes") == true else {
            return "the status line does not say \(bytes) bytes"
        }
        return nil
    }

    static let descriptor = SessionDescriptor(
        id: "bigtext-undo",
        summary: "bigtext's typing undone and redone, two runs at a time, in 3.2 MB",
        exercises: "an undo and a redo: the step's edit put back through the binding, the layout and the "
            + "wrapped rows brought up to date, against the size of the document",
        make: { config, width, height, cold in
            DrivenSession(BigTextUndoSession(config: config), width: width, height: height, cold: cold)
        })
}
