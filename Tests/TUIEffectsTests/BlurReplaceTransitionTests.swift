//  🖥️ TUI — A Terminal UI framework for Swift
//  BlurReplaceTransitionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIEffects
@testable import TUIFoundation
@testable import TUITestSupport

/// Twenty cells that come and go above a rule, so a removal has a slot.
private struct Host: View {
    let showing: Bool
    let transition: BlurReplaceTransition

    var body: some View {
        VStack(spacing: 0) {
            if showing {
                Text(String(repeating: "X", count: 20)).transition(transition)
            }
            Text(String(repeating: "-", count: 20))
        }
    }
}

@MainActor
@Suite("Blur replace transition")
struct BlurReplaceTransitionTests {

    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 20, height: 4)

        init() {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: .linear(duration: 1))
        }

        func draw(_ showing: Bool, _ transition: BlurReplaceTransition, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(
                Host(showing: showing, transition: transition), context: context
            ).withLayersDrawn().lines.map(\.stripped)
        }
    }

    @Test("The spellings are SwiftUI's, .downUp by default, and it has motion as SwiftUI's does")
    func spellings() {
        let plain: BlurReplaceTransition = .blurReplace
        #expect(plain.configuration == .downUp)
        let up: BlurReplaceTransition = .blurReplace(.upUp)
        #expect(up.configuration == .upUp)
        #expect(BlurReplaceTransition.Configuration.downUp != .upUp)
        // Measured: `Tools/SwiftUIProbes/Animation curves, springs and keyframes/p1.swift`.
        #expect(BlurReplaceTransition.properties.hasMotion)
    }

    @Test("Down-up arrives and leaves as a reveal from 0.9 at the centre, fading; up-up leaves by the fade alone")
    func erasesToScaleAndFade() {
        // SwiftUI: 0.9 of the view from its centre, and opacity 0 to 1
        // (`Tools/SwiftUIProbes/Transitions/tr4.out`); the blur is the fade.
        let scaleAndFade = AnyTransition.scale(scale: 0.9, anchor: .center).combined(with: .opacity)
        #expect(AnyTransition(BlurReplaceTransition(configuration: .downUp)) == scaleAndFade)
        #expect(
            AnyTransition(BlurReplaceTransition(configuration: .upUp))
                == .asymmetric(insertion: scaleAndFade, removal: .opacity))
    }

    @Test("Part-way in, the view shows from the centre, a cell short, and its letters are still there")
    func arrivalRevealsFromTheCentre() {
        let screen = Screen()
        _ = screen.draw(false, .blurReplace, atMillis: 0)
        _ = screen.draw(true, .blurReplace, atMillis: 0)
        // 0.96 of twenty cells is nineteen, centred on the half cell.
        #expect(screen.draw(true, .blurReplace, atMillis: 600)[0] == " " + String(repeating: "X", count: 19))
        #expect(screen.draw(true, .blurReplace, atMillis: 1000)[0] == String(repeating: "X", count: 20))
    }

    @Test("Up-up leaves whole, fading, where down-up shrinks toward the centre")
    func upUpRemovalIsTheFadeAlone() {
        let upUp = Screen()
        _ = upUp.draw(true, .blurReplace(.upUp), atMillis: 0)
        _ = upUp.draw(false, .blurReplace(.upUp), atMillis: 0)
        #expect(upUp.draw(false, .blurReplace(.upUp), atMillis: 400)[0] == String(repeating: "X", count: 20))

        let downUp = Screen()
        _ = downUp.draw(true, .blurReplace(.downUp), atMillis: 0)
        _ = downUp.draw(false, .blurReplace(.downUp), atMillis: 0)
        let row = downUp.draw(false, .blurReplace(.downUp), atMillis: 400)[0]
        let leading = row.prefix { $0 == " " }.count
        let trailing = row.reversed().prefix { $0 == " " }.count
        #expect(leading > 0 && trailing > 0, "shrunk from both sides: \(row)")
        #expect(abs(leading - trailing) <= 1, "toward the centre: \(row)")
    }
}
