//  🖥️ TUI — A Terminal UI framework for Swift
//  LegibilityWeightTests.swift
//
//  `\.legibilityWeight` is settable, and under `.bold` text is drawn a tier
//  heavier — faint draws plain, plain draws bold, bold stays bold — as SwiftUI
//  draws all of its text a weight heavier (decisions B2, owner 2026-10-12:
//  "make it writable"). What faint means other than a weight stays faint.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Legibility weight: text a tier heavier under .bold")
struct LegibilityWeightTests {
    /// The SGR state at `word` when `view` is drawn, under `weight`.
    private func state(of word: String, in view: some View, under weight: LegibilityWeight?) -> SGRState? {
        let lines = renderToBuffer(
            view.environment(\.legibilityWeight, weight), context: makeRenderContext(width: 40, height: 4)
        ).lines
        return sgrState(of: word, in: lines)
    }

    @Test("It is nil unless something sets it, and a write is read back")
    func settable() {
        var environment = EnvironmentValues()
        #expect(environment.legibilityWeight == nil)
        environment.legibilityWeight = .bold
        #expect(environment.legibilityWeight == .bold)
    }

    @Test("The rule: faint draws plain, plain draws bold, bold stays bold; nil and .regular change nothing")
    func rule() {
        let bold: LegibilityWeight? = .bold
        #expect(bold.applied(bold: false, faint: true) == (false, false))
        #expect(bold.applied(bold: false, faint: false) == (true, false))
        #expect(bold.applied(bold: true, faint: false) == (true, false))
        for weight: LegibilityWeight? in [nil, .regular] {
            #expect(weight.applied(bold: false, faint: true) == (false, true))
            #expect(weight.applied(bold: false, faint: false) == (false, false))
        }
    }

    @Test("Plain text draws bold under .bold, and plain without it")
    func plainText() {
        #expect(state(of: "plain", in: Text("plain"), under: .bold)?.isBold == true)
        #expect(state(of: "plain", in: Text("plain"), under: nil)?.isBold == false)
        #expect(state(of: "plain", in: Text("plain"), under: .regular)?.isBold == false)
    }

    @Test("Light text draws plain under .bold")
    func lightText() {
        let light = Text("light").fontWeight(.light)
        #expect(state(of: "light", in: light, under: nil)?.isFaint == true)
        let heavier = state(of: "light", in: light, under: .bold)
        #expect(heavier?.isFaint == false && heavier?.isBold == false)
    }

    @Test("Bold text stays bold under .bold")
    func boldText() {
        let heavier = state(of: "bold", in: Text("bold").bold(), under: .bold)
        #expect(heavier?.isBold == true && heavier?.isFaint == false)
    }

    @Test("Text a secondary scale draws a tier lighter is a tier heavier than that under .bold")
    func secondaryScale() {
        let small = Text("small").textScale(.secondary)
        #expect(state(of: "small", in: small, under: nil)?.isFaint == true)
        let heavier = state(of: "small", in: small, under: .bold)
        #expect(heavier?.isFaint == false && heavier?.isBold == false)
    }

    @Test("A cascaded weight is stepped too: a container's .fontWeight(.light) draws plain under .bold")
    func cascaded() {
        let heavier = state(of: "inside", in: VStack { Text("inside") }.fontWeight(.light), under: .bold)
        #expect(heavier?.isFaint == false && heavier?.isBold == false)
    }

    @Test("A stale figure's faint is not a weight, and stays faint under .bold")
    func invalidatedStaysFaint() {
        let stale = state(of: "stale", in: Text("stale").redacted(reason: .invalidated), under: .bold)
        #expect(stale?.isFaint == true)
    }
}
