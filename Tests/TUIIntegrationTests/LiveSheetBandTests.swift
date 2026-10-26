//  🖥️ TUI — A Terminal UI framework for Swift
//  LiveSheetBandTests.swift
//
//  A sheet beside a live page is a band across the whole content area, as a
//  `VSplitView`'s pane is (A19, owner Q3): its box takes the width, as it
//  takes a detent's height. A sizing the content names still sizes it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A live sheet's band", .rendersEnglishUI)
struct LiveSheetBandTests {
    private static let width = 50
    private static let height = 20

    /// The sheet's width — the presented layer's — with `content` presented
    /// over a page.
    private func sheetWidth(_ content: some View) -> Int? {
        let harness = InputChainHarness(width: Self.width, height: Self.height) { environment in
            environment.terminalWidth = Self.width
            environment.overlayContentHeight = Self.height
        }
        let view = Text("page").sheet(isPresented: .constant(true)) { content }
        harness.frame(view)
        return harness.frame(view).overlays.first?.content.width
    }

    private func live(_ content: some View) -> some View {
        content
            .presentationDetents([.height(6), .large])
            .presentationBackgroundInteraction(.enabled)
    }

    @Test("A Dialog, a Panel, a Card and a bordered box each span the content area")
    func boxesSpanTheBand() {
        #expect(sheetWidth(live(Dialog(title: "D") { Text("x") })) == Self.width)
        #expect(sheetWidth(live(Panel("P") { Text("x") })) == Self.width)
        #expect(sheetWidth(live(Card { Text("x") })) == Self.width)
        #expect(sheetWidth(live(Text("x").border())) == Self.width)
    }

    @Test("Past its upThrough detent the band keeps its width")
    func modalBandKeepsItsWidth() {
        let content = Panel("P") { Text("x") }
            .presentationDetents([.height(6), .large], selection: .constant(.large))
            .presentationBackgroundInteraction(.enabled(upThrough: .height(6)))
        #expect(sheetWidth(content) == Self.width)
    }

    @Test("Content with no box keeps its own width, and a fitted sizing is a card")
    func ownWidths() {
        let bare = sheetWidth(live(Text("bare text")))
        #expect(bare.map { $0 < Self.width } == true, "a bare Text was stretched: \(String(describing: bare))")
        let fitted = sheetWidth(live(Panel("P") { Text("x") }.presentationSizing(.fitted)))
        #expect(fitted.map { $0 < Self.width } == true, "a fitted sheet spans the band")
        let automatic = sheetWidth(live(Panel("P") { Text("x") }.presentationSizing(.automatic)))
        #expect(automatic == Self.width, "an automatic sizing is not a band")
    }

    @Test("A detented sheet that does not let the page through is its content's width, as before")
    func modalSheetIsItsContentsWidth() {
        let width = sheetWidth(Panel("P") { Text("x") }.presentationDetents([.height(6), .large]))
        #expect(width.map { $0 < Self.width } == true)
    }
}
