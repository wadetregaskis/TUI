//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EffectStageTests.swift
//
//  The effect stage on its own: what a drawing that may be drawn again holds
//  back once it is armed, in what order it runs, and what a discarded drawing
//  puts back (decisions B-D5G-4).
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
    @Test("With no drawing open, or none armed, an effect runs at once and no undo is noted")
    func unarmedActsAtOnce() {
        let stage = EffectStage()
        let log = Log()
        stage.perform { log.lines.append("closed") }
        let mark = stage.open()
        #expect(!stage.isStaging)
        stage.perform { log.lines.append("open") }
        stage.noteUndo { log.lines.append("undo") }
        stage.discard(since: mark)
        #expect(log.lines == ["closed", "open"])
        stage.close(mark)
        #expect(log.lines == ["closed", "open"])
        #expect(stage.depth == 0)
    }

    @Test("An armed drawing holds its effects until it is kept, then runs them in order")
    func armedHoldsUntilKept() {
        let stage = EffectStage()
        let log = Log()
        let mark = stage.open()
        stage.perform { log.lines.append("before") }
        stage.arm(atDepth: stage.depth)
        #expect(stage.isStaging)
        stage.perform { log.lines.append("a") }
        stage.perform { log.lines.append("b") }
        #expect(log.lines == ["before"])
        stage.close(mark)
        #expect(log.lines == ["before", "a", "b"])
        #expect(!stage.isStaging)
    }

    @Test("A discarded armed drawing drops its effects and runs its undos, last first; the next drawing's run")
    func discardDropsAndUndoes() {
        let stage = EffectStage()
        let log = Log()
        let mark = stage.open()
        stage.arm(atDepth: 1)
        stage.noteUndo { log.lines.append("undo 1") }
        stage.perform { log.lines.append("first") }
        stage.noteUndo { log.lines.append("undo 2") }
        stage.discard(since: mark)
        #expect(log.lines == ["undo 2", "undo 1"])
        // Still open and armed: the drawing made in its place holds back too.
        #expect(stage.isStaging)
        stage.perform { log.lines.append("second") }
        stage.close(mark)
        #expect(log.lines == ["undo 2", "undo 1", "second"])
    }

    @Test("A kept drawing inside an armed one waits for it; discarded with it, its effects go too")
    func nestedWaitsForTheArmedOne() {
        let stage = EffectStage()
        let log = Log()
        let outer = stage.open()
        stage.arm(atDepth: 1)
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
        stage.close(outer)
        #expect(log.lines == ["inner undo", "inner again"])
    }

    @Test("An inner drawing armed alone runs its effects when it is kept, inside the unarmed outer one")
    func innerArmedAlone() {
        let stage = EffectStage()
        let log = Log()
        let outer = stage.open()
        let inner = stage.open()
        stage.arm(atDepth: 2)
        stage.perform { log.lines.append("inner") }
        stage.close(inner)
        #expect(log.lines == ["inner"])
        #expect(!stage.isStaging)
        stage.perform { log.lines.append("outer") }
        stage.close(outer)
        #expect(log.lines == ["inner", "outer"])
    }

    @Test("Arming further out keeps what the inner drawing held, for the outer one to run")
    func armingFurtherOut() {
        let stage = EffectStage()
        let log = Log()
        let outer = stage.open()
        let inner = stage.open()
        stage.arm(atDepth: 2)
        stage.perform { log.lines.append("a") }
        stage.arm(atDepth: 1)
        stage.perform { log.lines.append("b") }
        stage.close(inner)
        #expect(log.lines.isEmpty)
        stage.perform { log.lines.append("c") }
        stage.close(outer)
        #expect(log.lines == ["a", "b", "c"])
    }

    @Test("A depth past the innermost drawing arms the innermost, and nothing is armed with none open")
    func armingOutOfRange() {
        let stage = EffectStage()
        stage.arm(atDepth: 1)
        #expect(!stage.isStaging)
        let outer = stage.open()
        let inner = stage.open()
        stage.arm(atDepth: 9)
        #expect(stage.isStaging)
        stage.close(inner)
        #expect(!stage.isStaging)
        stage.close(outer)
    }
}
