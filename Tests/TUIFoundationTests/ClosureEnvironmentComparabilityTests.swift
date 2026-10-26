//  🖥️ TUI — A Terminal UI framework for Swift
//  ClosureEnvironmentComparabilityTests.swift
//
//  Two of TUI's own modifiers wrote a closure into the environment —
//  `.onMenuOpen`'s action, and the extra keys a disclosure header's button
//  answers — and an environment value that cannot be compared turns every memo
//  off beneath it. Each now writes one object for the modifier's life,
//  refreshed with the closure each body and compared by identity (the shape
//  `DismissAction`'s box and the searchable's dismissal take). These pin that
//  the subtree's environment stays comparable, and that the object answers as
//  the most recent body said, so a served memo replaying a handler gets the
//  current closure.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// What a render reached a leaf with.
@MainActor
private final class EnvironmentLog {
    var sawUncomparable: Bool?
    var menuOpen: MenuOpenAction?
    var keyExtras: ButtonKeyExtras?
}

/// A leaf that records the environment where it is drawn.
private struct EnvironmentSpy: View, Renderable {
    let log: EnvironmentLog

    var body: Never { fatalError("EnvironmentSpy renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        log.sawUncomparable = context.environment.hasUncomparableEnvironmentValue
        log.menuOpen = context.environment.menuOpenAction
        log.keyExtras = context.environment.buttonKeyExtras
        return FrameBuffer(text: "spy")
    }
}

@MainActor
@Suite("The environment under .onMenuOpen and a disclosure header can be compared")
struct ClosureEnvironmentComparabilityTests {
    /// Renders `view` as frames of a running app: state kept between them.
    @MainActor
    private final class Frames {
        let tui = TUIContext()

        func render(_ view: some View) {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            _ = renderToBuffer(
                view, context: RenderContext(availableWidth: 40, availableHeight: 10, tuiContext: tui))
            tui.stateStorage.endRenderPass()
        }
    }

    @Test("Under .onMenuOpen the environment is comparable, and one object runs the latest closure")
    func onMenuOpen() {
        let log = EnvironmentLog()
        let frames = Frames()
        var ran: [String] = []
        frames.render(EnvironmentSpy(log: log).onMenuOpen { ran.append("first") })
        #expect(log.sawUncomparable == false, ".onMenuOpen made the environment uncomparable")
        let first = log.menuOpen
        frames.render(EnvironmentSpy(log: log).onMenuOpen { ran.append("second") })
        let second = log.menuOpen
        #expect(first != nil && first == second, "the action is one object across frames")
        // Called through the object a frame ago handed out — as a handler a
        // memo stored then would call it.
        first?()
        #expect(ran == ["second"], "an action read last frame ran \(ran), not this frame's closure")
    }

    @Test("Under a disclosure header's key extras the environment is comparable, and current")
    func buttonKeyExtras() {
        let log = EnvironmentLog()
        let frames = Frames()
        var answered: [String] = []
        frames.render(
            EnvironmentSpy(log: log).buttonKeyExtras(keys: [.left]) { _ in answered.append("first"); return true })
        #expect(log.sawUncomparable == false, "the key extras made the environment uncomparable")
        let first = log.keyExtras
        frames.render(
            EnvironmentSpy(log: log).buttonKeyExtras(keys: [.right]) { _ in answered.append("second"); return true })
        #expect(first != nil && first == log.keyExtras, "the extras are one object across frames")
        #expect(first?.keys == [.right], "the keys are this frame's")
        _ = first?.handle(KeyEvent(key: .right))
        #expect(answered == ["second"], "extras read last frame answered \(answered), not this frame's handler")
    }
}
