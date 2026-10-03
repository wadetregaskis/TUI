//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SearchTokensTests.swift
//
//  The `searchable` forms with tokens, through the real input chain: tokens
//  draw before the text, Backspace in an empty field removes the last,
//  suggested tokens are chosen from a row under the field, and an editable
//  token's view changes its token.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

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

    @Test("Suggested tokens are offered under an empty field, and choosing one adds it")
    func suggestedTokens() {
        let harness = InputChainHarness(width: 50, height: 10)
        let model = Model()
        model.tokens = []
        let page = {
            VStack { Button("Result") {} }
                .searchable(text: model.text, tokens: model.tokenBinding, suggestedTokens: model.suggestedBinding) {
                    Text($0.id)
                }
        }
        harness.frame(page())
        let offered = harness.frame(page())
        #expect(line(offered, containing: "Fig") != nil, "the field holds the focus, empty: suggestions show")
        harness.press(KeyEvent(key: .tab))  // field → the first suggestion, Apple
        harness.frame(page())
        harness.press(KeyEvent(key: .enter))
        let after = harness.frame(page())
        #expect(model.tokens.map(\.id) == ["Apple"])
        #expect(
            !(after.lines.map(\.stripped).contains { $0.contains("Apple") && $0.contains("Fig") }),
            "a chosen suggestion is not offered again")
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
