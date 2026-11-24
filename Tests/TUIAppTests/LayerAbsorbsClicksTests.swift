//  🖥️ TUI — A Terminal UI framework for Swift
//  LayerAbsorbsClicksTests.swift
//
//  A later layer of a `ZStack` takes the clicks of a control under it where it
//  draws, as SwiftUI's does (bug hunt H-68, BLEND-9; owner ruling O-10 (a),
//  2026-11-21). One test per case of the SwiftUI probe
//  (`Tools/SwiftUIProbes/Layers over a control (H-68)/covered.out`), each
//  expecting what SwiftUI did: a `Button` under the layer, clicked at its
//  centre.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// What the button under the layer heard.
@MainActor
private final class ClickLog {
    var saves = 0
    var stops = 0
    var hovers: [Bool] = []
}

@MainActor
@Suite("A layer over a control takes its clicks", .serialized)
struct LayerAbsorbsClicksTests {
    /// `layer` over a button in a 20 × 3 `ZStack`, the button centred.
    private func covered(_ log: ClickLog, _ layer: some View) -> some View {
        ZStack {
            Button("Save") { log.saves += 1 }
                .onHover { log.hovers.append($0) }
            layer
        }
        .frame(width: 20, height: 3)
    }

    /// Whether a click at the centre of the button `layer` lies over reaches it.
    private func clickReaches(_ layer: some View) -> Bool {
        let log = ClickLog()
        let harness = InputChainHarness()
        let drawn = harness.frame(covered(log, layer))
        guard let button = drawn.hitTargets.last(where: \.takesClicks) else {
            Issue.record("the button filed no region")
            return false
        }
        let (x, y) = (button.offsetX + button.width / 2, button.offsetY + button.height / 2)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: x, y: y))
        harness.frame(covered(log, layer))
        return log.saves == 1
    }

    @Test("With no layer the click reaches the button (the probe's control)")
    func noLayer() {
        #expect(clickReaches(EmptyView()))
    }

    @Test("Color.black.opacity(0.4) over the button takes the click")
    func scrim() {
        #expect(!clickReaches(Color.black.opacity(0.4)))
    }

    @Test("Color.black.opacity(0.4).allowsHitTesting(false) lets the click through")
    func scrimNotHitTestable() {
        #expect(clickReaches(Color.black.opacity(0.4).allowsHitTesting(false)))
    }

    @Test("A disabled scrim still takes the click")
    func disabledScrim() {
        #expect(!clickReaches(Color.black.opacity(0.4).disabled(true)))
    }

    @Test("Color.clear lets the click through")
    func clear() {
        #expect(clickReaches(Color.clear))
    }

    @Test("Color.black.opacity(0) lets the click through")
    func transparentColour() {
        #expect(clickReaches(Color.black.opacity(0)))
    }

    /// The probe's `0.001`, at the faintest alpha TUI's colour holds: a `Color`
    /// keeps its alpha in a byte, so `0.001` is stored as zero and is
    /// `Color.clear`, and `0.01` is the nearest that is not (3 of 255).
    @Test("A nearly transparent colour still takes the click")
    func nearlyTransparentColour() {
        #expect(!clickReaches(Color.black.opacity(0.01)))
    }

    @Test("A filled rectangle at .opacity(0) lets the click through")
    func rectangleAtOpacityZero() {
        #expect(clickReaches(Rectangle().fill(Color.black).opacity(0)))
    }

    @Test("A Text with a glyph over the button's centre takes the click")
    func textGlyph() {
        #expect(!clickReaches(Text(verbatim: "████████████")))
    }

    @Test("A Text at .opacity(0) lets the click through")
    func textAtOpacityZero() {
        #expect(clickReaches(Text(verbatim: "████████████").opacity(0)))
    }

    @Test("A Text with a space over the button's centre takes the click: it is inside the text")
    func textSpace() {
        #expect(!clickReaches(Text(verbatim: "█" + String(repeating: " ", count: 16) + "█")))
    }

    @Test("A frame's empty padding over the button lets the click through")
    func framePadding() {
        #expect(
            clickReaches(Text(verbatim: "x").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)))
    }

    @Test("A scrim over the half without the button's centre lets the click through")
    func scrimBeside() {
        #expect(
            clickReaches(
                Color.black.opacity(0.4).frame(width: 9).frame(maxWidth: .infinity, alignment: .leading)))
    }

    @Test("A scrim over the half with the button's centre takes the click")
    func scrimOverTheCentre() {
        #expect(
            !clickReaches(
                Color.black.opacity(0.4).frame(width: 11).frame(maxWidth: .infinity, alignment: .trailing)))
    }

    @Test("An .overlay drawn over a button takes its click, as a ZStack's layer does")
    func overlayModifier() {
        let log = ClickLog()
        let harness = InputChainHarness()
        let view = { Button("Save") { log.saves += 1 }.overlay { Color.black.opacity(0.4) } }
        let drawn = harness.frame(view())
        guard let button = drawn.hitTargets.last(where: \.takesClicks) else {
            Issue.record("the button filed no region")
            return
        }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: button.offsetX + 1, y: button.offsetY))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: button.offsetX + 1, y: button.offsetY))
        #expect(log.saves == 0)
    }

    @Test("A control in the layer itself still takes its click")
    func controlInTheLayer() {
        let log = ClickLog()
        let harness = InputChainHarness()
        let view = {
            ZStack {
                Button("Save") { log.saves += 1 }
                ZStack {
                    Color.black.opacity(0.4)
                    Button("Stop") { log.stops += 1 }
                }
            }
            .frame(width: 20, height: 3)
        }
        let drawn = harness.frame(view())
        guard let stop = drawn.hitTargets.last(where: \.takesClicks) else {
            Issue.record("the layer's button filed no region")
            return
        }
        let (x, y) = (stop.offsetX + stop.width / 2, stop.offsetY)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: x, y: y))
        #expect(log.stops == 1)
        #expect(log.saves == 0)
    }

    @Test("The pointer still hovers the button under a scrim: only clicks are taken")
    func hoverStillReaches() {
        let log = ClickLog()
        let harness = InputChainHarness()
        let view = { covered(log, Color.black.opacity(0.4)) }
        let drawn = harness.frame(view())
        guard let button = drawn.hitTargets.last(where: \.takesClicks) else {
            Issue.record("the button filed no region")
            return
        }
        harness.hover([(button.offsetX + 1, button.offsetY)], view)
        #expect(log.hovers == [true])
    }
}
