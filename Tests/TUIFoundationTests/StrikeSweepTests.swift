//  🖥️ TUI — A Terminal UI framework for Swift
//  StrikeSweepTests.swift
//
//  A strikethrough that changes under an animation is drawn along the text,
//  left to right, and taken back right to left (the owner, 2026-10-27);
//  under no animation it changes at once.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
private final class Frames {
    var context = makeRenderContext(width: 20, height: 2)

    init(_ animation: Animation?) {
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: animation)
    }

    /// Which cells of the first line are struck through at `millis`.
    func struck<V: View>(_ view: V, atMillis millis: Int) -> String {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        let line = renderToBuffer(view, context: context).lines.first ?? ""
        return String((0..<line.strippedLength).map { line.ansiSGRStateAt(visibleColumn: $0).isStruckThrough ? "-" : " " })
    }
}

@MainActor
@Suite("A strikethrough is drawn along its text under an animation")
struct StrikeSweepTests {
    @Test("Text's own strikethrough strikes left to right, and comes off right to left")
    func textStrikes() {
        let frames = Frames(.linear(duration: 1))
        _ = frames.struck(Text("abcdefgh").strikethrough(false), atMillis: 0)
        #expect(frames.struck(Text("abcdefgh").strikethrough(true), atMillis: 0) == "        ")
        #expect(frames.struck(Text("abcdefgh").strikethrough(true), atMillis: 500) == "----    ")
        #expect(frames.struck(Text("abcdefgh").strikethrough(true), atMillis: 1100) == "--------")
        _ = frames.struck(Text("abcdefgh").strikethrough(false), atMillis: 1100)
        #expect(frames.struck(Text("abcdefgh").strikethrough(false), atMillis: 1350) == "------  ")
        #expect(frames.struck(Text("abcdefgh").strikethrough(false), atMillis: 2200) == "        ")
    }

    @Test("A subtree's strikethrough strikes its text the same way")
    func subtreeStrikes() {
        let frames = Frames(.linear(duration: 1))
        _ = frames.struck(HStack { Text("abcdefgh") }.strikethrough(false), atMillis: 0)
        #expect(frames.struck(HStack { Text("abcdefgh") }.strikethrough(true), atMillis: 0) == "        ")
        #expect(frames.struck(HStack { Text("abcdefgh") }.strikethrough(true), atMillis: 500) == "----    ")
        #expect(frames.struck(HStack { Text("abcdefgh") }.strikethrough(true), atMillis: 1100) == "--------")
    }

    @Test("Under no animation it changes at once")
    func unanimated() {
        let frames = Frames(nil)
        _ = frames.struck(Text("abcd").strikethrough(false), atMillis: 0)
        #expect(frames.struck(Text("abcd").strikethrough(true), atMillis: 10) == "----")
        #expect(frames.struck(HStack { Text("abcd") }.strikethrough(true), atMillis: 20) == "----")
    }

    @Test("Clearing the strike past a cell restates the clearing after every sequence there")
    func clearingRestates() {
        let line = "\u{1B}[9mab\u{1B}[0m\u{1B}[9;31mcd\u{1B}[0m"
        let cleared = line.clearingStrikethrough(fromCell: 1)
        let struck = (0..<4).map { cleared.ansiSGRStateAt(visibleColumn: $0).isStruckThrough }
        #expect(struck == [true, false, false, false], "\(cleared.debugDescription)")
    }
}
