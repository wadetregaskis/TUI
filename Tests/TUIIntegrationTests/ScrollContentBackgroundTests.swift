//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollContentBackgroundTests.swift
//
//  `scrollContentBackground(_:)` (decisions A9): `.visible` paints the
//  palette's background behind ScrollView, List, Table, Form and TextEditor;
//  `.hidden` and `.automatic` leave them as they were, since none of them draws
//  a background of its own here.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("scrollContentBackground")
struct ScrollContentBackgroundTests {

    /// The five scrollables the modifier reaches.
    enum Scrollable: String, CaseIterable, Sendable {
        case scrollView, list, table, form, textEditor
    }

    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
    }

    private func view(_ kind: Scrollable) -> AnyView {
        switch kind {
        case .scrollView:
            AnyView(ScrollView { Text("short") }.frame(height: 4))
        case .list:
            AnyView(List { Text("one"); Text("two") }.frame(height: 6))
        case .table:
            AnyView(
                Table([Row(id: 1), Row(id: 2)]) { TableColumn("Name", value: \.name) }
                    .frame(height: 6))
        case .form:
            AnyView(Form { Text("field") })
        case .textEditor:
            AnyView(TextEditor(text: .constant("text")).frame(height: 4))
        }
    }

    /// The frame's lines, escapes and all.
    private func render(_ view: some View) -> [String] {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        // A palette whose background is a colour, so painting it shows.
        environment.palette = SystemPalette.green
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 24, availableHeight: 8, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.lines
    }

    @Test("`.visible` paints the palette's background behind the scrollable", arguments: Scrollable.allCases)
    func visiblePaints(_ kind: Scrollable) {
        let plain = render(view(kind))
        let visible = render(view(kind).scrollContentBackground(.visible))
        let painted = render(view(kind).background(.windowBackground))
        #expect(visible == painted, "the palette's background, as `.background(.windowBackground)` paints it")
        #expect(visible != plain, "and something was painted")
    }

    @Test("`.hidden` and `.automatic` draw as before", arguments: Scrollable.allCases)
    func hiddenAndAutomaticDrawAsBefore(_ kind: Scrollable) {
        let plain = render(view(kind))
        #expect(render(view(kind).scrollContentBackground(.hidden)) == plain)
        #expect(render(view(kind).scrollContentBackground(.automatic)) == plain)
    }

    /// SwiftUI's commonest use: hide the scrollable's own background and draw
    /// the app's behind it.
    @Test("`.hidden` under an app background draws the app's background")
    func hiddenUnderAnAppBackground() {
        let idiom = render(view(.list).scrollContentBackground(.hidden).background(Color.blue))
        let direct = render(view(.list).background(Color.blue))
        #expect(idiom == direct)
    }

    /// The nearer statement wins, as the environment always resolves.
    @Test("A nearer `.hidden` overrides an outer `.visible`")
    func nearerWins() {
        let plain = render(view(.scrollView))
        let overridden = render(
            view(.scrollView).scrollContentBackground(.hidden).scrollContentBackground(.visible))
        #expect(overridden == plain)
    }

    /// The scroller a menu, a sheet or a framed container puts around content
    /// too tall for it is chrome: its surface paints its own background.
    @Test("A chrome scroller does not paint, while its content's scrollables still do")
    func chromeDoesNotPaint() {
        let chrome = ScrollView { Text("short") }.asChrome().frame(height: 4)
        #expect(
            render(chrome.scrollContentBackground(.visible))
                == render(ScrollView { Text("short") }.asChrome().frame(height: 4)))
        let nested = ScrollView { ScrollView { Text("inner") }.frame(height: 2) }.asChrome().frame(height: 4)
        let paintedInner = ScrollView {
            ScrollView { Text("inner") }.frame(height: 2).background(.windowBackground)
        }.asChrome().frame(height: 4)
        #expect(render(nested.scrollContentBackground(.visible)) == render(paintedInner))
    }
}
