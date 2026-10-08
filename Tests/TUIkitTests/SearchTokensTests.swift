//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SearchTokensTests.swift
//
//  The `searchable` forms with tokens, through the real input chain: tokens
//  draw before the text, Backspace in an empty field removes the last,
//  suggested tokens and token completions are chosen from the field's
//  suggestions menu, and an editable token's view changes its token.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

private struct Fruit: Identifiable, Hashable {
    let id: String
    var starred = false
}

/// What the page holds, by reference so the bindings a frame built reach it.
private final class Model {
    var query = ""
    var tokens: [Fruit] = [Fruit(id: "Apple"), Fruit(id: "Pear")]
    var suggested: [Fruit] = [Fruit(id: "Apple"), Fruit(id: "Fig")]

    var text: Binding<String> { Binding(get: { self.query }, set: { self.query = $0 }) }
    var tokenBinding: Binding<[Fruit]> { Binding(get: { self.tokens }, set: { self.tokens = $0 }) }
    var suggestedBinding: Binding<[Fruit]> {
        Binding(get: { self.suggested }, set: { self.suggested = $0 })
    }
}

@MainActor
@Suite("Search tokens", .rendersEnglishUI)
struct SearchTokensTests {
    private let backspace = KeyEvent(key: .backspace)

    private func page(_ model: Model) -> some View {
        VStack { Button("Result") {} }
            .searchable(text: model.text, tokens: model.tokenBinding) { Text($0.id) }
    }

    private func line(_ buffer: FrameBuffer, containing text: String) -> String? {
        buffer.lines.map(\.stripped).first { $0.contains(text) }
    }

    /// The frame's lines with the pop-up overlays composited in — a
    /// suggestions menu is an overlay, so it is not in `buffer.lines` until
    /// that happens.
    private func screen(_ buffer: FrameBuffer) -> [String] {
        buffer.compositingOverlays(maxWidth: 50, maxHeight: 12, palette: EnvironmentValues().palette)
            .lines.map(\.stripped)
    }

    /// A page with suggested tokens, and the given search suggestions.
    private func suggestingPage(_ model: Model, @ViewBuilder suggestions: () -> some View) -> some View {
        VStack { Button("Result") {} }
            .searchable(text: model.text, tokens: model.tokenBinding, suggestedTokens: model.suggestedBinding) {
                Text($0.id)
            }
            .searchSuggestions(suggestions)
    }

    @Test("Tokens draw in the field before the text")
    func tokensDraw() throws {
        let harness = InputChainHarness(width: 50, height: 10)
        let model = Model()
        model.query = "app"
        harness.frame(page(model))
        let fieldLine = try #require(line(harness.frame(page(model)), containing: "app"))
        let apple = try #require(fieldLine.range(of: "[Apple]"))
        let pear = try #require(fieldLine.range(of: "[Pear]"))
        let query = try #require(fieldLine.range(of: "app", range: pear.upperBound..<fieldLine.endIndex))
        #expect(apple.upperBound <= pear.lowerBound && pear.upperBound <= query.lowerBound)
    }

    @Test("Backspace in an empty field removes the last token; with text it deletes text")
    func backspaceRemovesLast() {
        let harness = InputChainHarness(width: 50, height: 10)
        let model = Model()
        model.query = "a"
        harness.frame(page(model))
        harness.frame(page(model))
        harness.press(backspace)
        harness.frame(page(model))
        #expect(model.query.isEmpty && model.tokens.count == 2, "the first Backspace takes the text")
        harness.press(backspace)
        harness.frame(page(model))
        #expect(model.tokens.map(\.id) == ["Apple"], "the next takes the last token")
    }

