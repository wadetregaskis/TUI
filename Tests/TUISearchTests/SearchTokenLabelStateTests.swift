//  🖥️ TUI — A Terminal UI framework for Swift
//  SearchTokenLabelStateTests.swift
//
//  A searchable's suggested tokens are drawn in the field's suggestions menu
//  by the app's `token` view, and that view keeps `@State` of its own: apart
//  from the field's slots, apart from the other tokens' labels, and with its
//  token as the tokens before it are chosen.
//
//  The field drew every suggestion's label at its own identity, where its
//  handler and focus id live at indices 0…, and a suggested token's label is
//  the app's view itself (not a `Subview`, which draws where it resolved): its
//  first `@State` landed on the handler's key, so the two replaced each
//  other's box every frame, and every token's label shared one box.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUISearch
@testable import TUITestSupport

private struct Fruit: Identifiable, Hashable {
    let id: String
}

/// What the page holds, by reference so the bindings a frame built reach it,
/// and a way for the test to write each token label's state, as a key would.
@MainActor
private final class Model {
    var query = ""
    var tokens: [Fruit] = []
    var suggested: [Fruit] = [Fruit(id: "Apple"), Fruit(id: "Fig"), Fruit(id: "Kiwi")]
    var writers: [String: (String) -> Void] = [:]

    var text: Binding<String> { Binding(get: { self.query }, set: { self.query = $0 }) }
    var tokenBinding: Binding<[Fruit]> { Binding(get: { self.tokens }, set: { self.tokens = $0 }) }
    var suggestedBinding: Binding<[Fruit]> {
        Binding(get: { self.suggested }, set: { self.suggested = $0 })
    }
}

/// A token's label, with a note the test writes and a count its appearance
/// writes: `@State` of two types, so sharing a key with a slot of the field's,
/// whatever its type, replaces one of the boxes each frame.
private struct NotedToken: View {
    let fruit: Fruit
    let model: Model
    @State private var note = ""
    @State private var count = 0

    var body: some View {
        model.writers[fruit.id] = { note = $0 }
        return Text(verbatim: "\(fruit.id)\(note)\(count)").onAppear { count = 7 }
    }
}

@MainActor
@Suite("A suggested token's label keeps its own @State", .rendersEnglishUI)
struct SearchTokenLabelStateTests {
    /// Find, ⌃F: the keys into the search field.
    private let find = KeyEvent(key: .character("f"), ctrl: true)

    private func page(_ model: Model) -> some View {
        VStack { Button("Result") {} }
            .searchable(text: model.text, tokens: model.tokenBinding, suggestedTokens: model.suggestedBinding) {
                NotedToken(fruit: $0, model: model)
            }
    }

    /// The frame's lines with the suggestions menu, an overlay, composited in.
    private func screen(_ buffer: FrameBuffer) -> String {
        buffer.compositingOverlays(maxWidth: 50, maxHeight: 12, palette: EnvironmentValues().palette)
            .lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("Each token's label keeps its own state, with its token, and the menu still opens and adds")
    func tokenLabelsKeepTheirState() throws {
        let harness = InputChainHarness(width: 50, height: 12)
        let model = Model()
        harness.frame(page(model))
        harness.press(find)
        harness.frame(page(model))
        model.writers["Fig"]?("+f")
        harness.frame(page(model))
        harness.press(KeyEvent(key: .down))  // opens the menu at its first row, Apple
        let open = screen(harness.frame(page(model)))
        try #require(open.contains("[Fig+f7]"), "the menu opens, Fig keeps its state: \(open)")
        #expect(open.contains("[Apple7]") && open.contains("[Kiwi7]"), "each keeps its own: \(open)")
        harness.press(KeyEvent(key: .enter))
        harness.frame(page(model))
        #expect(model.tokens.map(\.id) == ["Apple"], "the menu added the token")
        harness.press(KeyEvent(key: .down))
        let again = screen(harness.frame(page(model)))
        #expect(again.contains("[Fig+f7]"), "Fig, first now, kept its own state: \(again)")
        #expect(again.contains("[Kiwi7]"), "Kiwi was handed Fig's state: \(again)")
    }
}
