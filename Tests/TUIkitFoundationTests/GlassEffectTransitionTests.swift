//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassEffectTransitionTests.swift
//
//  `glassEffectTransition(_:)` and `glassEffectID(_:in:)` in a container:
//  glass arriving under an animation fades in, unless its transition is the
//  identity, and glass with an id that moves to another view does not arrive
//  again.
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

    @Test("Glass with an id that moves to another view does not arrive again; without one, it does")
    func identifiedGlassKeepsItsArrival() {
        let namespace = Namespace().wrappedValue
        func pair(glassOnFirst: Bool, id: String?) -> some View {
            GlassEffectContainer {
                HStack(spacing: 2) {
                    if glassOnFirst {
                        Text("A").padding().glassEffect().glassEffectID(id, in: namespace)
                        Text("B").padding()
                    } else {
                        Text("A").padding()
                        Text("B").padding().glassEffect().glassEffectID(id, in: namespace)
                    }
                }
            }
        }
        let rimmedB = ["   ", " A ", "   "].indices.map { row in
            ["   ", " A ", "   "][row] + "  " + ["╭─╮", "│B│", "╰─╯"][row]
        }
        let identified = TUIContext()
        _ = frame(pair(glassOnFirst: true, id: "x"), tui: identified, atMillis: 0, width: 8)
        #expect(
            frame(pair(glassOnFirst: false, id: "x"), tui: identified, atMillis: 0, animation: .linear(duration: 1), width: 8)
                == rimmedB)
        let anonymous = TUIContext()
        _ = frame(pair(glassOnFirst: true, id: nil), tui: anonymous, atMillis: 0, width: 8)
        #expect(
            frame(pair(glassOnFirst: false, id: nil), tui: anonymous, atMillis: 0, animation: .linear(duration: 1), width: 8)
                != rimmedB, "a new glass, arriving")
    }
}
