//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassEffectIDTests.swift
//
//  `glassEffectID(_:in:)` in a container: glass with an id that moves to
//  another view does not arrive again, and glass without one does.
//
//  Here rather than beside the other glass transitions in
//  TUIkitFoundationTests: the glass moves by flipping a branch, and an
//  animated flip fades the branch's views by default, as SwiftUI's does
//  (lane TRANSITIONS2). `.transition(.identity)`, which TUIkitEffects
//  declares, holds the views still, so what changes is the glass alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
@Suite("Glass effect ids")
struct GlassEffectIDTests {

    /// One whole pass of `view` through `tui`, at `millis` on the frame clock,
    /// under `animation` (`nil`: no change animates), as the screen shows it,
    /// styling stripped.
    private func frame(
        _ view: some View, tui: TUIContext, atMillis millis: Int, animation: Animation? = nil, width: Int = 8
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

    @Test("Glass with an id that moves to another view does not arrive again; without one, it does")
    func identifiedGlassKeepsItsArrival() {
        let namespace = Namespace().wrappedValue
        func pair(glassOnFirst: Bool, id: String?) -> some View {
            GlassEffectContainer {
                HStack(spacing: 2) {
                    if glassOnFirst {
                        Text("A").padding().glassEffect().glassEffectID(id, in: namespace).transition(.identity)
                        Text("B").padding().transition(.identity)
                    } else {
                        Text("A").padding().transition(.identity)
                        Text("B").padding().glassEffect().glassEffectID(id, in: namespace).transition(.identity)
                    }
                }
            }
        }
        let rimmedB = ["   ", " A ", "   "].indices.map { row in
            ["   ", " A ", "   "][row] + "  " + ["╭─╮", "│B│", "╰─╯"][row]
        }
        let identified = TUIContext()
        _ = frame(pair(glassOnFirst: true, id: "x"), tui: identified, atMillis: 0)
        #expect(
            frame(pair(glassOnFirst: false, id: "x"), tui: identified, atMillis: 0, animation: .linear(duration: 1))
                == rimmedB)
        let anonymous = TUIContext()
        _ = frame(pair(glassOnFirst: true, id: nil), tui: anonymous, atMillis: 0)
        #expect(
            frame(pair(glassOnFirst: false, id: nil), tui: anonymous, atMillis: 0, animation: .linear(duration: 1))
                != rimmedB, "a new glass, arriving")
    }
}
