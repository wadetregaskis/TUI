//  🖥️ TUI — A Terminal UI framework for Swift
//  TabSearchActivationTests.swift
//
//  `tabViewSearchActivation(_:)`: selecting a tab view's search tab activates
//  the search around it, and the search ending selects the tab before again
//  (`.searchTabSelection`); by default neither happens.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUISearch
@testable import TUITabs
@testable import TUITestSupport

@MainActor
private final class TabSearchModel {
    var selection = 0
    var query = ""
}

/// Reads whether the search is active, in the search tab's content.
private struct SearchingProbe: View {
    @Environment(\.isSearching) private var isSearching
    var body: some View { Text(isSearching ? "SEARCHING" : "IDLE") }
}

@MainActor
@Suite("Tab view search activation", .rendersEnglishUI)
struct TabSearchActivationTests {
    private func page(_ model: TabSearchModel, activation: TabSearchActivation) -> some View {
        VStack {
            // Ahead of the field, so it takes the focus first and the search
            // starts inactive.
            Button("Elsewhere") {}
            TabView(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
                Tab("Books", value: 0) { Text("BOOKS") }
                Tab(value: 1, role: .search) { SearchingProbe() }
            }
            .searchable(text: Binding(get: { model.query }, set: { model.query = $0 }))
            .tabViewSearchActivation(activation)
        }
    }

    @discardableResult
    private func frame(_ view: some View, tui: TUIContext, focus: FocusManager) -> String {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("Selecting the search tab activates the search, and ending it goes back")
    func linked() {
        let model = TabSearchModel()
        let tui = TUIContext()
        let focus = FocusManager()
        let view = page(model, activation: .searchTabSelection)
        frame(view, tui: tui, focus: focus)
        frame(view, tui: tui, focus: focus)
        let elsewhere = focus.currentFocusedID
        #expect(frame(view, tui: tui, focus: focus).contains("BOOKS"))

        model.selection = 1
        for _ in 0..<3 { frame(view, tui: tui, focus: focus) }
        #expect(focus.currentFocusedID != elsewhere, "the field takes the focus")
        #expect(frame(view, tui: tui, focus: focus).contains("SEARCHING"))

        // The search ends: the focus leaves the field.
        if let elsewhere { focus.focus(id: elsewhere) }
        for _ in 0..<3 { frame(view, tui: tui, focus: focus) }
        #expect(model.selection == 0, "the tab before is selected again")
    }

    @Test("By default, selecting the search tab leaves the focus where it is")
    func automatic() {
        let model = TabSearchModel()
        let tui = TUIContext()
        let focus = FocusManager()
        let view = page(model, activation: .automatic)
        frame(view, tui: tui, focus: focus)
        frame(view, tui: tui, focus: focus)
        let elsewhere = focus.currentFocusedID
        model.selection = 1
        for _ in 0..<3 { frame(view, tui: tui, focus: focus) }
        #expect(focus.currentFocusedID == elsewhere)
        #expect(frame(view, tui: tui, focus: focus).contains("IDLE"))
    }
}
