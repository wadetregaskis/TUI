//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassEffectTransitionTests.swift
//
//  `glassEffectTransition(_:)` in a container: glass arriving under an
//  animation fades in, unless its transition is the identity. Glass with an id
//  that moves to another view is in TUIkitIntegrationTests'
//  GlassEffectIDTests: it moves by flipping a branch, whose views fade by
//  default, and only `.transition(.identity)` (TUIkitEffects) holds them still.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
@Suite("Glass effect transitions")
struct GlassEffectTransitionTests {

    /// One whole pass of `view` through `tui`, at `millis` on the frame clock,
    /// under `animation` (`nil`: no change animates), as the screen shows it,
    /// styling stripped.
    private func frame(
        _ view: some View, tui: TUIContext, atMillis millis: Int, animation: Animation? = nil, width: Int = 6
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = SystemPalette.green
        environment.canAnimate = true
        environment.transaction = Transaction(animation: animation)
        environment.frameNowNanos = Int64(millis) * 1_000_000
        let context = RenderContext(availableWidth: width, availableHeight: 3, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToScreen(view, context: context)
        tui.renderCache.removeInactive()
        tui.stateStorage.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    private func flag(_ glass: Glass, transition: GlassEffectTransition = .matchedGeometry) -> some View {
        GlassEffectContainer {
            Text("Flag").padding().glassEffect(glass).glassEffectTransition(transition)
        }
    }

    private let rimmed = ["╭────╮", "│Flag│", "╰────╯"]
    private let bare = ["      ", " Flag ", "      "]

    @Test("In a container, glass arriving under an animation fades in")
    func materializes() {
        for transition in [GlassEffectTransition.matchedGeometry, .materialize] {
            let tui = TUIContext()
            #expect(frame(flag(.identity, transition: transition), tui: tui, atMillis: 0) == bare)
            let arriving = flag(.regular, transition: transition)
            #expect(frame(arriving, tui: tui, atMillis: 0, animation: .linear(duration: 1)) == bare, "not there yet")
            #expect(frame(arriving, tui: tui, atMillis: 750) == rimmed, "most of the way: the rim is drawn")
            #expect(frame(arriving, tui: tui, atMillis: 1_100) == rimmed)
        }
    }

    @Test("Glass arriving beside glass in a container fades in by itself, and joins it once it has arrived")
    func arrivingBesideGlass() {
        func row(_ withB: Bool) -> some View {
            GlassEffectContainer {
                HStack(spacing: 0) {
                    Text("A").padding(.horizontal).glassEffect()
                    if withB { Text("B").padding(.horizontal).glassEffect() }
                }
            }
        }
        // B's view fades in too (an inserted view's default transition): its
        // label is not there at first, then faint.
        let tui = TUIContext()
        #expect(frame(row(false), tui: tui, atMillis: 0) == ["(A)"])
        #expect(frame(row(true), tui: tui, atMillis: 0, animation: .linear(duration: 1)) == ["(A)   "], "not there yet")
        #expect(frame(row(true), tui: tui, atMillis: 250) == ["(A) B "], "a quarter of the way: A keeps its own shape")
        #expect(frame(row(true), tui: tui, atMillis: 750) == ["(A)(B)"], "by itself until it has arrived")
        #expect(frame(row(true), tui: tui, atMillis: 1_100) == ["(A  B)"])
    }

    @Test("Glass leaving a joined shape under an animation takes its part with it; the glass that stays closes at once")
    func leavingAJoinedShape() {
        let screen = RemovalScreen(animation: .linear(duration: 1), width: 8) { withB in
            GlassEffectContainer {
                HStack(spacing: 0) {
                    Text("A").padding(.horizontal).glassEffect()
                    if withB { Text("B").padding(.horizontal).glassEffect() }
                }
            }
        }
        // Every frame is under the animation, so the pair arrives first.
        _ = screen.draw(true, atMillis: 0)
        #expect(screen.draw(true, atMillis: 1_100) == ["(A  B)"])
        #expect(screen.draw(false, atMillis: 1_200) == ["(A) B)"], "B's part leaves with B, as it was drawn")
        #expect(screen.draw(false, atMillis: 1_700) == ["(A) B)"])
        #expect(screen.draw(false, atMillis: 2_300) == ["(A)"])
    }

    @Test("Glass whose transition is the identity appears at once; so does glass with no animation")
    func identityAndUnanimated() {
        let tui = TUIContext()
        _ = frame(flag(.identity, transition: .identity), tui: tui, atMillis: 0)
        #expect(frame(flag(.regular, transition: .identity), tui: tui, atMillis: 0, animation: .linear(duration: 1)) == rimmed)
        let other = TUIContext()
        _ = frame(flag(.identity), tui: other, atMillis: 0)
        #expect(frame(flag(.regular), tui: other, atMillis: 0) == rimmed)
    }

    @Test("Outside a container, glass comes with its view")
    func outsideAContainer() {
        let tui = TUIContext()
        _ = frame(Text("Flag").padding().glassEffect(.identity), tui: tui, atMillis: 0)
        let arriving = Text("Flag").padding().glassEffect()
        #expect(frame(arriving, tui: tui, atMillis: 0, animation: .linear(duration: 1)) == rimmed)
    }
}
