//  🖥️ TUI — A Terminal UI framework for Swift
//  SearchScopesTests.swift
//
//  `searchScopes`, through the real input chain: the scopes show under the
//  field while the search is under way, stay while the focus is in them, pick
//  a scope, and go when the search is left.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUISearch
@testable import TUITestSupport

private enum Produce: Hashable { case fruit, vegetable }

/// What the page holds, by reference so the bindings a frame built reach it.
private final class Model {
    var query = ""
    var scope = Produce.fruit
    var text: Binding<String> { Binding(get: { self.query }, set: { self.query = $0 }) }
    var scopeBinding: Binding<Produce> { Binding(get: { self.scope }, set: { self.scope = $0 }) }
}

@MainActor
@Suite("Search scopes", .rendersEnglishUI)
struct SearchScopesTests {
    private let tab = KeyEvent(key: .tab)

    private func page(_ model: Model, _ activation: SearchScopeActivation = .automatic) -> some View {
        VStack { Button("Result") {} }
            .searchable(text: model.text)
            .searchScopes(model.scopeBinding, activation: activation) {
                Text("Fruit").tag(Produce.fruit)
                Text("Vegetable").tag(Produce.vegetable)
            }
    }

    private func showsScopes(_ buffer: FrameBuffer) -> Bool {
        buffer.lines.contains { $0.stripped.contains("Vegetable") }
    }

    @Test("Shown while the field holds the focus, kept while the focus is in them, gone once the search is left")
    func presentationActivation() {
        let harness = InputChainHarness(width: 60, height: 12)
        let model = Model()
        harness.frame(page(model))
        #expect(showsScopes(harness.frame(page(model))), "the field took the focus: search is presented")

        harness.press(tab)  // field → the scope bar, on the selected scope
        #expect(showsScopes(harness.frame(page(model))), "Tab from the field reaches the scopes")
        // The bar is a segmented picker, one focus stop: Right moves its
        // cursor to the second scope, and Return picks it.
        harness.press(KeyEvent(key: .right))
        harness.frame(page(model))
        harness.press(KeyEvent(key: .enter))
        harness.frame(page(model))
        #expect(model.scope == .vegetable, "Return on a scope picks it")

        harness.press(tab)  // → the content
        harness.frame(page(model))
        #expect(!showsScopes(harness.frame(page(model))), "an empty search left behind hides them")
    }

    @Test("A query keeps them shown after the field loses the focus")
    func queryKeepsThem() {
        let harness = InputChainHarness(width: 60, height: 12)
        let model = Model()
        model.query = "app"
        harness.frame(page(model))
        harness.frame(page(model))
        harness.press(tab)
        harness.press(tab)
        harness.press(tab)
        harness.frame(page(model))
        #expect(showsScopes(harness.frame(page(model))))
    }

    @Test("onTextEntry waits for typing")
    func textEntryActivation() {
        let harness = InputChainHarness(width: 60, height: 12)
        let model = Model()
        harness.frame(page(model, .onTextEntry))
        #expect(!showsScopes(harness.frame(page(model, .onTextEntry))), "presented, but nothing typed")
        harness.press(KeyEvent(character: "a"))
        harness.frame(page(model, .onTextEntry))
        #expect(showsScopes(harness.frame(page(model, .onTextEntry))))
    }
}
