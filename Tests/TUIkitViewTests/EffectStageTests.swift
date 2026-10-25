//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EffectStageTests.swift
//
//  The effect stage on its own: what an open drawing holds back, in what
//  order it runs, and what a discarded drawing puts back (decisions B-D5G-4,
//  B-D5G-11).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitView

/// What the stage's effects and undos did, in order.
private final class Log {
    var lines: [String] = []
}

@Suite("The effect stage")
struct EffectStageTests {
    @Test("With no drawing open, an effect runs at once and no undo is noted")
    func closedActsAtOnce() {
        let stage = EffectStage()
        let log = Log()
        #expect(!stage.isStaging)
        stage.perform { log.lines.append("closed") }
        stage.noteUndo { log.lines.append("undo") }
        #expect(log.lines == ["closed"])
        let mark = stage.open()
        stage.discard(since: mark)
        stage.close(mark)
        #expect(log.lines == ["closed"])
        #expect(stage.depth == 0)
    }

    @Test("An open drawing holds its effects until it is kept, then runs them in order")
    func openHoldsUntilKept() {
        let stage = EffectStage()
        let log = Log()
        let mark = stage.open()
        #expect(stage.isStaging)
        stage.perform { log.lines.append("a") }
        stage.perform { log.lines.append("b") }
        #expect(log.lines.isEmpty)
        stage.close(mark)
        #expect(log.lines == ["a", "b"])
        #expect(!stage.isStaging)
    }

    @Test("A discarded drawing drops its effects and runs its undos, last first; the next drawing's run")
    func discardDropsAndUndoes() {
        let stage = EffectStage()
        let log = Log()
        let mark = stage.open()
        stage.noteUndo { log.lines.append("undo 1") }
        stage.perform { log.lines.append("first") }
        stage.noteUndo { log.lines.append("undo 2") }
        stage.discard(since: mark)
        #expect(log.lines == ["undo 2", "undo 1"])
        // Still open: the drawing made in its place holds back too.
        #expect(stage.isStaging)
        stage.perform { log.lines.append("second") }
        stage.close(mark)
        #expect(log.lines == ["undo 2", "undo 1", "second"])
    }

    @Test("A kept drawing inside another waits for it; discarded with it, its effects go too")
    func nestedWaitsForTheOuterOne() {
        let stage = EffectStage()
        let log = Log()
        let outer = stage.open()
        let inner = stage.open()
        stage.perform { log.lines.append("inner") }
        stage.noteUndo { log.lines.append("inner undo") }
        stage.close(inner)
        #expect(log.lines.isEmpty)
        stage.discard(since: outer)
        #expect(log.lines == ["inner undo"])
        let again = stage.open()
        stage.perform { log.lines.append("inner again") }
        stage.close(again)
        stage.perform { log.lines.append("outer") }
        stage.close(outer)
        #expect(log.lines == ["inner undo", "inner again", "outer"])
    }

    @Test("A kept drawing runs its effects kind by kind, in SwiftUI's order, and in the order handed over within a kind")
    func keptRunsByKind() {
        let stage = EffectStage()
        let log = Log()
        let mark = stage.open()
        stage.perform(as: .change) { log.lines.append("change") }
        stage.perform(as: .appearance) { log.lines.append("appear 1") }
        stage.perform(as: .geometry) { log.lines.append("geometry") }
        stage.perform(as: .appearance) { log.lines.append("appear 2") }
        stage.perform(as: .preference) { log.lines.append("preference") }
        stage.close(mark)
        #expect(log.lines == ["geometry", "preference", "appear 1", "appear 2", "change"])
    }

    @Test("A discarded drawing takes back the presence it noted; a kept one keeps it")
    func presenceTakenBackOnDiscard() {
        let stage = EffectStage()
        let log = Log()
        stage.presenceUndo = { log.lines.append("gone \($0)") }
        let mark = stage.open()
        stage.notePresence("a")
        stage.discard(since: mark)
        stage.notePresence("b")
        stage.close(mark)
        #expect(log.lines == ["gone a"])
    }
}
