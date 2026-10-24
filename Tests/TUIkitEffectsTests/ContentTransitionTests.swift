//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentTransitionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
private final class Frames {
    var context = makeRenderContext(width: 10, height: 2)

    init(_ animation: Animation?) {
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: animation)
    }

    func draw<V: View>(_ view: V, atMillis millis: Int) -> FrameBuffer {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context)
    }

    func text<V: View>(_ view: V, atMillis millis: Int) -> String {
        draw(view, atMillis: millis).lines.first?.stripped ?? ""
    }
}

private struct ReadsTransition: View {
    @Environment(\.contentTransition) var transition
    var body: some View { Text(transition == .opacity ? "opacity" : "other") }
}

@MainActor
@Suite("Content transitions")
struct ContentTransitionTests {

    private func label(_ text: String, _ color: Color = .red) -> some View {
        Text(text).foregroundStyle(color)
    }

    @Test("Under an animation, a change dissolves: the old glyphs until half way, then the new")
    func dissolves() {
        let frames = Frames(.linear(duration: 1))
        _ = frames.draw(label("AAAA").contentTransition(.opacity), atMillis: 0)
        #expect(frames.text(label("BBBB").contentTransition(.opacity), atMillis: 0) == "AAAA")
        #expect(frames.text(label("BBBB").contentTransition(.opacity), atMillis: 250) == "AAAA")
        #expect(frames.text(label("BBBB").contentTransition(.opacity), atMillis: 750) == "BBBB")
        let settled = frames.draw(label("BBBB").contentTransition(.opacity), atMillis: 1100)
        #expect(settled.lines == Frames(nil).draw(label("BBBB"), atMillis: 0).lines, "done, it is the new drawing")
    }

    @Test("A burst of changes faster than half the dissolve is followed, one change behind")
    func burstFollows() {
        // A held key's auto-repeat on a counter: a change every 100 ms under a
        // one-second dissolve. Each dissolve starts from the last value drawn,
        // so the glyphs move on with the burst instead of standing at the
        // first value until it ends.
        let frames = Frames(.linear(duration: 1))
        _ = frames.draw(label("1").contentTransition(.numericText()), atMillis: 0)
        var seen: [String] = []
        for (index, value) in ["2", "3", "4", "5"].enumerated() {
            seen.append(frames.text(label(value).contentTransition(.numericText()), atMillis: (index + 1) * 100))
        }
        #expect(seen == ["1", "2", "3", "4"], "\(seen)")
        #expect(frames.text(label("5").contentTransition(.numericText()), atMillis: 1500) == "5")
    }

    @Test("Interpolating keeps matching glyphs and moves their colours")
    func interpolatesColours() {
        let frames = Frames(.linear(duration: 1))
        _ = frames.draw(label("AB", .red).contentTransition(.interpolate), atMillis: 0)
        _ = frames.draw(label("AB", .blue).contentTransition(.interpolate), atMillis: 0)
        let halfway = frames.draw(label("AB", .blue).contentTransition(.interpolate), atMillis: 500)
        #expect(halfway.lines.first?.stripped.hasPrefix("AB") == true)
        let red = Frames(nil).draw(label("AB", .red), atMillis: 0).lines
        let blue = Frames(nil).draw(label("AB", .blue), atMillis: 0).lines
        #expect(halfway.lines != red && halfway.lines != blue, "a colour between the two")
    }

    @Test("Identity, the unset default and an unanimated change all draw the change at once")
    func noDissolve() {
        for transition in [ContentTransition.identity, EnvironmentValues().contentTransition] {
            let frames = Frames(.linear(duration: 1))
            _ = frames.draw(label("AAAA").contentTransition(transition), atMillis: 0)
            #expect(frames.text(label("BBBB").contentTransition(transition), atMillis: 0) == "BBBB")
        }
        let unanimated = Frames(nil)
        _ = unanimated.draw(label("AAAA").contentTransition(.opacity), atMillis: 0)
        #expect(unanimated.text(label("BBBB").contentTransition(.opacity), atMillis: 0) == "BBBB")
    }

    @Test("Each text dissolves its own change, so an inner .identity exempts its part")
    func innerIdentityIsExempt() {
        // SwiftUI's leaves read the transition each for itself (decisions B61).
        func pair(_ first: String, _ second: String) -> some View {
            HStack(spacing: 1) {
                label(first)
                label(second).contentTransition(.identity)
            }
            .contentTransition(.opacity)
        }
        let frames = Frames(.linear(duration: 1))
        _ = frames.draw(pair("AA", "CC"), atMillis: 0)
        #expect(frames.text(pair("BB", "DD"), atMillis: 0) == "AA DD")
        #expect(frames.text(pair("BB", "DD"), atMillis: 750) == "BB DD")
    }

    @Test("A transition set through .environment dissolves as the modifier's does")
    func environmentSpellingDissolves() {
        let frames = Frames(.linear(duration: 1))
        _ = frames.draw(label("AAAA").environment(\.contentTransition, .opacity), atMillis: 0)
        #expect(frames.text(label("BBBB").environment(\.contentTransition, .opacity), atMillis: 0) == "AAAA")
        var unset = EnvironmentValues()
        #expect(!unset.contentDissolves, "a text keeps nothing where no transition is written")
        unset.contentTransition = .interpolate
        #expect(unset.contentDissolves)
        unset.contentTransition = .identity
        #expect(!unset.contentDissolves)
    }

    @Test("What is not a text or an image changes as it would without the modifier")
    func nonLeafIsUntouched() {
        // A colour animates its own change; the modifier adds no dissolve.
        func swatch(_ color: Color) -> some View { color.frame(width: 2, height: 1) }
        let written = Frames(.linear(duration: 1))
        let bare = Frames(.linear(duration: 1))
        _ = written.draw(swatch(.red).contentTransition(.opacity), atMillis: 0)
        _ = bare.draw(swatch(.red), atMillis: 0)
        for millis in [0, 500, 1100] {
            #expect(
                written.draw(swatch(.blue).contentTransition(.opacity), atMillis: millis).lines
                    == bare.draw(swatch(.blue), atMillis: millis).lines)
        }
    }

    @Test("The modifier sets the environment value its content reads")
    func environment() {
        #expect(Frames(nil).text(ReadsTransition().contentTransition(.opacity), atMillis: 0) == "opacity")
        let unset = EnvironmentValues().contentTransition
        #expect(unset != .identity && unset != .opacity && unset != .interpolate, "SwiftUI's unnamed default, measured")
        #expect(EnvironmentValues().contentTransitionAddsDrawingGroup == false)
    }

    @Test("Numeric transitions compare by their direction or their value, as SwiftUI's do")
    func numericEquality() {
        #expect(ContentTransition.numericText(countsDown: true) == .numericText(countsDown: true))
        #expect(ContentTransition.numericText(countsDown: true) != .numericText(countsDown: false))
        #expect(ContentTransition.numericText(value: 3) != .numericText(value: 4))
        #expect(ContentTransition.numericText(value: 3) != .numericText(countsDown: false))
    }
}