    @Test("Suggested tokens are offered in the suggestions menu, and choosing one adds it")
    func suggestedTokens() {
        let harness = InputChainHarness(width: 50, height: 12)
        let model = Model()
        model.tokens = []
        let page = { self.suggestingPage(model) { EmptyView() } }
        harness.frame(page())
        let closed = screen(harness.frame(page()))
        #expect(!closed.contains { $0.contains("Fig") }, "nothing is offered until the menu opens: \(closed)")
        harness.press(KeyEvent(key: .down))  // opens the menu at its first row, Apple
        let open = screen(harness.frame(page()))
        #expect(open.contains { $0.contains("[Apple]") } && open.contains { $0.contains("[Fig]") }, "\(open)")
        harness.press(KeyEvent(key: .enter))
        harness.frame(page())
        #expect(model.tokens.map(\.id) == ["Apple"])
        harness.press(KeyEvent(key: .down))
        let again = screen(harness.frame(page()))
        #expect(again.contains { $0.contains("[Fig]") }, "\(again)")
        // Once: the chip in the field, and no row of the menu.
        #expect(
            again.joined().components(separatedBy: "[Apple]").count == 2,
            "a chosen token is not offered again: \(again)")
    }

    @Test("Suggested tokens come above the search suggestions, and only while nothing is typed")
    func suggestedTokensComeFirst() throws {
        let harness = InputChainHarness(width: 50, height: 12)
        let model = Model()
        model.tokens = []
        let page = { self.suggestingPage(model) { Text("apricot") } }
        harness.frame(page())
        harness.frame(page())
        harness.press(KeyEvent(key: .down))
        let open = screen(harness.frame(page()))
        let fig = try #require(open.firstIndex { $0.contains("[Fig]") }, "\(open)")
        let apricot = try #require(open.firstIndex { $0.contains("apricot") }, "\(open)")
        #expect(fig < apricot, "the tokens are the first group: \(open)")

        harness.press(KeyEvent(key: .escape))
        harness.frame(page())
        harness.press(KeyEvent(key: .character("a")))
        harness.frame(page())
        harness.press(KeyEvent(key: .down))
        let typed = screen(harness.frame(page()))
        #expect(typed.contains { $0.contains("apricot") }, "\(typed)")
        #expect(!typed.contains { $0.contains("[Fig]") }, "a typed query hides the suggested tokens: \(typed)")
    }

    @Test("A token completion empties the field and adds its token; a chosen one is ticked")
    func tokenCompletion() {
        let harness = InputChainHarness(width: 50, height: 12)
        let model = Model()
        model.tokens = [Fruit(id: "Apple")]
        model.suggested = []
        let page = {
            self.suggestingPage(model) {
                Text("Apple").searchCompletion(Fruit(id: "Apple"))
                Text("Fig").searchCompletion(Fruit(id: "Fig"))
            }
        }
        harness.frame(page())
        harness.frame(page())
        harness.press(KeyEvent(key: .character("f")))
        harness.frame(page())
        harness.press(KeyEvent(key: .down))
        let open = screen(harness.frame(page()))
        #expect(open.contains { $0.contains("✓") && $0.contains("[Apple]") }, "a chosen token is ticked: \(open)")
        harness.press(KeyEvent(key: .down))  // Apple → Fig
        harness.frame(page())
        harness.press(KeyEvent(key: .enter))
        harness.frame(page())
        #expect(model.tokens.map(\.id) == ["Apple", "Fig"])
        #expect(model.query.isEmpty, "the token replaces the partial text")
    }

    @Test("A token completion is left out where the searchable takes no tokens")
    func tokenCompletionWithoutTokens() {
        let harness = InputChainHarness(width: 50, height: 12)
        let model = Model()
        let page = {
            VStack { Button("Result") {} }
                .searchable(text: model.text)
                .searchSuggestions {
                    Text("Fig").searchCompletion(Fruit(id: "Fig"))
                    Text("figs")
                }
        }
        harness.frame(page())
        harness.frame(page())
        harness.press(KeyEvent(key: .down))
        let open = screen(harness.frame(page()))
        #expect(open.contains { $0.contains("figs") }, "\(open)")
        #expect(!open.contains { $0.contains("[Fig]") }, "\(open)")
    }

    @Test("An editable token's view changes its token")
    func editableTokens() {
        let harness = InputChainHarness(width: 50, height: 10)
        let model = Model()
        model.tokens = [Fruit(id: "Apple")]
        let page = {
            VStack { Button("Result") {} }
                .searchable(text: model.text, editableTokens: model.tokenBinding) { $token in
                    Button(token.starred ? "*\(token.id)" : token.id) { token.starred.toggle() }
                }
        }
        harness.frame(page())
        harness.frame(page())
        // The token's button comes before the field in the ring, so it is
        // the page's first stop.
        harness.press(KeyEvent(key: .enter))
        harness.frame(page())
        #expect(model.tokens.first?.starred == true, "the token's view wrote through its binding")
    }
}
